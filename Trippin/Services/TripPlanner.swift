import Foundation
import SwiftData
import MapKit

/// Trip-level actions shared by several screens.
@MainActor
enum TripPlanner {

    /// Saves a parsed reservation to the trip, puts it on the right day(s) and finds it on the map.
    @discardableResult
    static func add(_ parsed: ParsedReservation, rawText: String, to trip: Trip, context: ModelContext) async -> Reservation {
        let reservation = Reservation(from: parsed, rawText: rawText)
        context.insert(reservation)
        reservation.trip = trip

        extendTrip(trip, for: parsed)

        let place = await locate(parsed, in: trip)
        reservation.latitude = place?.coordinate.latitude
        reservation.longitude = place?.coordinate.longitude
        if reservation.address == nil { reservation.address = place?.address }

        makeStops(for: reservation, parsed: parsed, coordinate: place?.coordinate, in: trip, context: context)
        try? context.save()
        return reservation
    }

    /// Applies edits to a saved reservation and rebuilds its stops so their
    /// days, times and location match. Notes on the old stops are kept.
    static func update(_ reservation: Reservation, with parsed: ParsedReservation, context: ModelContext) async {
        guard let trip = reservation.trip else { return }
        let moved = parsed.address != reservation.address
            || (parsed.address == nil && parsed.title != reservation.title)
            || reservation.coordinate == nil

        reservation.kind = parsed.kind
        reservation.title = parsed.title
        reservation.confirmationCode = parsed.confirmationCode
        reservation.start = parsed.start
        reservation.end = parsed.end
        reservation.localName = parsed.localName
        reservation.address = parsed.address
        extendTrip(trip, for: parsed)

        var coordinate = reservation.coordinate
        if moved {
            let place = await locate(parsed, in: trip)
            coordinate = place?.coordinate
            reservation.latitude = coordinate?.latitude
            reservation.longitude = coordinate?.longitude
            if reservation.address == nil { reservation.address = place?.address }
        }

        let old = reservation.stops.sorted { ($0.fixedTime ?? .distantFuture) < ($1.fixedTime ?? .distantFuture) }
        let notes = old.map(\.note)
        let localAddress = moved ? nil : old.lazy.compactMap(\.localAddress).first
        for stop in old { context.delete(stop) }
        reservation.stops = []

        let stops = makeStops(for: reservation, parsed: parsed, coordinate: coordinate, in: trip, context: context)
        for (stop, note) in zip(stops, notes) { stop.note = note }
        if let localAddress {
            for stop in stops { stop.localAddress = localAddress }
        }
        try? context.save()
    }

    private static func extendTrip(_ trip: Trip, for parsed: ParsedReservation) {
        if let start = parsed.start { trip.extend(toInclude: start) }
        if let end = parsed.end, parsed.kind.spansDays { trip.extend(toInclude: end) }
    }

    private static func locate(_ parsed: ParsedReservation, in trip: Trip) async -> PlaceSearch.Place? {
        guard let query = parsed.address ?? (parsed.title.isEmpty ? nil : parsed.title) else { return nil }
        let region = await PlaceSearch.region(for: trip.destination)
        return await PlaceSearch.first(query, near: region)
    }

    @discardableResult
    private static func makeStops(for reservation: Reservation, parsed: ParsedReservation,
                                  coordinate: CLLocationCoordinate2D?, in trip: Trip, context: ModelContext) -> [Stop] {
        stopMoments(for: parsed).map { label, date in
            let day = date.flatMap { trip.dayIndex(for: $0) } ?? 0
            let stop = Stop(name: label.isEmpty ? parsed.title : "\(label): \(parsed.title)",
                            address: reservation.address,
                            coordinate: coordinate,
                            dayIndex: day,
                            sortOrder: sortOrder(for: date, inDay: day, of: trip),
                            fixedTime: date,
                            symbol: parsed.kind.symbol)
            stop.localName = parsed.localName
            context.insert(stop)
            stop.trip = trip
            stop.reservation = reservation
            return stop
        }
    }

