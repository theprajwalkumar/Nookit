import Foundation

// MARK: - Models

struct TravelFlight: Identifiable, Hashable, Sendable {
    let id: String
    let airline: String
    let airlineCode: String
    let flightNumbers: [String]
    let fromCode: String
    let toCode: String
    let departTime: String
    let arriveTime: String
    let arrivalDayOffset: Int
    let durationMinutes: Int
    let stops: Int
    let aircraft: String?
    let price: Int
    let currency: String
    let bookingURL: URL?

    var durationLabel: String {
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var stopsLabel: String {
        stops == 0 ? "Nonstop" : "\(stops) stop\(stops == 1 ? "" : "s")"
    }

    var flightLabel: String {
        let numbers = flightNumbers.filter { !$0.isEmpty }
        return numbers.isEmpty ? airline : "\(airline) · \(numbers.joined(separator: " + "))"
    }

    var currencySymbol: String {
        switch currency.uppercased() {
        case "INR": return "₹"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return currency.uppercased() + " "
        }
    }

    var priceLabel: String {
        "\(currencySymbol)\(price.formatted(.number.grouping(.automatic)))"
    }
}

struct TravelHotel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let rating: Double?
    let reviewCount: Int
    let price: Int
    let currency: String
    let photoURL: URL?
    let bookingURL: URL?
    let starClass: String?

    var priceLabel: String {
        price > 0 ? "\(currencySymbol)\(price.formatted(.number.grouping(.automatic)))" : "Price on request"
    }

    var ratingLabel: String? {
        guard let rating, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }

    var currencySymbol: String {
        switch currency.uppercased() {
        case "INR": return "₹"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return currency.uppercased() + " "
        }
    }
}

struct TravelTrain: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let name: String
    let trainType: String
    let fromCode: String
    let fromName: String
    let toCode: String
    let toName: String
    let departTime: String
    let arriveTime: String
    let arrivalDayOffset: Int
    let durationMinutes: Int
    let runsOn: String
    let classes: [String]
    let fares: [String: Int]
    let currency: String
    let distanceKm: Int
    let bookingURL: URL?

    var durationLabel: String {
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var currencySymbol: String {
        switch currency.uppercased() {
        case "INR": return "₹"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return currency.uppercased() + " "
        }
    }

    func fareLabel(for code: String) -> String? {
        guard let fare = fares[code], fare > 0 else { return nil }
        return "\(currencySymbol)\(fare.formatted(.number.grouping(.automatic)))"
    }
}

enum TravelError: LocalizedError {
    case missingInput(String)
    case noResults(String)
    case badResponse(Int)
    case parseFailed(String)
    case stationNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingInput(let what):
            return "Add \(what) to search live prices."
        case .noResults(let what):
            return "No \(what) found for these details. Try another date or city."
        case .badResponse(let code):
            return "The travel site returned an error (\(code)). Try again in a moment."
        case .parseFailed(let what):
            return "Couldn't read live \(what) results. The site may have changed its layout."
        case .stationNotFound(let name):
            return "Couldn't find a railway station for \"\(name)\". Try a station code like NDLS or BCT."
        }
    }
}

// MARK: - Service

