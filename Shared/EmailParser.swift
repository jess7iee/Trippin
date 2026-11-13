import Foundation

/// On-device parser for confirmation emails. It works without a network
/// connection; when a Claude API key is set, the app prefers Claude's
/// extraction and falls back to this.
enum EmailParser {

    static func parse(_ rawText: String) -> ParsedReservation {
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        var result = ParsedReservation()
        result.kind = detectKind(text)
        result.confirmationCode = confirmationCode(in: text)
        let dates = dates(in: text)
        result.start = labeledDate(in: text, labels: startLabels) ?? dates.first
        let end = labeledDate(in: text, labels: endLabels) ?? (dates.count > 1 ? dates.last : nil)
        if let end, let start = result.start, end > start { result.end = end }
        result.address = address(in: text)
        result.title = title(in: text, kind: result.kind)
        return result
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
        let lower = text.lowercased()
        var best: (ReservationKind, Int) = (.other, 0)
        for (kind, words) in kindKeywords {
            let score = words.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
            if score > best.1 { best = (kind, score) }
        }
        if flightRoute(in: text) != nil, best.0 != .train { return .flight }
        return best.0
    }

    // MARK: Confirmation code

    static func confirmationCode(in text: String) -> String? {
        let pattern = #"(?i:confirmation|booking|reservation|record locator|pnr|itinerary)(?i:\s*(?:number|no\.?|code|id|#))?\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{4,15})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let code = String(text[r])
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
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                return String(text[r]).replacingOccurrences(of: "\n", with: ", ")
            }
        }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for label in ["Address:", "Location:", "Where:"] where trimmed.lowercased().hasPrefix(label.lowercased()) {
                let value = trimmed.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    // MARK: Title

    static func flightRoute(in text: String) -> (from: String, to: String)? {
        let pattern = #"\b([A-Z]{3})\s*(?:→|->|–|—|-|to)\s*([A-Z]{3})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let a = Range(m.range(at: 1), in: text), let b = Range(m.range(at: 2), in: text) else { return nil }
        return (String(text[a]), String(text[b]))
    }

    static func flightNumber(in text: String) -> String? {
        let pattern = #"(?i:flight)(?i:\s*(?:number|no\.?|#))?\s*:?\s*([A-Z0-9]{2}\s?\d{1,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func title(in text: String, kind: ReservationKind) -> String {
        if kind == .flight {
            var parts = ["Flight"]
            if let number = flightNumber(in: text) { parts.append(number) }
            if let route = flightRoute(in: text) { parts.append("\(route.from) → \(route.to)") }
            if parts.count > 1 { return parts.joined(separator: " ") }
        }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        for label in ["Hotel:", "Property:", "Restaurant:", "Venue:", "Event:", "Subject:"] {
            if let line = lines.first(where: { $0.lowercased().hasPrefix(label.lowercased()) }) {
                let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        if let first = lines.first(where: { !$0.isEmpty && $0.count <= 80 }) { return first }
        return kind.label
    }
}
