import Foundation

/// A list of places prepared outside the app (for example, researched in a chat with
/// Claude) and pasted into Trippin. The text is JSON, optionally inside a Markdown
/// code fence or with other text around it:
///
///     {"trippinPlaces": 1, "places": [
///       {"date": "2026-11-16", "time": "19:00", "name": "Donglaishun (Wangfujing)",
///        "localName": "东来顺饭庄（王府井店）", "address": "北京市东城区王府井大街198号",
///        "latitude": 39.913, "longitude": 116.411, "category": "food",
///        "note": "Copper-pot lamb hot pot", "searchQuery": "Donglaishun Wangfujing Beijing"}
///     ]}
///
/// `date` is required; everything except `name` is optional.
enum PlacesImport {
    struct Place: Equatable, Identifiable {
        var id = UUID()
        var date: Date
        /// Time of day, when the place is tied to one (a dinner booking, say).
        var time: DateComponents?
        var name: String
        var localName: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?
        var category: String?
        var note: String?
        var searchQuery: String?

        static func == (a: Place, b: Place) -> Bool {
            a.date == b.date && a.time == b.time && a.name == b.name && a.localName == b.localName
                && a.address == b.address && a.latitude == b.latitude && a.longitude == b.longitude
                && a.category == b.category && a.note == b.note && a.searchQuery == b.searchQuery
        }
    }

    enum ImportError: LocalizedError, Equatable {
        case notAPlacesList
        case noPlaces

        var errorDescription: String? {
            switch self {
            case .notAPlacesList: "This doesn't look like a Trippin places list. Copy the whole block, including the { } braces."
            case .noPlaces: "The list has no places with a name and date."
            }
        }
    }

    private struct File: Decodable {
        var trippinPlaces: Int?
        var places: [Item]
    }

    private struct Item: Decodable {
        var date: String?
        var time: String?
        var name: String?
        var localName: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?
        var category: String?
        var note: String?
        var searchQuery: String?
    }

    static func parse(_ text: String) throws -> [Place] {
        // Take the outermost { … } so code fences or surrounding chat text don't matter.
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let data = String(text[open...close]).data(using: .utf8),
              let file = try? JSONDecoder().decode(File.self, from: data) else { throw ImportError.notAPlacesList }

        let places = file.places.compactMap { item -> Place? in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let date = item.date.flatMap(day) else { return nil }
            var lat = item.latitude, lon = item.longitude
            if let la = lat, let lo = lon, (la == 0 && lo == 0) || abs(la) > 90 || abs(lo) > 180 { lat = nil; lon = nil }
            if lat == nil || lon == nil { lat = nil; lon = nil }
            return Place(date: date, time: item.time.flatMap(time), name: name,
                         localName: item.localName.nonEmpty, address: item.address.nonEmpty,
                         latitude: lat, longitude: lon, category: item.category.nonEmpty,
                         note: item.note.nonEmpty, searchQuery: item.searchQuery.nonEmpty)
        }
        guard !places.isEmpty else { throw ImportError.noPlaces }
        return places
    }

    /// "2026-11-16" in the phone's time zone (the trip's day pages work in local days).
    private static func day(_ string: String) -> Date? {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "19:00" or "7:30 PM".
    private static func time(_ string: String) -> DateComponents? {
        let s = string.trimmingCharacters(in: .whitespaces).lowercased()
        let pm = s.hasSuffix("pm"), am = s.hasSuffix("am")
        let digits = s.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = digits.split(separator: ":").compactMap { Int($0) }
        guard let h = parts.first, (0..<24).contains(h) else { return nil }
        var hour = h
        if pm, hour < 12 { hour += 12 }
        if am, hour == 12 { hour = 0 }
        let minute = parts.count > 1 ? parts[1] : 0
        guard (0..<60).contains(minute) else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
