import Testing
import Foundation

struct TripExportTests {
    private func day(_ i: Int, _ items: [TripExport.Item] = []) -> TripExport.Day {
        TripExport.Day(index: i, date: Calendar.current.date(from: DateComponents(year: 2027, month: 3, day: 1 + i))!, items: items)
    }
    private func item(_ name: String, journey: Bool = false, stay: String? = nil) -> TripExport.Item {
        TripExport.Item(time: nil, name: name, isJourney: journey, stayID: stay)
    }
    private let a = TripExport.Stay(id: "A", name: "Hotel A", firstDay: 1, lastDay: 3, city: "Alpha")
    private let b = TripExport.Stay(id: "B", name: "Hotel B", firstDay: 3, lastDay: 5, city: "Beta")

    @Test func groupsDaysByStayAndSplitsTravelDay() {
        let days = [
            day(0, [item("Flight in", journey: true)]),
            day(1, [item("Check in: Hotel A", stay: "A")]),
            day(2),
            day(3, [item("Check out: Hotel A", stay: "A"), item("Museum"), item("Train", journey: true), item("Check in: Hotel B", stay: "B")]),
            day(4, [item("Lake")]),
            day(5, [item("Check out: Hotel B", stay: "B")]),
            day(6),
            day(7, [item("Flight home", journey: true)]),
        ]
        let sections = TripExport.sections(days: days, stays: [b, a])
        #expect(sections.map(\.name) == ["Mar 1", "Alpha", "Beta", "Mar 8"])
        let alpha = sections[1], beta = sections[2]
        #expect(alpha.days.map(\.index) == [1, 2, 3])
        #expect(alpha.days.last?.items.map(\.name) == ["Check out: Hotel A", "Museum"])
        #expect(beta.days.map(\.index) == [3, 4, 5])
        #expect(beta.days.first?.items.map(\.name) == ["Train", "Check in: Hotel B"])
        // Empty days with no hotel are left out; an empty day during a stay stays as a free day.
        #expect(!sections.contains { $0.days.contains { $0.index == 6 } })
        #expect(alpha.days[1].items.isEmpty)
    }

    @Test func splitsAfterCheckOutWhenNoTrainOrFlight() {
        let days = [day(3, [item("Breakfast"), item("Check out: Hotel A", stay: "A"), item("Check in: Hotel B", stay: "B")])]
        let sections = TripExport.sections(days: days, stays: [a, b])
        #expect(sections[0].days[0].items.map(\.name) == ["Breakfast", "Check out: Hotel A"])
        #expect(sections[1].days[0].items.map(\.name) == ["Check in: Hotel B"])
    }

    @Test func cityNamesFromChineseAddresses() {
        #expect(TripExport.chineseCity(fromAddress: "云南省昆明市西山区广福路与前兴路交叉口") == "昆明")
        #expect(TripExport.chineseCity(fromAddress: "北京市顺义区天竺镇府前一街32号") == "北京")
        #expect(TripExport.chineseCity(fromAddress: "云南省丽江市古城区束河古镇") == "丽江")
        #expect(TripExport.chineseCity(fromAddress: "3-7-1-2 Nishi Shinjuku, Tokyo") == nil)
        #expect(TripExport.pinyin("昆明") == "Kunming")
        #expect(TripExport.pinyin("北京") == "Beijing")
    }

    @Test func pageEscapesTextAndListsSections() {
        var stay = a
        stay.name = "Hotel <A> & Spa"
        let sections = TripExport.sections(days: [day(1, [item("Tea")]), day(2)], stays: [stay])
        let html = TripExport.html(sections: sections, options: .init(title: "Alpha", subtitle: "Mar 2027"))
        #expect(html.contains("Hotel &lt;A&gt; &amp; Spa"))
        #expect(html.contains("<h2>Alpha</h2>"))
        #expect(html.contains("Free day."))
        #expect(!html.contains("Booking"))
    }
}
