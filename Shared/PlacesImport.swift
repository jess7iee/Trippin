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

// MARK: - Prompt for an AI chat

extension PlacesImport {
    /// One hotel stay, for filling in the prompt.
    struct PromptStay {
        var name: String
        var address: String?
        var checkIn: Date
        var checkOut: Date?
    }

    /// A prompt to paste into an AI chat (Claude with web search, say). Its answer is a
    /// places list that `parse` reads. The trip's dates and hotels are filled in; the
    /// traveler adds what they want to do.
    static func prompt(tripName: String, start: Date, end: Date, stays: [PromptStay], fixedPlans: [String]) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let stayLines = stays.isEmpty
            ? "- 住在：[酒店名和地址]"
            : stays.map { s in
                let dates = day.string(from: s.checkIn) + (s.checkOut.map { " 到 " + day.string(from: $0) } ?? "")
                return "- 住在：\(s.name)\(s.address.map { "（\($0)）" } ?? "")，\(dates)"
            }.joined(separator: "\n")
        let plans = fixedPlans.isEmpty ? "[例如 11月17日 18:55 到达机场]" : fixedPlans.joined(separator: "；")

        return """
        你是我的旅行规划助手。请根据下面的行程信息，推荐具体、真实、目前仍在营业的地点，并安排到每一天。

        【行程】\(tripName)
        - 日期：\(day.string(from: start)) 到 \(day.string(from: end))
        \(stayLines)
        - 已确定的安排：\(plans)
        - 想规划的城市和日期：[例如 昆明，11月17日到21日]
        - 想做的事：[例如 spa、菌子火锅、本地小吃、骑行、咖啡馆和书店]
        - 偏好：[例如 节奏慢一点、预算中等、不吃辣]

        【要求】
        1. 先用网上的最新信息核实每个地点存在且在营业；不确定的不要推荐。
        2. 每天安排 2–5 个地点，按时间顺序，离住处或当天行程不要太远；到达日和离开日少排一些。
        3. 只输出一个 JSON 代码块，代码块前后可以有简短说明，但 JSON 里不要有注释。

        【JSON 格式】
        {"trippinPlaces": 1, "places": [
          {
            "date": "YYYY-MM-DD",
            "time": "HH:mm",
            "name": "英文或拼音名称",
            "localName": "当地语言名称",
            "address": "当地语言的完整地址",
            "latitude": 25.0478,
            "longitude": 102.7036,
            "category": "food",
            "searchQuery": "在高德或大众点评里能搜到它的关键词",
            "note": "一两句话：为什么推荐、点什么、注意事项"
          }
        ]}

        字段说明：
        - date：必填，当地日期，必须在行程日期内。
        - time：可选，24 小时制当地时间。
        - name：必填，英文或拼音名称。
        - localName：当地语言名称；中国地点写中文全名，含分店，如 东来顺饭庄（王府井店）。
        - address：可选，当地语言的完整地址，只写确定的。
        - latitude / longitude：可选，只在确定准确时一起填写，否则都省略，不要编造。
        - category：food / cafe / bookstore / park / nature / spa / shop / museum / sight / nightlife 之一。
        - searchQuery：在高德或大众点评里能搜到它的关键词；中国地点用中文，如 "翠湖公园 昆明"。
        - note：一两句话，为什么推荐、点什么、是否需预约、营业时间等。
        不确定的字段直接省略。
        """
    }
}
