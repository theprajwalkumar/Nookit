import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers

// MARK: - Coordinate formatting

enum CoordinateMath {
    static func dms(_ value: Double, latitude: Bool) -> String {
        let hemisphere: String
        if latitude {
            hemisphere = value >= 0 ? "N" : "S"
        } else {
            hemisphere = value >= 0 ? "E" : "W"
        }
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutesFull = (absolute - Double(degrees)) * 60
        let minutes = Int(minutesFull)
        let seconds = (minutesFull - Double(minutes)) * 60
        return String(format: "%d° %02d′ %05.2f″ %@", degrees, minutes, seconds, hemisphere)
    }

    static func ddm(_ value: Double, latitude: Bool) -> String {
        let hemisphere = latitude ? (value >= 0 ? "N" : "S") : (value >= 0 ? "E" : "W")
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutes = (absolute - Double(degrees)) * 60
        return String(format: "%d° %06.3f′ %@", degrees, minutes, hemisphere)
    }

    static func decimalPair(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    static func utm(_ coordinate: CLLocationCoordinate2D) -> String {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        guard latitude >= -80, latitude <= 84 else {
            return "Not defined outside 80°S to 84°N"
        }
        let a = 6_378_137.0
        let flattening = 1 / 298.257_223_563
        let eccentricity = flattening * (2 - flattening)
        let k0 = 0.9996
        let zone = Int(floor((longitude + 180) / 6)) + 1
        let centralMeridian = Double(zone - 1) * 6 - 180 + 3

        let latitudeRadians = latitude * .pi / 180
        let longitudeRadians = longitude * .pi / 180
        let centralRadians = centralMeridian * .pi / 180
        let eccentricitySquared = eccentricity / (1 - eccentricity)
        let n = a / sqrt(1 - eccentricity * pow(sin(latitudeRadians), 2))
        let t = pow(tan(latitudeRadians), 2)
        let c = eccentricitySquared * pow(cos(latitudeRadians), 2)
        let aa = cos(latitudeRadians) * (longitudeRadians - centralRadians)
        let m = a * (
            (1 - eccentricity / 4 - 3 * pow(eccentricity, 2) / 64 - 5 * pow(eccentricity, 3) / 256) * latitudeRadians
            - (3 * eccentricity / 8 + 3 * pow(eccentricity, 2) / 32 + 45 * pow(eccentricity, 3) / 1024) * sin(2 * latitudeRadians)
            + (15 * pow(eccentricity, 2) / 256 + 45 * pow(eccentricity, 3) / 1024) * sin(4 * latitudeRadians)
            - (35 * pow(eccentricity, 3) / 3072) * sin(6 * latitudeRadians)
        )
        let easting = k0 * n * (
            aa + (1 - t + c) * pow(aa, 3) / 6
            + (5 - 18 * t + pow(t, 2) + 72 * c - 58 * eccentricitySquared) * pow(aa, 5) / 120
        ) + 500_000
        var northing = k0 * (
            m + n * tan(latitudeRadians) * (
                pow(aa, 2) / 2
                + (5 - t + 9 * c + 4 * pow(c, 2)) * pow(aa, 4) / 24
                + (61 - 58 * t + pow(t, 2) + 600 * c - 330 * eccentricitySquared) * pow(aa, 6) / 720
            )
        )
        if latitude < 0 { northing += 10_000_000 }
        let band = latitudeBand(latitude)
        return String(format: "%d%@ %.0f m E, %.0f m N", zone, band, easting, northing)
    }

    static func latitudeBand(_ latitude: Double) -> String {
        let bands = Array("CDEFGHJKLMNPQRSTUVWX")
        var index = Int(floor((latitude + 80) / 8))
        index = max(0, min(bands.count - 1, index))
        return String(bands[index])
    }

    static func distance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let radius = 6_371_008.8
        let latitude1 = start.latitude * .pi / 180
        let latitude2 = end.latitude * .pi / 180
        let deltaLatitude = (end.latitude - start.latitude) * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(latitude1) * cos(latitude2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let latitude1 = start.latitude * .pi / 180
        let latitude2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func compass(_ bearing: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((bearing / 22.5).rounded()) % names.count
        return "\(names[index]) \(Int(bearing.rounded()))°"
    }
}

// MARK: - Location helper

final class PickerLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var error: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            error = "Location access is off. Turn it on in System Settings → Privacy & Security → Location Services, or just search for a place."
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            error = "Location access was declined. Search for a place instead."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        error = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = "Couldn’t get a location fix. Search for a place instead."
    }
}

