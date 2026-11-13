import Foundation

/// Turns a trip into a shareable, self-contained web page, one section per city.
///
/// Cities come from hotel stays: each stay covers its check-in day through its
/// check-out day. On a travel day that ends one stay and starts the next, the
/// stops before the flight or train go to the first city and the rest to the next.
/// Days with plans but no hotel form their own section, which the traveler can name.
enum TripExport {
    struct Item: Equatable {
        var time: String?
        var name: String
        var localName: String?
        var note: String?
        var isJourney = false
        /// The stay this is a check-in or check-out of, if any.
        var stayID: String?
    }

    struct Day: Equatable {
        var index: Int
        var date: Date
        var items: [Item]
    }

    struct Stay: Equatable {
        var id: String
        var name: String
        var localName: String?
        var address: String?
        var localAddress: String?
        var confirmation: String?
        /// Day indexes of check-in and check-out.
        var firstDay: Int
        var lastDay: Int
        var city: String
        var cityLocalName: String?
    }

    struct Journey: Equatable {
        var date: Date
        var route: String
        var number: String?
        var detail: String
        var isTrain: Bool
        var confirmation: String?
    }

    struct Section: Equatable, Identifiable {
        var id: String
        var name: String
        var localName: String?
        var stay: Stay?
        var days: [Day]
    }

    // MARK: Grouping

    static func sections(days: [Day], stays: [Stay]) -> [Section] {
        let stays = stays.sorted { $0.firstDay < $1.firstDay }
        var byStay: [String: [Day]] = [:]
        var loose: [Day] = []

        for day in days.sorted(by: { $0.index < $1.index }) {
            let covering = stays.filter { $0.firstDay <= day.index && day.index <= $0.lastDay }
            switch covering.count {
            case 0:
                if !day.items.isEmpty { loose.append(day) }
            case 1:
                byStay[covering[0].id, default: []].append(day)
            default:
                // A travel day between two stays: split at the first flight or train,
                // or else just after the earlier stay's check-out.
                let earlier = covering[0], later = covering[covering.count - 1]
                let split = day.items.firstIndex(where: \.isJourney)
                    ?? day.items.firstIndex(where: { $0.stayID == earlier.id && $0.isCheckOut }).map { $0 + 1 }
                    ?? 0
                var first = day, second = day
                first.items = Array(day.items[..<split])
                second.items = Array(day.items[split...])
                if !first.items.isEmpty || earlier.lastDay > earlier.firstDay { byStay[earlier.id, default: []].append(first) }
                byStay[later.id, default: []].append(second)
            }
        }

        var result: [Section] = stays.compactMap { stay in
            guard let days = byStay[stay.id], !days.isEmpty else { return nil }
            return Section(id: stay.id, name: stay.city, localName: stay.cityLocalName, stay: stay, days: days)
        }
        // Consecutive days without a hotel become one section each.
        var run: [Day] = []
        func flush() {
            guard let first = run.first, let last = run.last else { return }
            let name = first.index == last.index ? dayLabel(first.date) : "\(dayLabel(first.date)) – \(dayLabel(last.date))"
            result.append(Section(id: "days-\(first.index)", name: name, localName: nil, stay: nil, days: run))
            run = []
        }
        for day in loose {
            if let last = run.last, last.index + 1 != day.index { flush() }
            run.append(day)
        }
        flush()
        return result.sorted { ($0.days.first?.index ?? 0) < ($1.days.first?.index ?? 0) }
    }

    // MARK: City names

    /// "云南省昆明市西山区…" → "昆明"; "北京市顺义区…" → "北京".
    static func chineseCity(fromAddress address: String) -> String? {
        var text = address
        for marker in ["自治区", "省"] {
            if let range = text.range(of: marker) { text = String(text[range.upperBound...]); break }
        }
        guard let shi = text.range(of: "市") else { return nil }
        let city = String(text[..<shi.lowerBound])
        guard (2...5).contains(city.count), city.unicodeScalars.allSatisfy({ $0.properties.isIdeographic }) else { return nil }
        return city
    }

