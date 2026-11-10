import SwiftUI
import AppKit
import CoreGraphics
import IOKit

// MARK: - Built-in brightness (DisplayServices)

enum BuiltInBrightness {
    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_NOW
    )
    private static let getFn: GetFn? = handle.flatMap { symbol("DisplayServicesGetBrightness", as: GetFn.self, in: $0) }
    private static let setFn: SetFn? = handle.flatMap { symbol("DisplayServicesSetBrightness", as: SetFn.self, in: $0) }
    private static let canFn: CanFn? = handle.flatMap { symbol("DisplayServicesCanChangeBrightness", as: CanFn.self, in: $0) }

    private static func symbol<T>(_ name: String, as type: T.Type, in handle: UnsafeMutableRawPointer) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var available: Bool { getFn != nil && setFn != nil }

    static func canChange(_ id: CGDirectDisplayID) -> Bool {
        canFn?(id) ?? (getFn != nil)
    }

    static func read(_ id: CGDirectDisplayID) -> Double? {
        guard let getFn else { return nil }
        var value: Float = 0
        guard getFn(id, &value) == 0 else { return nil }
        return Double(max(0, min(1, value)))
    }

    static func write(_ id: CGDirectDisplayID, _ value: Double) {
        guard let setFn else { return }
        _ = setFn(id, Float(max(0, min(1, value))))
    }
}

// MARK: - DDC over I2C (external displays)

final class DDCService {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias WriteFn = @convention(c) (CFTypeRef?, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, UInt32) -> IOReturn
    private typealias ReadFn = @convention(c) (CFTypeRef?, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, UInt32) -> IOReturn

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let createFn: CreateFn? = handle.flatMap { pointer in
        guard let symbol = dlsym(pointer, "IOAVServiceCreateWithService") else { return nil }
        return unsafeBitCast(symbol, to: CreateFn.self)
    }
    private static let writeFn: WriteFn? = handle.flatMap { pointer in
        guard let symbol = dlsym(pointer, "IOAVServiceWriteI2C") else { return nil }
        return unsafeBitCast(symbol, to: WriteFn.self)
    }
    private static let readFn: ReadFn? = handle.flatMap { pointer in
        guard let symbol = dlsym(pointer, "IOAVServiceReadI2C") else { return nil }
        return unsafeBitCast(symbol, to: ReadFn.self)
    }

    private static let address: UInt8 = 0x37
    private static let dataAddress: UInt8 = 0x51

    private let service: CFTypeRef

    init?(service: CFTypeRef) {
        guard Self.writeFn != nil, Self.readFn != nil else { return nil }
        self.service = service
    }

    static var isAvailable: Bool { createFn != nil && writeFn != nil && readFn != nil }

    /// Every `DCPAVServiceProxy` whose Location is External, in registry order.
    static func externalServices() -> [CFTypeRef] {
        guard let createFn else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var services: [CFTypeRef] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let raw = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let location = raw as? String,
                  location == "External" else { continue }
            if let av = createFn(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                services.append(av)
            }
        }
        return services
    }

    private static func checksum(_ start: UInt8, _ packet: [UInt8], through end: Int) -> UInt8 {
        var value = start
        for index in 0...end { value ^= packet[index] }
        return value
    }

    private func writePacket(_ packet: inout [UInt8]) -> Bool {
        guard let writeFn = Self.writeFn else { return false }
        return packet.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return writeFn(service, UInt32(Self.address), UInt32(Self.dataAddress), base, UInt32(buffer.count)) == kIOReturnSuccess
        }
    }

    private func transact(send: [UInt8], replyLength: Int) -> [UInt8]? {
        guard Self.writeFn != nil, Self.readFn != nil else { return nil }
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let base: UInt8 = send.count == 1
            ? Self.address << 1
            : (Self.address << 1) ^ Self.dataAddress
        packet[packet.count - 1] = Self.checksum(base, packet, through: packet.count - 2)

        for _ in 0..<4 {
            for _ in 0..<2 {
                usleep(10_000)
                _ = writePacket(&packet)
            }
            guard replyLength > 0, let readFn = Self.readFn else { return packet }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: replyLength)
            let status = reply.withUnsafeMutableBufferPointer { buffer -> IOReturn in
                guard let base = buffer.baseAddress else { return kIOReturnError }
                return readFn(service, UInt32(Self.address), 0, base, UInt32(buffer.count))
            }
            if status == kIOReturnSuccess,
               reply.count >= 10,
               Self.checksum(0x50, reply, through: reply.count - 2) == reply[reply.count - 1] {
                return reply
            }
            usleep(20_000)
        }
        return nil
    }

    /// Returns the current and maximum raw value for a VCP code.
    func read(_ control: UInt8) -> (current: Double, max: Double)? {
        guard let reply = transact(send: [control], replyLength: 11) else { return nil }
        let maximum = Double(reply[6]) * 256 + Double(reply[7])
        let current = Double(reply[8]) * 256 + Double(reply[9])
        guard maximum > 0 else { return nil }
        return (min(current, maximum), maximum)
    }

    /// Writes a raw value. Returns false when the monitor did not acknowledge.
    func write(_ control: UInt8, value: Double, max maximum: Double) -> Bool {
        let clamped = max(0, min(maximum, value))
        let raw = UInt16(clamped.rounded())
        guard transact(send: [control, UInt8(raw >> 8), UInt8(raw & 0xFF)], replyLength: 0) != nil else {
            return false
        }
        return true
    }
}

