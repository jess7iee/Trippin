import Testing
import Foundation

/// A pasted multi-booking itinerary in the style trip-planning assistants write.
/// All names, codes and seats are made up.
struct ItineraryParserTests {
    private let itinerary = """
    **March 3–4 — Los Angeles → Shanghai**  
    Fly Example Air **EX101**, departing Los Angeles (LAX) on March 3 at **11:30 AM** and arriving at Shanghai Pudong (PVG) on March 4 at **6:10 PM**. Your seat is **32A**, and your booking reference is **QZPL42**.

    **March 4 — Shanghai hotel**  
    Stay at **静安示例酒店**. Address: **上海市静安区南京西路100号**.

    **March 5–8 — Hangzhou hotel**  
    Stay at **Lakeview Sample Hotel / 西湖示例酒店**. Address: **浙江省杭州市西湖区北山街1号**. Exact hotel reservation dates remain unconfirmed.

    **March 8 — Hangzhou → Suzhou**  
    Take train **G7321**, departing at **14:05 (2:05 PM)**. You are in **Car 5 / 5号车厢, Seat 07C**.

    **March 9–11 — Tokyo**  
    Your Tokyo accommodation remains to be added. You arrive at Narita (NRT) and depart from Haneda (HND).

    **March 11 — Tokyo → Los Angeles**  
    Fly Example Air **EX202**, departing Tokyo Haneda (HND) at **5:00 PM** and arriving in Los Angeles (LAX) at **10:30 AM the same day**. Your booking reference is **RT88MK**.

    *All times are local to the departure or arrival city.*
    """

    /// Mid-January, so March without a year is this year's.
    private let now = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 15))!

    private func parts(_ date: Date?) -> [Int] {
        guard let date else { return [] }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return [c.year!, c.month!, c.day!, c.hour!, c.minute!]
    }

    @Test func findsEachBookingAndSkipsNotes() {
        let all = EmailParser.parseAll(itinerary, now: now)
        #expect(all.map(\.kind) == [.flight, .hotel, .hotel, .train, .flight])
    }

    @Test func overnightFlight() {
        let flight = EmailParser.parseAll(itinerary, now: now)[0]
        #expect(flight.title == "Flight EX101 LAX → PVG")
        #expect(flight.confirmationCode == "QZPL42")
        #expect(parts(flight.start) == [2027, 3, 3, 11, 30])
        #expect(parts(flight.end) == [2027, 3, 4, 18, 10])
        #expect(flight.address == "Los Angeles Airport")
    }

    @Test func hotelsGetDatesNamesAndAddresses() {
        let all = EmailParser.parseAll(itinerary, now: now)
        let shanghai = all[1], hangzhou = all[2]
        #expect(shanghai.title == "静安示例酒店")
        #expect(shanghai.address == "上海市静安区南京西路100号")
        #expect(shanghai.confirmationCode == nil)
        // A single date is one night.
        #expect(parts(shanghai.start) == [2027, 3, 4, 15, 0])
        #expect(parts(shanghai.end) == [2027, 3, 5, 11, 0])

        #expect(hangzhou.title == "Lakeview Sample Hotel")
        #expect(hangzhou.localName == "西湖示例酒店")
        #expect(hangzhou.address == "浙江省杭州市西湖区北山街1号")
        #expect(parts(hangzhou.start) == [2027, 3, 5, 15, 0])
        #expect(parts(hangzhou.end) == [2027, 3, 8, 11, 0])
    }

    @Test func trainUsesHeadingDateAndRoute() {
        let train = EmailParser.parseAll(itinerary, now: now)[3]
        #expect(train.title == "Train G7321 Hangzhou → Suzhou")
        #expect(parts(train.start) == [2027, 3, 8, 14, 5])
        #expect(train.end == nil)
        #expect(train.address == "Hangzhou Railway Station")
    }

    @Test func returnFlightArrivingEarlierLocalTimeHasNoEnd() {
        let flight = EmailParser.parseAll(itinerary, now: now)[4]
        #expect(flight.title == "Flight EX202 HND → LAX")
        #expect(flight.confirmationCode == "RT88MK")
        #expect(flight.address == "Tokyo Haneda Airport")
        #expect(parts(flight.start) == [2027, 3, 11, 17, 0])
        #expect(flight.end == nil)
    }

    @Test func missingYearRollsToNextYear() {
        let late = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        let r = EmailParser.parse("Fly Example Air EX9 on March 3 at 9:00 AM", now: late)
        #expect(parts(r.start) == [2027, 3, 3, 9, 0])
    }

    @Test func singleEmailStillGivesOneBooking() {
        let email = """
        Your flight is confirmed
        Confirmation code: K7XQ2P
        Flight UA 837
        SFO → NRT
        Departure: March 6, 2027 at 11:05 AM

        Arrival: March 7, 2027 at 3:20 PM
        """
        #expect(EmailParser.parseAll(email).count == 1)
    }
}
