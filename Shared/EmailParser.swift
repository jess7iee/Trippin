import Foundation

/// On-device parser for confirmation emails and itineraries. It works without
/// a network connection; when a Claude API key is set, the app prefers
/// Claude's extraction and falls back to this.
enum EmailParser {

    /// Every booking in the text. An itinerary with several sections separated
    /// by blank lines (one flight, hotel or train each) gives one booking per
    /// section; anything else is read as a single booking.
    static func parseAll(_ rawText: String, now: Date = .now) -> [ParsedReservation] {
        let text = clean(rawText)
        let sections = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sections.count > 1 {
            // Skip notes like "accommodation to be added" or "all times are local".
            let bookings = sections.map { parse($0, now: now) }
                .filter { ($0.kind != .other || $0.confirmationCode != nil) && ($0.start != nil || $0.confirmationCode != nil) }
            if bookings.count > 1 { return bookings }
        }
        return [parse(text, now: now)]
    }

    static func parse(_ rawText: String, now: Date = .now) -> ParsedReservation {
        let text = clean(rawText)
        var result = ParsedReservation()
        result.kind = detectKind(text)
        result.confirmationCode = confirmationCode(in: text)
        let (start, end) = startAndEnd(in: text, kind: result.kind, now: now)
        result.start = start
        if let end, let start, end > start { result.end = end }
        result.address = departurePlace(in: text, kind: result.kind) ?? address(in: text)
        result.arrivalPlace = arrivalPlace(in: text, kind: result.kind)
        (result.title, result.localName) = titleAndLocalName(in: text, kind: result.kind)
        return result
    }

    /// Normalizes line endings and drops Markdown emphasis and whitespace-only lines.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    // MARK: Kind

    private static let kindKeywords: [(ReservationKind, [String])] = [
        (.flight, ["flight", "boarding", "airline", "departure", "gate", "e-ticket", "itinerary receipt", "seat "]),
        (.hotel, ["hotel", "check-in", "check in", "check-out", "checkout", "nights", "room type", "airbnb", "booking.com", "stay"]),
        (.restaurant, ["restaurant", "table for", "party of", "opentable", "resy", "dinner", "lunch", "guests", "tablecheck"]),
        (.car, ["car rental", "rental car", "pick-up location", "pickup location", "hertz", "avis", "enterprise", "sixt"]),
        (.train, ["train", "rail", "platform", "carriage", "shinkansen", "amtrak", "eurostar", "coach "]),
        (.activity, ["ticket", "tour", "admission", "museum", "concert", "event", "experience", "klook", "viator"]),
    ]

    static func detectKind(_ text: String) -> ReservationKind {
        // A flight or train number is a stronger signal than keyword counts.
        if flightNumber(in: text) != nil { return .flight }
        if trainNumber(in: text) != nil { return .train }
        let lower = text.lowercased()
        var best: (ReservationKind, Int) = (.other, 0)
        for (kind, words) in kindKeywords {
            let score = words.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
            if score > best.1 { best = (kind, score) }
        }
        if arrowRoute(in: text) != nil, best.0 != .train { return .flight }
        return best.0
    }

    // MARK: Confirmation code

    static func confirmationCode(in text: String) -> String? {
        let pattern = #"(?i:confirmation|booking|reservation|record locator|pnr|itinerary)(?i:\s*(?:number|no\.?|code|id|#|reference|ref\.?))?(?i:\s+is)?\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{4,15})\b"#
        for match in matches(pattern, in: text) {
            guard let code = group(1, of: match, in: text) else { continue }
            // Skip plain words such as "CONFIRMED".
            if code.rangeOfCharacter(from: .decimalDigits) != nil || code.count <= 8 && code.uppercased() == code && !commonWords.contains(code) {
                return code
            }
        }
        return nil
    }

    private static let commonWords: Set<String> = ["CONFIRMED", "DETAILS", "NUMBER", "STATUS"]

    // MARK: Dates