/// Live travel data with no third-party keys.
///
/// Flights come from the Google Flights result page, hotels from Google Hotels,
/// and Indian trains from eRail (which mirrors Indian Railways schedules).
/// All three are fetched with an ephemeral session so a previous city or
/// currency can never leak into the next search.
actor TravelService {
    static let shared = TravelService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Accept-Language": "en-IN,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        return URLSession(configuration: config)
    }()

    private var stationCache: [(code: String, name: String)]?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    // MARK: Flights

    func flights(from: String, to: String, date: Date, currency: String) async throws -> [TravelFlight] {
        let origin = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origin.isEmpty else { throw TravelError.missingInput("an origin") }
        guard !destination.isEmpty else { throw TravelError.missingInput("a destination") }

        let day = Self.dayFormatter.string(from: date)
        let query = "Flights from \(origin) to \(destination) on \(day) one way"
        guard let url = Self.googleFlightsURL(query: query, currency: currency) else {
            throw TravelError.parseFailed("flight")
        }
        let html = try await fetch(url)
        guard let data = Self.extractInitData(from: html, key: "ds:1") else {
            throw TravelError.parseFailed("flight")
        }
        let options = Self.value(Self.value(data, 3), 0) as? [Any] ?? []
        var results: [TravelFlight] = []
        var seen = Set<String>()

        for option in options {
            guard let opt = option as? [Any],
                  let itinerary = Self.value(opt, 0) as? [Any],
                  let fromCode = Self.value(itinerary, 3) as? String,
                  let toCode = Self.value(itinerary, 6) as? String,
                  let departTime = Self.timeString(Self.value(itinerary, 5)),
                  let arriveTime = Self.timeString(Self.value(itinerary, 8)) else { continue }

            let legs = Self.value(itinerary, 2) as? [Any] ?? []
            let stops = max(0, legs.count - 1)
            let duration = (Self.value(itinerary, 9) as? Int) ?? 0
            let price = Self.price(from: Self.value(opt, 1))
            let aircraft = (legs.first.flatMap { Self.value($0, 17) as? String })
            guard price > 0 else { continue }

            let airlineCode = (Self.value(itinerary, 0) as? String) ?? ""
            let airlineNames = Self.value(itinerary, 1) as? [Any]
            let airline = (airlineNames?.first as? String) ?? airlineCode

            var numbers: [String] = []
            for leg in legs {
                if let number = Self.value(Self.value(leg, 22), 1) as? String, !number.isEmpty {
                    numbers.append(number)
                }
            }

            let offset = Self.dayOffset(from: Self.value(itinerary, 4), to: Self.value(itinerary, 7))
            let id = "\(fromCode)-\(toCode)-\(numbers.joined(separator: "+"))-\(departTime)-\(price)"
            guard seen.insert(id).inserted else { continue }

            results.append(TravelFlight(
                id: id,
                airline: airline,
                airlineCode: airlineCode,
                flightNumbers: numbers,
                fromCode: fromCode,
                toCode: toCode,
                departTime: departTime,
                arriveTime: arriveTime,
                arrivalDayOffset: offset,
                durationMinutes: duration,
                stops: stops,
                aircraft: aircraft,
                price: price,
                currency: currency,
                bookingURL: url
            ))
        }

        guard !results.isEmpty else { throw TravelError.noResults("flights") }
        return results.sorted { $0.price < $1.price }
    }

    private static func googleFlightsURL(query: String, currency: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/travel/flights")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "curr", value: currency),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "IN")
        ]
        return components?.url
    }

    // MARK: Hotels

    func hotels(city: String, checkIn: Date, checkOut: Date, guests: Int, currency: String) async throws -> [TravelHotel] {
        let destination = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { throw TravelError.missingInput("a location") }

        let checkInText = Self.dayFormatter.string(from: checkIn)
        let checkOutText = Self.dayFormatter.string(from: max(checkOut, checkIn.addingTimeInterval(86_400)))
        var components = URLComponents(string: "https://www.google.com/travel/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "hotels in \(destination)"),
            URLQueryItem(name: "checkin", value: checkInText),
            URLQueryItem(name: "checkout", value: checkOutText),
            URLQueryItem(name: "curr", value: currency),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "IN")
        ]
        guard let url = components?.url else { throw TravelError.parseFailed("hotel") }

        let html = try await fetch(url)
        let results = Self.parseHotels(html: html, currency: currency)
        guard !results.isEmpty else { throw TravelError.noResults("stays") }
        return results
    }

    static func parseHotels(html: String, currency: String) -> [TravelHotel] {
        let marker = "<div class=\"uaTTDe"
        var starts: [String.Index] = []
        var cursor = html.startIndex
        while let range = html.range(of: marker, range: cursor..<html.endIndex) {
            starts.append(range.lowerBound)
            cursor = range.upperBound
        }
        guard !starts.isEmpty else { return [] }

        var results: [TravelHotel] = []
        var seen = Set<String>()

        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : html.endIndex
            let chunk = String(html[start..<end])

            guard let rawName = firstGroup(in: chunk, pattern: "class=\"PVOOXe\"[^>]*aria-label=\"([^\"]+)\""),
                  !rawName.isEmpty else { continue }
            let name = decodeEntities(rawName).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }

            var price = 0
            let moneyPattern = "[₹$€£][0-9,]+"
            if let priceText = firstGroup(in: chunk, pattern: "aria-label=\"Prices starting from (\(moneyPattern))") {
                price = digits(priceText)
            } else if let priceText = firstGroup(in: chunk, pattern: moneyPattern) {
                price = digits(priceText)
            }

            let rating = firstGroup(in: chunk, pattern: "aria-label=\"([0-9.]+) out of 5 stars from [0-9,]+ reviews")
                .flatMap(Double.init)
            let reviews = firstGroup(in: chunk, pattern: "out of 5 stars from ([0-9,]+) reviews")
                .flatMap { Int($0.replacingOccurrences(of: ",", with: "")) } ?? 0

            let photo = firstGroup(in: chunk, pattern: "(https://lh3\\.googleusercontent\\.com/[^\"\\\\]+)")
                .flatMap(URL.init(string:))
            let href = firstGroup(in: chunk, pattern: "href=\"(/travel/hotels/entity/[^\"]+)\"")
            let booking = href
                .map { decodeEntities($0) }
                .flatMap { URL(string: "https://www.google.com\($0)") }

            let starClass = firstGroup(in: chunk, pattern: "\\b([1-5]-star hotel)")

            let id = href ?? "\(name)-\(price)"
            results.append(TravelHotel(
                id: id,
                name: name,
                rating: rating,
                reviewCount: reviews,
                price: price,
                currency: currency,
                photoURL: photo,
                bookingURL: booking,
                starClass: starClass
            ))
        }

        return results
    }

    // MARK: Trains

    func trains(from: String, to: String) async throws -> [TravelTrain] {
        let origin = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origin.isEmpty else { throw TravelError.missingInput("an origin") }
        guard !destination.isEmpty else { throw TravelError.missingInput("a destination") }

        let stations = try await loadStations()
        guard let fromCode = Self.resolveStation(origin, in: stations) else {
            throw TravelError.stationNotFound(origin)
        }
        guard let toCode = Self.resolveStation(destination, in: stations) else {
            throw TravelError.stationNotFound(destination)
        }

        var components = URLComponents(string: "https://erail.in/rail/getTrains.aspx")
        components?.queryItems = [
            URLQueryItem(name: "Station_From", value: fromCode),
            URLQueryItem(name: "Station_To", value: toCode),
            URLQueryItem(name: "DataSource", value: "0"),
            URLQueryItem(name: "Language", value: "0"),
            URLQueryItem(name: "Cache", value: "true")
        ]
        guard let url = components?.url else { throw TravelError.parseFailed("train") }

        let text = try await fetch(url)
        let results = Self.parseTrains(text)
        guard !results.isEmpty else { throw TravelError.noResults("trains") }
        return results
    }

    private func loadStations() async throws -> [(code: String, name: String)] {
        if let stationCache { return stationCache }
        guard let url = URL(string: "https://erail.in/js/cmp/Stations.js") else {
            throw TravelError.parseFailed("station list")
        }
        let js = try await fetch(url)
        guard let assignment = js.range(of: "StationsData=\"") else {
            throw TravelError.parseFailed("station list")
        }
        let body = js[assignment.upperBound...]
        guard let closing = body.firstIndex(of: "\"") else {
            throw TravelError.parseFailed("station list")
        }
        let csv = String(body[..<closing])
        let parts = csv.components(separatedBy: ",")
        var stations: [(code: String, name: String)] = []
        var index = 0
        while index + 1 < parts.count {
            let code = parts[index].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let name = parts[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty, !name.isEmpty {
                stations.append((code, name))
            }
            index += 2
        }
        guard !stations.isEmpty else { throw TravelError.parseFailed("station list") }
        stationCache = stations
        return stations
    }

    static func parseTrains(_ text: String) -> [TravelTrain] {
        let chunks = text.components(separatedBy: "^")
        guard chunks.count > 1 else { return [] }

        var results: [TravelTrain] = []
        var seen = Set<String>()

        for chunk in chunks.dropFirst() {
            let fields = chunk.components(separatedBy: "~")
            guard fields.count > 62 else { continue }
            let number = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !number.isEmpty, Int(number) != nil, seen.insert(number).inserted else { continue }

            let name = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let fromName = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)
            let fromCode = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
            let toName = fields[8].trimmingCharacters(in: .whitespacesAndNewlines)
            let toCode = fields[9].trimmingCharacters(in: .whitespacesAndNewlines)
            let depart = fields[10].trimmingCharacters(in: .whitespacesAndNewlines)
            let arrive = fields[11].trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = minutes(fromRailwayDuration: fields[12])
            let runsOn = runsOnLabel(fields[13])
            let distance = Int(fields[39].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let classes = classList(fields[62])
            let offset = dayOffset(depart: depart, arrive: arrive)

            let fareRaw = fields.count > 41 ? fields[41].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let fareParts = fareRaw.components(separatedBy: ":")
            let trainType = fareParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let classMask = fields[21].trimmingCharacters(in: .whitespacesAndNewlines)
            let classOrder = ["1A", "2A", "3A", "CC", "FC", "SL", "2S", "3E", "GN", "EA", "EC", "EV", "VC", "VS"]
            var fares: [String: Int] = [:]
            for (index, code) in classOrder.enumerated() {
                guard index < classMask.count else { break }
                let maskChar = classMask[classMask.index(classMask.startIndex, offsetBy: index)]
                guard maskChar == "1" else { continue }
                let segmentIndex = index + 2
                guard segmentIndex < fareParts.count else { continue }
                let components = fareParts[segmentIndex].components(separatedBy: ",")
                guard let first = components.first,
                      let fare = Int(first.trimmingCharacters(in: .whitespacesAndNewlines)),
                      fare > 0 else { continue }
                fares[code] = fare
            }

            guard !fromCode.isEmpty, !toCode.isEmpty, duration > 0 else { continue }

            results.append(TravelTrain(
                id: number,
                number: number,
                name: name,
                trainType: trainType,
                fromCode: fromCode,
                fromName: fromName,
                toCode: toCode,
                toName: toName,
                departTime: depart.replacingOccurrences(of: ".", with: ":"),
                arriveTime: arrive.replacingOccurrences(of: ".", with: ":"),
                arrivalDayOffset: offset,
                durationMinutes: duration,
                runsOn: runsOn,
                classes: classes,
                fares: fares,
                currency: "INR",
                distanceKm: distance,
                bookingURL: URL(string: "https://erail.in/train-enquiry/\(number)")
            ))
        }

        return results.sorted { lhs, rhs in
            let l = lhs.departTime.replacingOccurrences(of: ":", with: "")
            let r = rhs.departTime.replacingOccurrences(of: ":", with: "")
            return (Int(l) ?? 0) < (Int(r) ?? 0)
        }
    }

    // MARK: Station resolution

    static func resolveStation(_ input: String, in stations: [(code: String, name: String)]) -> String? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        if stations.contains(where: { $0.code == upper }) { return upper }

        let key = raw.lowercased()
        if let hint = stationHints[key] { return hint }

        if let exact = stations.first(where: { $0.name.lowercased() == key }) {
            return exact.code
        }
        let matches = stations.filter { $0.name.lowercased().contains(key) }
        if let best = matches.min(by: { $0.name.count < $1.name.count }) {
            return best.code
        }
        return nil
    }

    private static let stationHints: [String: String] = [
        "delhi": "NDLS", "new delhi": "NDLS", "delhi ncr": "NDLS",
        "mumbai": "CSMT", "bombay": "CSMT", "navi mumbai": "CSMT",
        "bengaluru": "SBC", "bangalore": "SBC",
        "kolkata": "HWH", "calcutta": "HWH", "howrah": "HWH",
        "chennai": "MAS", "madras": "MAS",
        "hyderabad": "SC", "secunderabad": "SC",
        "pune": "PUNE", "ahmedabad": "ADI", "jaipur": "JP",
        "lucknow": "LKO", "kanpur": "CNB", "bhopal": "BPL",
        "patna": "PNBE", "varanasi": "BSB", "banaras": "BSB",
        "guwahati": "GHY", "bhubaneswar": "BBS", "ranchi": "RNC",
        "jamshedpur": "TATA", "kochi": "ERS", "cochin": "ERS",
        "ernakulam": "ERS", "thiruvananthapuram": "TVC", "trivandrum": "TVC",
        "coimbatore": "CBE", "madurai": "MDU", "nagpur": "NGP",
        "surat": "ST", "vadodara": "BRC", "indore": "INDB",
        "chandigarh": "CDG", "amritsar": "ASR", "dehradun": "DDN",
        "haridwar": "HW", "agra": "AGC", "gwalior": "GWL",
        "jabalpur": "JBP", "raipur": "R", "visakhapatnam": "VSKP",
        "vizag": "VSKP", "vijayawada": "BZA", "mysuru": "MYS",
        "mysore": "MYS", "mangaluru": "MAQ", "mangalore": "MAQ",
        "goa": "MAO", "panaji": "MAO", "udaipur": "UDZ",
        "jodhpur": "JU", "ajmer": "AII", "kota": "KOTA",
        "prayagraj": "PRYJ", "allahabad": "PRYJ", "gorakhpur": "GKP",
        "siliguri": "NJP", "new jalpaiguri": "NJP", "darjeeling": "NJP",
        "jammu": "JAT", "shimla": "SML", "nashik": "NK",
        "aurangabad": "AWB", "kolhapur": "KOP", "tirupati": "TPTY",
        "kanyakumari": "CAPE", "rameswaram": "RMM", "bikaner": "BKN",
        "jaisalmer": "JSM", "mathura": "MTJ", "vrindavan": "MTJ",
        "ayodhya": "AYC", "jhansi": "JHS", "satna": "STA",
        "bilaspur": "BSP", "cuttack": "CTC", "puri": "PURI",
        "dhanbad": "DHN", "asansol": "ASN", "durgapur": "DGR",
        "bokaro": "BKSC", "rourkela": "ROU", "sambalpur": "SBP",
        "berhampur": "BAM", "warangal": "WL", "guntur": "GNT",
        "rajahmundry": "RJY", "tiruchirappalli": "TPJ", "trichy": "TPJ",
        "salem": "SA", "hubballi": "UBL", "hubli": "UBL",
        "belagavi": "BGM", "belgaum": "BGM", "kalaburagi": "KLBG",
        "gulbarga": "KLBG", "nanded": "NED", "solapur": "SUR",
        "bijapur": "BJP", "vijayapura": "BJP", "davangere": "DVG",
        "shivamogga": "SMET", "shimoga": "SMET", "kurnool": "KRNT",
        "anantapur": "ATP", "kadapa": "HX", "cuddapah": "HX",
        "ongole": "OGL", "bhavnagar": "BVC", "jamnagar": "JAM",
        "rajkot": "RJT", "gandhinagar": "GNC", "bhuj": "BHUJ",
        "porbandar": "PBR", "dwarka": "DWK", "somnath": "SMNH",
        "veraval": "VRL", "palitana": "PIT", "mehsana": "MSH",
        "palanpur": "PNU", "abu road": "ABR", "mount abu": "ABR",
        "bhilwara": "BHL", "chittorgarh": "COR", "alwar": "AWR",
        "bharatpur": "BTE", "sawai madhopur": "SWM", "dausa": "DO",
        "hisar": "HSR", "rohtak": "ROK", "panipat": "PNP",
        "karnal": "KUN", "ambala": "UMB", "ludhiana": "LDH",
        "jalandhar": "JUC", "pathankot": "PTK", "jammu tawi": "JAT",
        "katra": "SVDK", "udhampur": "UHP", "baramulla": "BRML",
        "moradabad": "MB", "bareilly": "BE", "shahjahanpur": "SPN",
        "sitapur": "STP", "gonda": "GD", "basti": "BST",
        "deoria": "DEOS", "siwan": "SV", "chhapra": "CPR",
        "muzaffarpur": "MFP", "darbhanga": "DBG", "samastipur": "SPJ",
        "bhagalpur": "BGP", "gaya": "GAYA", "deoghar": "DGHR",
        "jasidih": "JSME", "madhepura": "MHP", "saharsa": "SHC",
        "purnia": "PRNA", "katihar": "KIR",
        "cooch behar": "NCB", "alipurduar": "APDJ", "bongaigaon": "BNGN",
        "dibrugarh": "DBRG", "tinsukia": "TSK", "jorhat": "JTT",
        "silchar": "SCL", "agartala": "AGTL", "imphal": "IMPL",
        "shillong": "SHL", "itanagar": "NHLN", "dimapur": "DMV",
        "kohima": "KXJ", "aizawl": "AZL"
    ]

    // MARK: Networking

    private func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TravelError.badResponse(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TravelError.badResponse(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Parsing helpers

    static func extractInitData(from html: String, key: String) -> Any? {
        guard let keyRange = html.range(of: "key: '\(key)'") else { return nil }
        guard let dataRange = html.range(of: "data:", range: keyRange.upperBound..<html.endIndex) else { return nil }
        guard let open = html[dataRange.upperBound...].firstIndex(of: "[") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var index = open

        while index < html.endIndex {
            let character = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        let json = String(html[open...index])
                        return try? JSONSerialization.jsonObject(with: Data(json.utf8))
                    }
                }
            }
            index = html.index(after: index)
        }
        return nil
    }

    static func value(_ any: Any?, _ index: Int) -> Any? {
        guard let array = any as? [Any], array.indices.contains(index) else { return nil }
        return array[index]
    }

    static func timeString(_ any: Any?) -> String? {
        guard let array = any as? [Any], array.count >= 2,
              let hour = array[0] as? Int, let minute = array[1] as? Int else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    static func dayOffset(from: Any?, to: Any?) -> Int {
        guard let start = dayOrdinal(from: from), let end = dayOrdinal(from: to) else { return 0 }
        return max(0, end - start)
    }

    private static func dayOrdinal(from any: Any?) -> Int? {
        guard let array = any as? [Any], array.count >= 3,
              let year = array[0] as? Int, let month = array[1] as? Int, let day = array[2] as? Int else {
            return nil
        }
        return year * 372 + month * 31 + day
    }

    static func price(from any: Any?) -> Int {
        guard let array = any as? [Any] else { return (any as? Int) ?? 0 }
        if let direct = array.first(where: { $0 is Int }) as? Int { return direct }
        for element in array {
            if let nested = element as? [Any], let number = nested.last(where: { $0 is Int }) as? Int {
                return number
            }
        }
        return 0
    }

    static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[groupRange])
    }

    static func digits(_ text: String) -> Int {
        Int(text.filter(\.isNumber)) ?? 0
    }

    static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    static func minutes(fromRailwayDuration text: String) -> Int {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".")
        guard let hours = Int(parts.first ?? "") else { return 0 }
        let minutes = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return hours * 60 + minutes
    }

    static func dayOffset(depart: String, arrive: String) -> Int {
        guard let dep = clockMinutes(depart), let arr = clockMinutes(arrive) else { return 0 }
        return arr < dep ? 1 : 0
    }

    private static func clockMinutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: ":")
            .components(separatedBy: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    static func runsOnLabel(_ mask: String) -> String {
        let value = mask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 7 else { return "" }
        let days = Array(value.prefix(7))
        if days.allSatisfy({ $0 == "1" }) { return "Daily" }
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let running = zip(days, names).compactMap { $0 == "1" ? $1 : nil }
        return running.isEmpty ? "" : running.joined(separator: " ")
    }

    static func classList(_ text: String) -> [String] {
        let valid: Set<String> = ["1A", "2A", "3A", "SL", "CC", "2S", "3E", "EC", "EA", "FC", "VC", "VS", "EV", "GN"]
        var seen = Set<String>()
        var result: [String] = []
        for entry in text.components(separatedBy: "|") {
            guard let code = entry.components(separatedBy: ":").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(), valid.contains(code) else { continue }
            if seen.insert(code).inserted { result.append(code) }
        }
        return result
    }
}