    /// Hotels and car rentals appear on both their first and last day.
    private static func stopMoments(for parsed: ParsedReservation) -> [(String, Date?)] {
        switch parsed.kind {
        case .hotel, .car:
            return [(parsed.kind.startLabel, parsed.start)] + (parsed.end.map { [(parsed.kind.endLabel, $0)] } ?? [])
        default:
            return [("", parsed.start)]
        }
    }

    /// Places a timed stop between the existing stops by time of day.
    private static func sortOrder(for date: Date?, inDay day: Int, of trip: Trip, excluding: Stop? = nil) -> Double {
        let stops = trip.stops(onDay: day).filter { $0 !== excluding }
        guard let date else { return (stops.last?.sortOrder ?? 0) + 1 }
        if let next = stops.first(where: { ($0.fixedTime ?? .distantFuture) > date }) {
            let index = stops.firstIndex(of: next)!
            let previous = index > 0 ? stops[index - 1].sortOrder : next.sortOrder - 1
            return (previous + next.sortOrder) / 2
        }
        return (stops.last?.sortOrder ?? 0) + 1
    }

    static func addStop(_ place: PlaceSearch.Place, localName: String? = nil, note: String = "", symbol: String = "mappin",
                        day: Int, to trip: Trip, context: ModelContext) {
        let order = (trip.stops(onDay: day).last?.sortOrder ?? 0) + 1
        let stop = Stop(name: place.name, address: place.address, coordinate: place.coordinate,
                        dayIndex: day, sortOrder: order, note: note, symbol: symbol)
        stop.localName = (localName?.isEmpty ?? true) ? nil : localName
        context.insert(stop)
        stop.trip = trip
        try? context.save()
    }

    /// Moves a stop to another day, keeping its time of day, and slots it in by time.
    static func move(_ stop: Stop, toDay day: Int, of trip: Trip) {
        guard stop.dayIndex != day else { return }
        if let time = stop.fixedTime {
            let cal = Calendar.current
            let parts = cal.dateComponents([.hour, .minute], from: time)
            stop.fixedTime = cal.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0,
                                      of: trip.date(forDay: day))
        }
        stop.dayIndex = day
        stop.sortOrder = sortOrder(for: stop.fixedTime, inDay: day, of: trip, excluding: stop)
    }

    /// Re-slots a stop on its own day after its time changes.
    static func resort(_ stop: Stop, in trip: Trip) {
        stop.sortOrder = sortOrder(for: stop.fixedTime, inDay: stop.dayIndex, of: trip, excluding: stop)
    }

    /// Points a stop at a new place and clears the old local name so it is looked up again.
    static func relocate(_ stop: Stop, to place: PlaceSearch.Place, rename: Bool) {
        if rename { stop.name = place.name }
        stop.address = place.address
        stop.coordinate = place.coordinate
        stop.localName = nil
        stop.localAddress = nil
        stop.localLookupDone = false
    }

    /// Reorders a day's stops to cut travel, keeping timed stops in time order.
    /// Returns the meters saved (0 if nothing changed).
    @discardableResult
    static func optimize(day: Int, of trip: Trip) -> Double {
        let stops = trip.stops(onDay: day)
        guard stops.count > 2 else { return 0 }
        let items = stops.map {
            RouteOptimizer.Item(id: $0.id,
                                point: $0.coordinate.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) },
                                fixedTime: $0.fixedTime)
        }
        let before = RouteOptimizer.length(items)
        let order = RouteOptimizer.optimize(items)
        let byID = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) })
        let reordered = order.compactMap { byID[$0] }
        for (index, stop) in reordered.enumerated() { stop.sortOrder = Double(index + 1) }
        let after = RouteOptimizer.length(order.compactMap { id in items.first { $0.id == id } })
        return max(0, before - after)
    }
}