    private static let startLabels = ["check-in", "check in", "departure", "departs", "depart", "pick-up", "pickup", "date", "when"]
    private static let endLabels = ["check-out", "check out", "checkout", "arrival", "arrives", "return", "drop-off", "dropoff"]

    private static let monthPattern = #"\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*[–—-]\s*(\d{1,2})\b)?(?:,?\s+(\d{4}))?"#
    private static let timePattern = #"\b(\d{1,2}):(\d{2})(?:\s*([AaPp])\.?[Mm]\b\.?)?"#

    private static func startAndEnd(in text: String, kind: ReservationKind, now: Date) -> (Date?, Date?) {
        let timeline = timeline(in: text, now: now)
        if !timeline.moments.isEmpty {
            return (timeline.moments.first, timeline.moments.count > 1 ? timeline.moments.last : nil)
        }
        if let day = timeline.firstDay {
            // Dates without times. Hotels get the usual check-in and check-out hours,
            // and a single date is read as a one-night stay.
            guard kind == .hotel else { return (day, timeline.rangeEnd) }
            let cal = Calendar.current
            let checkOutDay = timeline.rangeEnd ?? cal.date(byAdding: .day, value: 1, to: day)!
            return (cal.date(bySettingHour: 15, minute: 0, second: 0, of: day),
                    cal.date(bySettingHour: 11, minute: 0, second: 0, of: checkOutDay))
        }
        // Other formats, e.g. "2027-03-06 11:05" or "6 March 2027".
        let all = dates(in: text)
        let start = labeledDate(in: text, labels: startLabels) ?? all.first
        let end = labeledDate(in: text, labels: endLabels) ?? (all.count > 1 ? all.last : nil)
        return (start, end)
    }

    struct Timeline {
        /// Each time in the text, on the most recent date mentioned before it.
        var moments: [Date] = []
        /// The first date mentioned, at midnight.
        var firstDay: Date?
        /// The end of a range on the first date, e.g. the 21 in "November 17–21".
        var rangeEnd: Date?
    }

    /// Reads dates like "November 15" or "Mar 6, 2027" and times like "10:45 AM" or
    /// "13:11" in order. A date without a year is the next one on or after about
    /// three months ago, so a trip coming up in the next year is read correctly.
    static func timeline(in text: String, now: Date = .now) -> Timeline {
        let cal = Calendar.current
        var result = Timeline()
        var currentDay: Date?
        let pattern = "(?:\(monthPattern))|(?:\(timePattern))"
        for match in matches(pattern, in: text) {
            if let monthName = group(1, of: match, in: text), let day = group(2, of: match, in: text).flatMap({ Int($0) }),
               let month = monthNumber(monthName) {
                let year = group(4, of: match, in: text).flatMap { Int($0) }
                guard let date = resolve(month: month, day: day, year: year, now: now) else { continue }
                currentDay = date
                if result.firstDay == nil {
                    result.firstDay = date
                    if let endDay = group(3, of: match, in: text).flatMap({ Int($0) }) {
                        var end = cal.date(bySetting: .day, value: endDay, of: date)
                        if endDay < day { end = cal.date(byAdding: .month, value: 1, to: cal.date(bySetting: .day, value: endDay, of: date) ?? date) }
                        result.rangeEnd = end.map { cal.startOfDay(for: $0) }
                    }
                }
            } else if var hour = group(5, of: match, in: text).flatMap({ Int($0) }),
                      let minute = group(6, of: match, in: text).flatMap({ Int($0) }),
                      let day = currentDay, hour < 24, minute < 60 {
                if let half = group(7, of: match, in: text)?.lowercased() {
                    guard hour >= 1, hour <= 12 else { continue }
                    hour = hour % 12 + (half == "p" ? 12 : 0)
                }
                if let moment = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                   result.moments.last != moment {
                    result.moments.append(moment)
                }
            }
        }
        return result
    }

    private static func monthNumber(_ name: String) -> Int? {
        let prefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return prefixes.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }

