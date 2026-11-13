import Foundation

/// The kinds of bookings Trippin understands.
enum ReservationKind: String, Codable, CaseIterable, Identifiable {
    case flight, hotel, restaurant, car, train, activity, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flight: "Flight"
        case .hotel: "Hotel"
        case .restaurant: "Restaurant"
        case .car: "Car rental"
        case .train: "Train"
        case .activity: "Activity"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .hotel: "bed.double.fill"
        case .restaurant: "fork.knife"
        case .car: "car.fill"
        case .train: "tram.fill"
        case .activity: "ticket.fill"
        case .other: "doc.text.fill"
        }
    }
}

/// A reservation pulled out of an email, before it is saved to a trip.
struct ParsedReservation: Equatable, Identifiable {
    var id = UUID()
    var kind: ReservationKind = .other
    var title: String = ""
    var confirmationCode: String?
    var start: Date?
    var end: Date?
    /// Address or place name used to find the location on the map.
    var address: String?

    static func == (lhs: ParsedReservation, rhs: ParsedReservation) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.confirmationCode == rhs.confirmationCode
            && lhs.start == rhs.start && lhs.end == rhs.end && lhs.address == rhs.address
    }
}