// MARK: - Display state

@MainActor
final class ExternalDisplayState: ObservableObject, Identifiable {
    enum Control: String {
        case brightness, contrast, volume
        var vcp: UInt8 {
            switch self {
            case .brightness: return 0x10
            case .contrast: return 0x12
            case .volume: return 0x62
            }
        }
        var title: String { rawValue.capitalized }
    }

    let id: CGDirectDisplayID
    let name: String
    private let ddc: DDCService?

    @Published var brightness: Double = 50
    @Published var contrast: Double = 50
    @Published var volume: Double = 50
    @Published var brightnessMax: Double = 100
    @Published var contrastMax: Double = 100
    @Published var volumeMax: Double = 100
    @Published var supportsBrightness = true
    @Published var supportsContrast = true
    @Published var supportsVolume = true
    @Published var error: String?
    @Published var loaded = false

    init(id: CGDirectDisplayID, name: String, ddc: DDCService?) {
        self.id = id
        self.name = name
        self.ddc = ddc
    }

    var hasDDC: Bool { ddc != nil }

    func load() {
        guard let ddc else {
            supportsBrightness = false
            supportsContrast = false
            supportsVolume = false
            loaded = true
            return
        }
        Task.detached(priority: .userInitiated) {
            let values: [(Control, (current: Double, max: Double)?)] = [
                (.brightness, ddc.read(Control.brightness.vcp)),
                (.contrast, ddc.read(Control.contrast.vcp)),
                (.volume, ddc.read(Control.volume.vcp))
            ]
            await MainActor.run {
                for (control, value) in values {
                    guard let value else {
                        switch control {
                        case .brightness: self.supportsBrightness = false
                        case .contrast: self.supportsContrast = false
                        case .volume: self.supportsVolume = false
                        }
                        continue
                    }
                    let percent = (value.current / value.max) * 100
                    switch control {
                    case .brightness:
                        self.brightnessMax = value.max
                        self.brightness = percent
                    case .contrast:
                        self.contrastMax = value.max
                        self.contrast = percent
                    case .volume:
                        self.volumeMax = value.max
                        self.volume = percent
                    }
                }
                self.loaded = true
                if !self.supportsBrightness && !self.supportsContrast && !self.supportsVolume {
                    self.error = "This monitor did not answer DDC. Many USB-C hubs and some adapters block the control channel."
                }
            }
        }
    }

    func apply(_ control: Control) {
        guard let ddc else { return }
        let percent: Double
        let maximum: Double
        switch control {
        case .brightness: percent = brightness; maximum = brightnessMax
        case .contrast: percent = contrast; maximum = contrastMax
        case .volume: percent = volume; maximum = volumeMax
        }
        let raw = (percent / 100) * maximum
        let vcp = control.vcp
        Task.detached(priority: .userInitiated) {
            let ok = ddc.write(vcp, value: raw, max: maximum)
            await MainActor.run {
                if ok {
                    self.error = nil
                } else {
                    self.error = "DDC did not acknowledge \(control.title.lowercased()). The monitor or adapter may not support it."
                }
            }
        }
    }
}

@MainActor
final class DisplayControlService: ObservableObject {
    static let shared = DisplayControlService()

    @Published var builtinID: CGDirectDisplayID?
    @Published var builtinName = "Built-in display"
    @Published var builtinBrightness: Double = 0.5
    @Published var builtinAvailable = false
    @Published var external: [ExternalDisplayState] = []
    @Published var status = ""
    @Published var lastError: String?

    func refresh() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        ids = Array(ids.prefix(Int(count)))