    private static func resolve(month: Int, day: Int, year: Int?, now: Date) -> Date? {
        let cal = Calendar.current
        if let year { return cal.date(from: DateComponents(year: year, month: month, day: day)) }
        let thisYear = cal.component(.year, from: now)
        guard let date = cal.date(from: DateComponents(year: thisYear, month: month, day: day)) else { return nil }
        let cutoff = cal.date(byAdding: .month, value: -3, to: cal.startOfDay(for: now))!
        return date < cutoff ? cal.date(byAdding: .year, value: 1, to: date) : date
    }

    static func dates(in text: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.date).sorted()
    }

    /// Looks for a date on the same line as one of the labels, e.g. "Check-in: Fri, Mar 6 2027, 3:00 PM".
    private static func labeledDate(in text: String, labels: [String]) -> Date? {
        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            guard labels.contains(where: { lower.contains($0) }) else { continue }
            if let date = dates(in: line).first { return date }
        }
        return nil
    }

    // MARK: Address

    static func address(in text: String) -> String? {
        // "Address: 北京市顺义区天竺镇府前一街32号." — up to the end of the sentence.
        for line in text.components(separatedBy: .newlines) {
            for label in ["address:", "location:", "where:"] {
                guard let range = line.range(of: label, options: .caseInsensitive) else { continue }
                var value = String(line[range.upperBound...])
                if let stop = value.range(of: ". ") ?? value.range(of: "。") { value = String(value[..<stop.lowerBound]) }
                value = value.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
                if !value.isEmpty { return value }
            }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                return String(text[r]).replacingOccurrences(of: "\n", with: ", ")
            }
        }
        return nil
    }

    /// Where a flight or train leaves from, as something Apple Maps can find.
    private static func departurePlace(in text: String, kind: ReservationKind) -> String? {
        switch kind {
        case .flight: flightRoute(in: text).map { "\(airportName($0.from, in: text) ?? $0.from) Airport" }
        case .train: headingRoute(in: text).map { "\($0.from) Railway Station" }
        default: nil
        }
    }

    /// Where a flight or train arrives, as something Apple Maps can find.
    private static func arrivalPlace(in text: String, kind: ReservationKind) -> String? {
        switch kind {
        case .flight: flightRoute(in: text).map { "\(airportName($0.to, in: text) ?? $0.to) Airport" }
        case .train: headingRoute(in: text).map { "\($0.to) Railway Station" }
        default: nil
        }
    }

    // MARK: Title

    /// Airport codes: "SFO → NRT", or the first two in brackets, e.g. "San Francisco (SFO) … Beijing (PEK)".
    static func flightRoute(in text: String) -> (from: String, to: String)? {
        if let route = arrowRoute(in: text) { return route }
        var codes: [String] = []
        for m in matches(#"\(([A-Z]{3})\)"#, in: text) {
            if let code = group(1, of: m, in: text), !codes.contains(code) { codes.append(code) }
        }
        return codes.count >= 2 ? (codes[0], codes[1]) : nil
    }

    /// "SFO → NRT" or "SFO-NRT".
    private static func arrowRoute(in text: String) -> (from: String, to: String)? {
        guard let m = matches(#"\b([A-Z]{3})\s*(?:→|->|–|—|-|to)\s*([A-Z]{3})\b"#, in: text).first,
              let a = group(1, of: m, in: text), let b = group(2, of: m, in: text) else { return nil }
        return (a, b)
    }

    /// The place written before an airport code, e.g. "Tokyo Haneda" in "departing Tokyo Haneda (HND)".
    /// Searching "Tokyo Haneda Airport" finds the right airport more reliably than "HND Airport".
    static func airportName(_ code: String, in text: String) -> String? {
        let pattern = #"((?:[A-Z][\p{L}'-]+\s+){0,2}[A-Z][\p{L}'-]+)\s*\("# + code + #"\)"#
        return matches(pattern, in: text).first.flatMap { group(1, of: $0, in: text) }
    }

    /// "Flight UA 837", "Fly United UA888", "flight no. 3K 123".
    static func flightNumber(in text: String) -> String? {
        let pattern = #"(?i:\b(?:flight|fly|flying)\b)[^\n]*?\b((?:[A-Z]{2}|[A-Z]\d|\d[A-Z])\s?\d{1,4})\b"#
        return matches(pattern, in: text).first.flatMap { group(1, of: $0, in: text) }
    }

    /// "Take train C638", "Train G102".
    static func trainNumber(in text: String) -> String? {
        let pattern = #"(?i:\btrain)\s+(?:no\.?\s*)?([A-Z]{0,2}\d{1,5})\b"#
        return matches(pattern, in: text).first.flatMap { group(1, of: $0, in: text) }
    }

    /// The route in a heading like "November 21 — Kunming → Lijiang".
    static func headingRoute(in text: String) -> (from: String, to: String)? {
        guard let heading = text.components(separatedBy: .newlines).first else { return nil }
        let parts = heading.components(separatedBy: "→")
        guard parts.count == 2 else { return nil }
        let from = parts[0].components(separatedBy: CharacterSet(charactersIn: "—–:")).last ?? parts[0]
        let a = from.trimmingCharacters(in: .whitespaces), b = parts[1].trimmingCharacters(in: .whitespaces)
        return a.isEmpty || b.isEmpty ? nil : (a, b)
    }

    private static func titleAndLocalName(in text: String, kind: ReservationKind) -> (String, String?) {
        if kind == .flight {
            var parts = ["Flight"]
            if let number = flightNumber(in: text) { parts.append(number) }
            if let route = flightRoute(in: text) { parts.append("\(route.from) → \(route.to)") }
            if parts.count > 1 { return (parts.joined(separator: " "), nil) }
        }
        if kind == .train, let number = trainNumber(in: text) {
            let route = headingRoute(in: text).map { " \($0.from) → \($0.to)" } ?? ""
            return ("Train \(number)\(route)", nil)
        }
        if let name = stayName(in: text) { return splitLocalName(name) }
        let lines = text.components(separatedBy: .newlines)
        for label in ["Hotel:", "Property:", "Restaurant:", "Venue:", "Event:", "Subject:"] {
            if let line = lines.first(where: { $0.lowercased().hasPrefix(label.lowercased()) }) {
                let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return splitLocalName(value) }
            }
        }
        if let first = lines.first(where: { !$0.isEmpty && $0.count <= 80 }) { return (first, nil) }
        return (kind.label, nil)
    }

    /// "Stay at Park Hyatt Tokyo." → "Park Hyatt Tokyo".
    private static func stayName(in text: String) -> String? {
        guard let m = matches(#"(?i:\bstay(?:ing)? at)\s+(.+?)(?:\.\s|\.?$|。)"#, in: text, options: .anchorsMatchLines).first else { return nil }
        return group(1, of: m, in: text)?.trimmingCharacters(in: .whitespaces)
    }

    /// "Fairfield by Marriott Kunming / 昆明西山万豪万枫酒店" → title and local name.
    private static func splitLocalName(_ name: String) -> (String, String?) {
        let parts = name.components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return (name, nil) }
        if isLocalScript(parts[1]) && !isLocalScript(parts[0]) { return (parts[0], parts[1]) }
        if isLocalScript(parts[0]) && !isLocalScript(parts[1]) { return (parts[1], parts[0]) }
        return (name, nil)
    }

    /// True when the text is mostly Chinese, Japanese or Korean characters.
    static func isLocalScript(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard !letters.isEmpty else { return false }
        let cjk = letters.filter {
            $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        }
        return cjk.count * 2 > letters.count
    }

    // MARK: Regex helpers

    private static func matches(_ pattern: String, in text: String,
                                options: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: text) else { return nil }
        return String(text[r])
    }
}
