import Foundation
import SwiftData
import CoreLocation

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    var destination: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Reservation.trip) var reservations: [Reservation] = []
    @Relationship(deleteRule: .cascade, inverse: \Stop.trip) var stops: [Stop] = []
    @Relationship(deleteRule: .cascade, inverse: \TodoItem.trip) var todos: [TodoItem] = []

    init(name: String, destination: String, startDate: Date, endDate: Date) {
        self.name = name
        self.destination = destination
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: max(startDate, endDate))
    }

    /// Number of day pages (Day 1 … Day N).
    var dayCount: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return max(1, days + 1)
    }

    func date(forDay index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
    }

    /// Zero-based day index for a date, or nil when it falls outside the trip.
    func dayIndex(for date: Date) -> Int? {
        let start = Calendar.current.startOfDay(for: startDate)
        let day = Calendar.current.startOfDay(for: date)
        guard let diff = Calendar.current.dateComponents([.day], from: start, to: day).day,
              diff >= 0, diff < dayCount else { return nil }
        return diff
    }

    /// Grows the trip so the date has a day page.
    func extend(toInclude date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if day < startDate { startDate = day }
        if day > endDate { endDate = day }
    }

    func stops(onDay index: Int) -> [Stop] {
        stops.filter { $0.dayIndex == index }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedReservations: [Reservation] {
        reservations.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
}

@Model
final class Reservation {
    var id: UUID = UUID()
    var kindRaw: String = ReservationKind.other.rawValue
    var title: String = ""
    var confirmationCode: String?
    var start: Date?
    var end: Date?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var rawText: String = ""
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Stop.reservation) var stops: [Stop] = []

    init(from parsed: ParsedReservation, rawText: String) {
        self.kindRaw = parsed.kind.rawValue
        self.title = parsed.title
        self.confirmationCode = parsed.confirmationCode
        self.start = parsed.start
        self.end = parsed.end
        self.address = parsed.address
        self.rawText = rawText
    }

    var kind: ReservationKind {
        get { ReservationKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// One place on a day's itinerary. Reservations create stops automatically;
/// recommendations and searches add more.
@Model
final class Stop {
    var id: UUID = UUID()
    var name: String = ""
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var dayIndex: Int = 0
    var sortOrder: Double = 0
    /// Set for reservation stops; the optimizer keeps these in time order.
    var fixedTime: Date?
    var note: String = ""
    var symbol: String = "mappin"
    var trip: Trip?
    var reservation: Reservation?

    init(name: String, address: String? = nil, coordinate: CLLocationCoordinate2D? = nil,
         dayIndex: Int, sortOrder: Double, fixedTime: Date? = nil, note: String = "", symbol: String = "mappin") {
        self.name = name
        self.address = address
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.dayIndex = dayIndex
        self.sortOrder = sortOrder
        self.fixedTime = fixedTime
        self.note = note
        self.symbol = symbol
    }

    var coordinate: CLLocationCoordinate2D? {
        get {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue?.latitude
            longitude = newValue?.longitude
        }
    }
}

@Model
final class TodoItem {
    var id: UUID = UUID()
    var text: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date()
    var trip: Trip?

    init(text: String) {
        self.text = text
    }
}