        func screenName(_ id: CGDirectDisplayID) -> String? {
            NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }?.localizedName
        }

        if let builtin = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            builtinID = builtin
            builtinName = screenName(builtin) ?? "Built-in display"
            builtinAvailable = BuiltInBrightness.available && BuiltInBrightness.canChange(builtin)
            if let value = BuiltInBrightness.read(builtin) {
                builtinBrightness = value
            }
        } else {
            builtinID = nil
            builtinAvailable = false
        }

        let externalIDs = ids.filter { CGDisplayIsBuiltin($0) == 0 }
        let services = DDCService.externalServices()
        external = externalIDs.enumerated().map { index, id in
            let av = index < services.count ? services[index] : nil
            let ddc = av.flatMap { DDCService(service: $0) }
            return ExternalDisplayState(
                id: id,
                name: screenName(id) ?? "External display \(index + 1)",
                ddc: ddc
            )
        }
        external.forEach { $0.load() }

        if externalIDs.isEmpty {
            status = "No external displays are connected."
        } else {
            let withDDC = external.filter(\.hasDDC).count
            status = "\(withDDC) of \(externalIDs.count) external display\(externalIDs.count == 1 ? "" : "s") accepted a DDC connection."
        }
        lastError = DDCService.isAvailable ? nil : "The I2C display service is not available on this Mac."
    }

    func setBuiltin(_ value: Double) {
        builtinBrightness = value
        guard let builtinID else { return }
        BuiltInBrightness.write(builtinID, value)
    }
}

// MARK: - Display Control UI

struct DisplayControlTool: View {
    @StateObject private var service = DisplayControlService.shared