// MARK: - Search result

struct PlaceHit: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Coordinate Picker

struct CoordinatePickerTool: View {
    @StateObject private var job = JobState()
    @StateObject private var location = PickerLocation()
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 24, longitude: 4),
            span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 300)
        )
    )
    @State private var pointA: CLLocationCoordinate2D?
    @State private var pointB: CLLocationCoordinate2D?
    @State private var query = ""
    @State private var hits: [PlaceHit] = []
    @State private var searching = false
    @State private var searchError: String?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "mappin.and.ellipse", title: "Coordinate Picker", subtitle: "Click the map or search for a place to get latitude and longitude in decimal, degrees-minutes-seconds and UTM, then measure the distance to a second point.") {
            ToolCard(title: "Find a place") {
                HStack(spacing: 10) {
                    TextField("Search for an address, landmark or city", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                        .onSubmit { search() }
                    Button(searching ? "Searching…" : "Search") { search() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("My location") { location.request() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if let error = searchError { InlineError(message: error) }
                if let error = location.error {
                    Text(error).font(Theme.caption).foregroundStyle(Theme.textTertiary)
                }
                if !hits.isEmpty {
                    VStack(spacing: 1) {
                        ForEach(hits) { hit in
                            Button {
                                choose(hit)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(Theme.ember)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(hit.name)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                        Text(hit.detail)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(CoordinateMath.decimalPair(hit.coordinate))
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Theme.raised.opacity(0.35))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            ToolCard(title: "Map", subtitle: "Click once to drop point A, again to drop point B. Further clicks move B.", trailing: AnyView(
                Button("Clear points") { pointA = nil; pointB = nil }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(pointA == nil && pointB == nil)
            )) {
                MapReader { proxy in
                    Map(position: $camera) {
                        if let pointA {
                            Marker("Point A", systemImage: "a.circle.fill", coordinate: pointA)
                                .tint(Theme.ember)
                        }
                        if let pointB {
                            Marker("Point B", systemImage: "b.circle.fill", coordinate: pointB)
                                .tint(Theme.mint)
                        }
                        if let pointA, let pointB {
                            MapPolyline(coordinates: [pointA, pointB])
                                .stroke(Theme.ember, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        drop(coordinate)
                    })
                }
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                Text("Pan and zoom with the trackpad. A click while panning does not drop a point.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            if let pointA {
                ToolCard(title: "Point A", trailing: AnyView(
                    HStack(spacing: 6) {
                        CopyButton(value: formats(for: pointA).map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
                        Button("Save") { save() }.buttonStyle(QuietButtonStyle())
                    }
                )) {
                    coordinateRows(for: pointA)
                }
            }

            if let pointB {
                ToolCard(title: "Point B") {
                    coordinateRows(for: pointB)
                }
            }

            if let pointA, let pointB {
                let meters = CoordinateMath.distance(from: pointA, to: pointB)
                let bearing = CoordinateMath.bearing(from: pointA, to: pointB)
                ToolCard(title: "Distance") {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                            Text(meters >= 1000 ? String(format: "%.2f miles", meters / 1609.344) : String(format: "%.0f feet", meters * 3.280_84))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Divider().frame(height: 34).opacity(0.4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CoordinateMath.compass(bearing))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                            Text("bearing from A to B")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    Text("Great-circle distance on the WGS-84 ellipsoid approximation. Flat-map distance is never used, so the number stays right across a city or an ocean.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if pointA == nil {
                ToolCard(title: "No point yet") {
                    Text("Search for a place or click the map. Coordinates update instantly; nothing is sent anywhere. Map tiles come from Apple, which is the only network request this tool makes.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let error = job.error { InlineError(message: error) }
            if !job.status.isEmpty {
                Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            OutputFilesCard(title: "Saved", urls: job.results)
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            guard let coordinate = location.coordinate else { return }
            camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
            drop(coordinate)
        }
    }

    private func coordinateRows(for coordinate: CLLocationCoordinate2D) -> some View {
        VStack(spacing: 1) {
            ForEach(formats(for: coordinate), id: \.0) { label, value in
                HStack(spacing: 10) {
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 116, alignment: .leading)
                    Text(value)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CopyButton(value: value)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.raised.opacity(0.35))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formats(for coordinate: CLLocationCoordinate2D) -> [(String, String)] {
        [
            ("Decimal", CoordinateMath.decimalPair(coordinate)),
            ("DMS", "\(CoordinateMath.dms(coordinate.latitude, latitude: true)), \(CoordinateMath.dms(coordinate.longitude, latitude: false))"),
            ("Degrees + minutes", "\(CoordinateMath.ddm(coordinate.latitude, latitude: true)), \(CoordinateMath.ddm(coordinate.longitude, latitude: false))"),
            ("UTM", CoordinateMath.utm(coordinate)),
            ("Geo URI", String(format: "geo:%.6f,%.6f", coordinate.latitude, coordinate.longitude)),
            ("Apple Maps", String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=%.6f,%.6f", coordinate.latitude, coordinate.longitude, coordinate.latitude, coordinate.longitude))
        ]
    }

    private func drop(_ coordinate: CLLocationCoordinate2D) {
        if pointA == nil {
            pointA = coordinate
        } else {
            pointB = coordinate
        }
        job.clear()
    }

    private func choose(_ hit: PlaceHit) {
        camera = .region(MKCoordinateRegion(center: hit.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
        pointA = hit.coordinate
        pointB = nil
        hits = []
        query = hit.name
        job.clear()
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true
        searchError = nil
        hits = []
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                searching = false
                if let error {
                    searchError = "The search failed: \(error.localizedDescription)"
                    return
                }
                let items = response?.mapItems.prefix(8) ?? []
                hits = items.map { item in
                    let placemark = item.placemark
                    let detail = [placemark.locality, placemark.administrativeArea, placemark.country]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    return PlaceHit(
                        name: item.name ?? "Unnamed place",
                        detail: detail.isEmpty ? "No address details" : detail,
                        coordinate: placemark.coordinate
                    )
                }
                if hits.isEmpty {
                    searchError = "No places matched “\(text)”."
                }
            }
        }
    }

    private func save() {
        guard let pointA else { return }
        var body = "Nookit coordinate report\n\(Fmt.stamp.string(from: Date()))\n\n"
        body += "Point A\n"
        for (label, value) in formats(for: pointA) {
            body += "  \(label): \(value)\n"
        }
        if let pointB {
            body += "\nPoint B\n"
            for (label, value) in formats(for: pointB) {
                body += "  \(label): \(value)\n"
            }
            let meters = CoordinateMath.distance(from: pointA, to: pointB)
            let bearing = CoordinateMath.bearing(from: pointA, to: pointB)
            body += String(format: "\nDistance: %.2f m (%.2f km, %.2f mi)\n", meters, meters / 1000, meters / 1609.344)
            body += "Bearing: \(CoordinateMath.compass(bearing))\n"
        }
        do {
            let folder = store.datedFolder(for: "Coordinate Picker")
            let target = try store.write(string: body, to: folder, filename: "coordinates-\(Fmt.stampTime.string(from: Date())).txt")
            job.finish([target], "Saved \(target.lastPathComponent).")
        } catch {
            job.fail(error)
        }
    }
}