    /// "昆明" → "Kunming".
    static func pinyin(_ chinese: String) -> String {
        let latin = (chinese.applyingTransform(.mandarinToLatin, reverse: false) ?? chinese)
            .applyingTransform(.stripDiacritics, reverse: false) ?? chinese
        let joined = latin.replacingOccurrences(of: " ", with: "")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    // MARK: Page

    struct Options {
        var title: String
        var subtitle: String
        var journeys: [Journey] = []
    }

    static func html(sections: [Section], options: Options) -> String {
        var out = "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        out += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">\n"
        out += "<title>\(esc(options.title))</title>\n<style>\(css)</style>\n</head>\n<body>\n<div class=\"page\">\n"

        // Header
        out += "<header>\n<p class=\"label\">\(esc(options.subtitle))</p>\n<h1>\(esc(options.title))</h1>\n"
        if sections.count > 1 {
            out += "<div class=\"route\">"
            out += sections.map { s in
                "<div class=\"stop\"><b>\(esc(s.name))</b><span>\(esc(rangeLabel(s.days)))</span></div>"
            }.joined(separator: "<span class=\"arrow\">→</span>")
            out += "</div>\n<nav class=\"jump\">"
            if !options.journeys.isEmpty { out += "<a href=\"#getting-around\">Getting around</a>" }
            out += sections.map { "<a href=\"#\(anchor($0))\">\(esc($0.name))</a>" }.joined()
            out += "</nav>\n"
        }
        out += "</header>\n"

        // Flights and trains
        if !options.journeys.isEmpty {
            out += "<section class=\"city\" id=\"getting-around\"><div class=\"city-head\"><h2>Getting around</h2></div><div class=\"passes\">\n"
            for j in options.journeys {
                let day = Calendar.current.component(.day, from: j.date)
                out += "<div class=\"pass\"><div class=\"date\"><span class=\"d\">\(day)</span><span class=\"m\">\(esc(monthLabel(j.date)))</span></div>"
                out += "<div class=\"codes\">\(esc(j.route))</div>"
                if let number = j.number { out += "<span class=\"no\">\(esc(number))</span>" }
                var detail = esc(j.detail)
                if let code = j.confirmation { detail += " · Booking <span class=\"mono\">\(esc(code))</span>" }
                out += "<div class=\"meta\">\(detail)</div></div>\n"
            }
            out += "</div></section>\n"
        }

        // Cities
        for section in sections {
            out += "<section class=\"city\" id=\"\(anchor(section))\">\n<div class=\"city-head\"><h2>\(esc(section.name))</h2>"
            if let local = section.localName { out += "<span class=\"zh\">\(esc(local))</span>" }
            out += "<span class=\"when\">\(esc(rangeLabel(section.days)))\(nightsLabel(section))</span></div>\n"
            if let stay = section.stay {
                out += "<div class=\"stay\"><span class=\"label\">Staying at</span><span class=\"name\">\(esc(stay.name))"
                if let local = stay.localName, local != stay.name { out += " <span class=\"zh\">\(esc(local))</span>" }
                out += "</span>"
                let addresses = [stay.address, stay.localAddress.flatMap { $0 == stay.address ? nil : $0 }].compactMap { $0 }
                if !addresses.isEmpty { out += "<span class=\"addr\">\(addresses.map(esc).joined(separator: " · "))</span>" }
                if let code = stay.confirmation { out += "<span class=\"addr\">Booking <span class=\"mono\">\(esc(code))</span></span>" }
                out += "</div>\n"
            }
            for day in section.days {
                out += "<div class=\"day\"><div class=\"when\"><b>\(esc(weekdayLabel(day.date)))</b><span>Day \(day.index + 1)</span></div><div class=\"items\">"
                if day.items.isEmpty {
                    out += "<p class=\"empty\">Free day.</p>"
                }
                for item in day.items {
                    out += "<div class=\"item\"><span class=\"t\(item.isJourney ? " travel" : "")\">\(esc(item.time ?? ""))</span><div class=\"what\"><span class=\"n\">\(esc(item.name))"
                    if let local = item.localName { out += " <span class=\"zh\">\(esc(local))</span>" }
                    out += "</span>"
                    if let note = item.note, !note.isEmpty { out += "<p>\(esc(note))</p>" }
                    out += "</div></div>"
                }
                out += "</div></div>\n"
            }
            out += "</section>\n"
        }
        out += "<footer>Made with Trippin. Times are local to each city.</footer>\n</div>\n</body>\n</html>\n"
        return out
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func anchor(_ s: Section) -> String {
        let ascii = s.name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" }
        let slug = String(ascii).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? s.id : slug
    }

    private static let en = Locale(identifier: "en_US")
    private static func dayLabel(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day().locale(en)) }
    private static func monthLabel(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).locale(en)) }
    private static func weekdayLabel(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).day().locale(en)) }
    private static func rangeLabel(_ days: [Day]) -> String {
        guard let a = days.first?.date, let b = days.last?.date else { return "" }
        return Calendar.current.isDate(a, inSameDayAs: b) ? dayLabel(a) : "\(dayLabel(a)) – \(dayLabel(b))"
    }
    private static func nightsLabel(_ s: Section) -> String {
        guard let stay = s.stay else { return "" }
        let n = stay.lastDay - stay.firstDay
        return n > 0 ? " · \(n) night\(n == 1 ? "" : "s")" : ""
    }

    // Same look as the shared trip page: tokens for light and dark, one column.
    private static let css = """
    :root{--bg:#f6f8f7;--surface:#fff;--ink:#15201c;--muted:#5b6b65;--faint:#8b9a94;--line:#dde5e1;--accent:#11885f;--accent-soft:#e3f3ec;--sun:#d98a12;--sun-soft:#fbefd9;color-scheme:light;
    --body:-apple-system,"SF Pro Text","Inter","PingFang SC","Hiragino Sans GB","Noto Sans SC",system-ui,sans-serif;--display:-apple-system,"SF Pro Display","Inter","PingFang SC",system-ui,sans-serif;--mono:ui-monospace,"SF Mono",Menlo,monospace}
    @media (prefers-color-scheme:dark){:root{--bg:#0f1513;--surface:#17201d;--ink:#e8efec;--muted:#9fb0a9;--faint:#6f817a;--line:#26332e;--accent:#4cc895;--accent-soft:#173229;--sun:#f0b04a;--sun-soft:#33270f;color-scheme:dark}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--ink);font:400 15px/1.55 var(--body);padding:32px max(16px,env(safe-area-inset-right)) 64px max(16px,env(safe-area-inset-left))}
    .page{max-width:760px;margin:0 auto;display:grid;gap:40px}
    h1,h2{font-family:var(--display);margin:0;letter-spacing:-.01em;text-wrap:balance}
    p{margin:0}.zh{font-family:"PingFang SC","Hiragino Sans GB","Noto Sans SC",sans-serif}.mono{font-family:var(--mono)}
    .label{font-size:11px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}
    header{display:grid;gap:16px}header h1{font-size:clamp(32px,7vw,50px);line-height:1.04;font-weight:700}
    .route{display:flex;flex-wrap:wrap;align-items:center;gap:6px 8px;font-family:var(--mono);font-size:13px}
    .route .stop{display:grid;padding:6px 10px;border-radius:8px;background:var(--surface);border:1px solid var(--line)}
    .route .stop span{color:var(--muted);font-size:11px}.route .arrow{color:var(--faint)}
    .jump{display:flex;flex-wrap:wrap;gap:8px}.jump a{text-decoration:none;font-weight:500;font-size:13px;padding:6px 12px;border-radius:999px;background:var(--surface);border:1px solid var(--line);color:var(--ink)}
    .passes{display:grid;gap:10px}
    .pass{display:grid;grid-template-columns:auto 1fr auto;gap:4px 14px;align-items:center;background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:12px 16px}
    .pass .date{grid-row:span 2;display:grid;place-items:center;width:52px;line-height:1.1;border-right:1px dashed var(--line);padding-right:12px}
    .pass .date .d{font:700 22px var(--display)}.pass .date .m{font-size:11px;color:var(--muted);text-transform:uppercase}
    .pass .codes{font-family:var(--mono);font-weight:700;font-size:18px;min-width:0}
    .pass .meta{color:var(--muted);font-size:13px;min-width:0}
    .pass .no{grid-row:span 2;font-family:var(--mono);font-size:12px;font-weight:700;color:var(--sun);background:var(--sun-soft);padding:4px 8px;border-radius:6px;white-space:nowrap}
    .city{display:grid;gap:16px}
    .city-head{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 12px;border-bottom:2px solid var(--ink);padding-bottom:8px}
    .city-head h2{font-size:30px}.city-head .zh{font-size:20px;color:var(--muted)}
    .city-head .when{margin-left:auto;font-family:var(--mono);font-size:13px;color:var(--muted)}
    .stay{display:grid;gap:4px;background:var(--accent-soft);border-radius:12px;padding:14px 16px}
    .stay .name{font-weight:600}.stay .addr{font-size:13px;color:var(--muted)}
    .day{display:grid;grid-template-columns:92px 1fr;gap:12px}
    .day>.when b{display:block;font:700 15px var(--display)}.day>.when span{font-size:12px;color:var(--muted)}
    .items{display:grid;gap:12px;border-left:2px solid var(--line);padding-left:14px;min-width:0}
    .item{display:grid;grid-template-columns:52px 1fr;gap:8px;min-width:0}
    .item .t{font-family:var(--mono);font-size:12px;font-weight:700;color:var(--accent);padding-top:3px}.item .t.travel{color:var(--sun)}
    .item .what{min-width:0;display:grid;gap:2px}.item .what .n{font-weight:600}.item .what .n .zh{font-weight:500;color:var(--muted)}
    .item .what p{color:var(--muted);font-size:14px}.empty{color:var(--muted);font-style:italic}
    footer{color:var(--faint);font-size:12px;border-top:1px solid var(--line);padding-top:16px}
    @media (max-width:560px){.day{grid-template-columns:1fr;gap:6px}.day>.when b,.day>.when span{display:inline;margin-right:6px}.pass{grid-template-columns:auto 1fr}.pass .date{grid-row:span 3}.pass .codes,.pass .meta,.pass .no{grid-column:2}.pass .no{grid-row:auto;justify-self:start}.city-head .when{margin-left:0;width:100%}}
    """
}

extension TripExport.Item {
    var isCheckOut: Bool { name.hasPrefix("Check out") }
}