    var body: some View {
        ToolPage(symbol: "display.2", title: "Display Control", subtitle: "Brightness for the built-in screen and, when the monitor and cable allow it, brightness, contrast and volume for external displays over DDC.") {
            if service.builtinAvailable {
                ToolCard(title: service.builtinName, subtitle: "Built-in display") {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.min")
                            .foregroundStyle(Theme.textTertiary)
                        Slider(value: Binding(
                            get: { service.builtinBrightness },
                            set: { service.setBuiltin($0) }
                        ), in: 0...1)
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(Theme.ember)
                        Text("\(Int(service.builtinBrightness * 100))%")
                            .font(Theme.mono)
                            .frame(width: 44, alignment: .trailing)
                    }
                    Text("Changes apply straight away and survive a restart because macOS stores its own brightness value.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if service.external.isEmpty {
                ToolCard(title: "External displays") {
                    Text("Connect a monitor to change its brightness, contrast and volume here. Nookit uses DDC/CI, which most DisplayPort and HDMI monitors support; some USB-C hubs pass only video and block the control channel.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                ForEach(service.external) { display in
                    ExternalDisplayCard(display: display)
                }
            }

            ToolCard(title: "How this works") {
                Text("Built-in brightness uses the same DisplayServices channel as the brightness keys. External controls are sent as DDC/CI over the display cable, with no driver, daemon or background helper.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                if !service.status.isEmpty {
                    Text(service.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                if let error = service.lastError { InlineError(message: error) }
                HStack(spacing: 10) {
                    Button("Refresh displays") { service.refresh() }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                }
                Text("Volume only appears for monitors with speakers that expose a volume control. If a slider is missing, the monitor did not report that control.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .task { service.refresh() }
    }
}

private struct ExternalDisplayCard: View {
    @ObservedObject var display: ExternalDisplayState

    var body: some View {
        ToolCard(title: display.name, subtitle: display.hasDDC ? "DDC/CI over the display cable" : "No DDC connection") {
            if !display.hasDDC {
                Text("macOS did not expose an external display control channel for this screen. Try a direct DisplayPort or HDMI cable; hubs and adapters often drop DDC.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            } else if !display.loaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the monitor…").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            } else {
                if display.supportsBrightness {
                    row(control: .brightness, value: $display.brightness, max: display.brightnessMax, icon: "sun.max.fill")
                }
                if display.supportsContrast {
                    row(control: .contrast, value: $display.contrast, max: display.contrastMax, icon: "circle.lefthalf.filled")
                }
                if display.supportsVolume {
                    row(control: .volume, value: $display.volume, max: display.volumeMax, icon: "speaker.wave.2.fill")
                }
                if !display.supportsBrightness && !display.supportsContrast && !display.supportsVolume {
                    Text("This monitor answered, but did not report brightness, contrast or volume controls.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let error = display.error { InlineError(message: error) }
                Text("Values are applied when you let go of a slider.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func row(control: ExternalDisplayState.Control, value: Binding<Double>, max maximum: Double, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 18)
            Slider(value: value, in: 0...100, onEditingChanged: { editing in
                if !editing { display.apply(control) }
            })
            Text("\(Int(value.wrappedValue))%")
                .font(Theme.mono)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - Scroll fixer

struct ScrollConfig {
    var invertWheel = false
    var invertPrecision = false
    var wheelSpeed = 1.0
    var precisionSpeed = 1.0
    var smoothing = 0.0
}

@MainActor
final class ScrollFixer: ObservableObject {
    static let shared = ScrollFixer()

    @Published var running = false {
        didSet { UserDefaults.standard.set(running, forKey: "scrollFixer.running") }
    }
    @Published var invertWheel = false { didSet { updateConfig() } }
    @Published var invertPrecision = false { didSet { updateConfig() } }
    @Published var wheelSpeed = 1.0 { didSet { updateConfig() } }
    @Published var precisionSpeed = 1.0 { didSet { updateConfig() } }
    @Published var smoothing = 0.0 { didSet { updateConfig() } }
    @Published var status = ""
    @Published var error: String?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let lock = NSLock()
    private var config = ScrollConfig()
    private var smooth1 = 0.0
    private var smooth2 = 0.0

    private init() {
        invertWheel = UserDefaults.standard.bool(forKey: "scrollFixer.invertWheel")
        invertPrecision = UserDefaults.standard.bool(forKey: "scrollFixer.invertPrecision")
        let wheel = UserDefaults.standard.double(forKey: "scrollFixer.wheelSpeed")
        let precision = UserDefaults.standard.double(forKey: "scrollFixer.precisionSpeed")
        let smoothing = UserDefaults.standard.double(forKey: "scrollFixer.smoothing")
        wheelSpeed = wheel == 0 ? 1 : wheel
        precisionSpeed = precision == 0 ? 1 : precision
        self.smoothing = max(0, min(0.9, smoothing))
        updateConfig()
        running = UserDefaults.standard.bool(forKey: "scrollFixer.running")
    }

    private func updateConfig() {
        lock.lock()
        config = ScrollConfig(
            invertWheel: invertWheel,
            invertPrecision: invertPrecision,
            wheelSpeed: wheelSpeed,
            precisionSpeed: precisionSpeed,
            smoothing: smoothing
        )
        lock.unlock()
        UserDefaults.standard.set(invertWheel, forKey: "scrollFixer.invertWheel")
        UserDefaults.standard.set(invertPrecision, forKey: "scrollFixer.invertPrecision")
        UserDefaults.standard.set(wheelSpeed, forKey: "scrollFixer.wheelSpeed")
        UserDefaults.standard.set(precisionSpeed, forKey: "scrollFixer.precisionSpeed")
        UserDefaults.standard.set(smoothing, forKey: "scrollFixer.smoothing")
    }

    func resumeIfNeeded() {
        guard running, !isActive else { return }
        start()
    }

    var isActive: Bool { tap != nil }

    func start() {
        guard !isActive else { return }
        guard AXIsProcessTrusted() else {
            error = "Scroll tuning needs Accessibility access. Turn on Nookit in System Settings → Privacy & Security → Accessibility, then press Start again."
            status = ""
            return
        }
        let mask = (1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, reference in
            guard let reference else { return Unmanaged.passUnretained(event) }
            let fixer = Unmanaged<ScrollFixer>.fromOpaque(reference).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                fixer.reenable()
                return Unmanaged.passUnretained(event)
            }
            if let changed = fixer.modify(event) {
                return Unmanaged.passRetained(changed)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            error = "macOS refused the scroll tap. Check Accessibility access for Nookit."
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        running = true
        error = nil
        status = "Tuning scroll for as long as Nookit is open."
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        running = false
        status = "Scroll tuning is off."
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func modify(_ event: CGEvent) -> CGEvent? {
        lock.lock()
        let current = config
        lock.unlock()

        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let invert = continuous ? current.invertPrecision : current.invertWheel
        let speed = continuous ? current.precisionSpeed : current.wheelSpeed
        let smoothing = current.smoothing
        guard invert || abs(speed - 1) > 0.001 || smoothing > 0.001 else { return nil }
        guard let copy = event.copy() else { return nil }

        func adjust(axis: Int) {
            let deltaField: CGEventField = axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
            let pointField: CGEventField = axis == 1 ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2
            let fixedField: CGEventField = axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2

            var delta = Double(event.getIntegerValueField(deltaField))
            var point = Double(event.getIntegerValueField(pointField))
            let fixed = event.getDoubleValueField(fixedField)
            guard delta != 0 || point != 0 || fixed != 0 else { return }

            let direction = invert ? -1.0 : 1.0
            delta *= speed * direction
            point *= speed * direction

            if smoothing > 0.001 && !continuous {
                var smoothed = axis == 1 ? smooth1 : smooth2
                smoothed = smoothed * smoothing + delta * (1 - smoothing)
                let whole = smoothed.rounded(.towardZero)
                if axis == 1 { smooth1 = smoothed - whole } else { smooth2 = smoothed - whole }
                delta = whole
                point = whole
            }

            copy.setIntegerValueField(deltaField, value: Int64(delta.rounded()))
            copy.setIntegerValueField(pointField, value: Int64(point.rounded()))
            let scaledFixed = fixed * speed * direction
            copy.setDoubleValueField(fixedField, value: scaledFixed)
        }

        adjust(axis: 1)
        adjust(axis: 2)
        return copy
    }
}

// MARK: - Mouse Fixes UI

struct MouseFixesTool: View {
    @StateObject private var fixer = ScrollFixer.shared
    @State private var naturalScrolling = true
    @State private var reloadToken = UUID()

    var body: some View {
        ToolPage(symbol: "computermouse", title: "Mouse Fixes", subtitle: "Scroll the way each device wants: flip the wheel without flipping the trackpad, and tune speed and smoothing separately. Runs while Nookit is open.") {
            ToolCard(title: "Direction") {
                Text("macOS has one “Natural scrolling” switch for every pointing device. Nookit can invert the wheel and the trackpad separately while it is running, so a mouse can scroll one way and the trackpad the other.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                Toggle("Invert the scroll wheel", isOn: $fixer.invertWheel)
                    .toggleStyle(.switch)
                Toggle("Invert the trackpad (and Magic Mouse)", isOn: $fixer.invertPrecision)
                    .toggleStyle(.switch)
                Divider().opacity(0.3)
                HStack(spacing: 12) {
                    Toggle("macOS Natural scrolling", isOn: Binding(
                        get: { naturalScrolling },
                        set: { value in
                            naturalScrolling = value
                            setNaturalScrolling(value)
                        }
                    ))
                    .toggleStyle(.switch)
                    Spacer()
                    Text("Affects every device and every app. Some apps only pick it up after they restart.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.trailing)
                }
            }

            ToolCard(title: "Speed and smoothing") {
                sliderRow(title: "Wheel speed", value: $fixer.wheelSpeed, range: 0.4...2.5, format: "%.1f×")
                sliderRow(title: "Trackpad speed", value: $fixer.precisionSpeed, range: 0.4...2.5, format: "%.1f×")
                HStack(spacing: 12) {
                    Text("Smoothing").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary).frame(width: 108, alignment: .leading)
                    Slider(value: $fixer.smoothing, in: 0...0.85)
                    Text("\(Int(fixer.smoothing * 100))%").font(Theme.mono).frame(width: 44, alignment: .trailing)
                }
                Text("Smoothing averages quick wheel steps so very slow scrolling moves in smaller, steadier increments. It is skipped for trackpad gestures, which macOS already smooths.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 10) {
                    if fixer.running {
                        Button("Stop tuning") { fixer.stop() }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button("Start tuning") { fixer.start() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Reset to 1×") {
                        fixer.wheelSpeed = 1
                        fixer.precisionSpeed = 1
                        fixer.smoothing = 0
                        fixer.invertWheel = false
                        fixer.invertPrecision = false
                    }
                    .buttonStyle(QuietButtonStyle())
                    Spacer()
                }
                if !fixer.status.isEmpty {
                    Text(fixer.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                if let error = fixer.error { InlineError(message: error) }
            }

            ToolCard(title: "Permission") {
                Text("Seeing and changing scroll events requires Accessibility access. Nookit does not record what you scroll, and the tap disappears the moment you press Stop or quit the app.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                Button("Open Accessibility settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .task {
            naturalScrolling = readNaturalScrolling()
            fixer.resumeIfNeeded()
        }
        .id(reloadToken)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary).frame(width: 108, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue)).font(Theme.mono).frame(width: 44, alignment: .trailing)
        }
    }

    private func readNaturalScrolling() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "NSGlobalDomain", "com.apple.swipescrolldirection"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return true }
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return text != "0" && text != "false"
    }

    private func setNaturalScrolling(_ value: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "NSGlobalDomain", "com.apple.swipescrolldirection", "-bool", value ? "true" : "false"]
        try? process.run()
        process.waitUntilExit()
    }
}
