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

    /// The hotel you wake up in and return to on a day between check-in and check-out.
    /// (Check-in and check-out days already have their own stops.)
    func baseHotel(onDay day: Int) -> Reservation? {
        reservations.first { r in
            guard r.kind == .hotel, let start = r.start else { return false }
            let first = dayIndex(for: start) ?? (start < startDate ? -1 : dayCount)
            let last = r.end.map { dayIndex(for: $0) ?? ($0 < startDate ? -1 : dayCount) } ?? first + 1
            return first < day && day < last
        }
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
    /// Name as written locally, e.g. パーク ハイアット 東京.
    var localName: String?
    /// For flights and trains: where it arrives.
    var arrivalAddress: String?
    var arrivalLatitude: Double?
    var arrivalLongitude: Double?
    /// Bumped when the way locations are found improves, so older bookings get looked up again.
    var locationVersion: Int = 0
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Stop.reservation) var stops: [Stop] = []

    init(from parsed: ParsedReservation, rawText: String) {
        self.kindRaw = parsed.kind.rawValue
        self.title = parsed.title
        self.confirmationCode = parsed.confirmationCode
        self.start = parsed.start
        self.end = parsed.end
        self.address = parsed.address
        self.localName = parsed.localName
        self.arrivalAddress = parsed.arrivalPlace
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

    var arrivalCoordinate: CLLocationCoordinate2D? {
        get {
            guard let arrivalLatitude, let arrivalLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: arrivalLatitude, longitude: arrivalLongitude)
        }
        set {
            arrivalLatitude = newValue?.latitude
            arrivalLongitude = newValue?.longitude
        }
    }

    /// The editable fields, for the reservation editor.
    var fields: ParsedReservation {
        ParsedReservation(kind: kind, title: title, confirmationCode: confirmationCode,
                          start: start, end: end, address: address, localName: localName,
                          arrivalPlace: arrivalAddress)
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
    /// Name in the local language and script, e.g. 新宿駅 for Shinjuku Station.
    var localName: String?
    /// Address in the local language, handy for taxis.
    var localAddress: String?
    /// True once the app has looked up the local name and address.
    var localLookupDone: Bool = false
    /// ISO country code from the geocoder, e.g. "CN". Picks which apps the place can open in.
    var countryCode: String?
    /// True when the location is an estimate (Apple Maps didn't list the place).
    /// Maps apps then search by name instead of dropping a pin there.
    var approximateLocation: Bool = false
    /// What to search for in a maps app when the location isn't exact, e.g.
    /// "Donglaishun Wangfujing, Dongcheng, Beijing".
    var searchQuery: String?
    var trip: Trip?
    var reservation: Reservation?

    /// The local name, only when it differs from the display name.
    var distinctLocalName: String? {
        guard let localName, !localName.isEmpty,
              localName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame,
              !name.contains(localName) else { return nil }
        return localName
    }

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

    /// For a flight or train stop: where it arrives, so the day's route continues from there.
    var arrivalCoordinate: CLLocationCoordinate2D? {
        guard reservation?.kind.isJourney == true else { return nil }
        return reservation?.arrivalCoordinate
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
    /// Places added for it from recommendations, e.g. "Ichiran Shibuya, Fuunji".
    var plannedAs: String = ""
    var trip: Trip?

    init(text: String) {
        self.text = text
    }
}
