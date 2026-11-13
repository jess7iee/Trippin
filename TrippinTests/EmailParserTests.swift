import Testing
import Foundation

struct EmailParserTests {

    @Test func flightEmail() {
        let email = """
        Your flight is confirmed
        Confirmation code: K7XQ2P
        Flight UA 837
        SFO → NRT
        Departure: March 6, 2027 at 11:05 AM
        Arrival: March 7, 2027 at 3:20 PM
        """
        let r = EmailParser.parse(email)
        #expect(r.kind == .flight)
        #expect(r.confirmationCode == "K7XQ2P")
        #expect(r.title.contains("SFO → NRT"))
        #expect(r.title.contains("UA 837"))
        #expect(r.start != nil)
        #expect(r.end != nil)
        if let start = r.start, let end = r.end { #expect(end > start) }
    }

    @Test func hotelEmail() {
        let email = """
        Hotel: Park Hyatt Tokyo
        Booking number: 88231045
        Check-in: Sunday, March 7, 2027, 3:00 PM
        Check-out: Wednesday, March 10, 2027, 12:00 PM
        3 nights, King room
        Address: 3-7-1-2 Nishi Shinjuku, Shinjuku-ku, Tokyo
        """
        let r = EmailParser.parse(email)
        #expect(r.kind == .hotel)
        #expect(r.title == "Park Hyatt Tokyo")
        #expect(r.confirmationCode == "88231045")
        #expect(r.address?.contains("Nishi Shinjuku") == true)
        let days = r.start.flatMap { s in r.end.map { Calendar.current.dateComponents([.day], from: s, to: $0).day } }
        #expect(days == 2 || days == 3)
    }

    @Test func restaurantEmail() {
        let email = """
        Subject: Your reservation at Sushi Saito
        Party of 2 on Monday, March 8, 2027 at 7:30 PM
        Reservation #: RS2291A
        """
        let r = EmailParser.parse(email)
        #expect(r.kind == .restaurant)
        #expect(r.confirmationCode == "RS2291A")
        #expect(r.title == "Your reservation at Sushi Saito")
        #expect(r.start != nil)
    }

    @Test func ignoresWordsThatAreNotCodes() {
        #expect(EmailParser.confirmationCode(in: "Reservation CONFIRMED for tonight") == nil)
    }
}
