import Testing

struct ReservationKindTests {
    @Test func timeLabelsMatchKind() {
        #expect(ReservationKind.hotel.startLabel == "Check in")
        #expect(ReservationKind.hotel.endLabel == "Check out")
        #expect(ReservationKind.flight.startLabel == "Departs")
        #expect(ReservationKind.car.endLabel == "Drop off")
        #expect(ReservationKind.restaurant.startLabel == "Starts")
    }

    @Test func onlyStaysAndRentalsSpanDays() {
        #expect(ReservationKind.allCases.filter(\.spansDays) == [.hotel, .car])
    }
}
