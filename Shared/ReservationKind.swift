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

    /// Label for the start time, e.g. "Check in" for a hotel.
    var startLabel: String {
        switch self {
        case .hotel: "Check in"
        case .flight, .train: "Departs"
        case .car: "Pick up"
        default: "Starts"
        }
    }

    /// Label for the end time, e.g. "Check out" for a hotel.
    var endLabel: String {
        switch self {
        case .hotel: "Check out"
        case .flight, .train: "Arrives"
        case .car: "Drop off"
        default: "Ends"
        }
    }

    /// Flights and trains go from one place to another.
    var isJourney: Bool { self == .flight || self == .train }

    /// Hotels and car rentals get a stop on both their first and last day.
    var spansDays: Bool { self == .hotel || self == .car }
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
    /// Name in the local language and script, when known.
    var localName: String?
    /// Where a flight or train arrives, to find it on a map, e.g. "Beijing Capital Airport".
    var arrivalPlace: String?

    static func ==(lhs: ParsedReservation, rhs: ParsedReservation) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.confirmationCode == rhs.confirmationCode
            && lhs.start == rhs.start && lhs.end == rhs.end && lhs.address == rhs.address
            && lhs.localName == rhs.localName && lhs.arrivalPlace == rhs.arrivalPlace
    }
}
