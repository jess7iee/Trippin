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

        if let start = parsed.start { trip.extend(toInclude: start) }
        if let end = parsed.end, parsed.kind == .hotel || parsed.kind == .car { trip.extend(toInclude: end) }

        var place: PlaceSearch.Place?
        if let query = parsed.address ?? (parsed.title.isEmpty ? nil : parsed.title) {
            let region = await PlaceSearch.region(for: trip.destination)
            place = await PlaceSearch.first(query, near: region)
        }
        reservation.latitude = place?.coordinate.latitude
        reservation.longitude = place?.coordinate.longitude
        if reservation.address == nil { reservation.address = place?.address }

        for (label, date) in stopMoments(for: parsed) {
            let day = date.flatMap { trip.dayIndex(for: $0) } ?? 0
            let stop = Stop(name: label.isEmpty ? parsed.title : "\(label): \(parsed.title)",
                            address: reservation.address,
                            coordinate: place?.coordinate,
                            dayIndex: day,
                            sortOrder: sortOrder(for: date, inDay: day, of: trip),
                            fixedTime: date,
                            symbol: parsed.kind.symbol)
            context.insert(stop)
            stop.trip = trip
            stop.reservation = reservation
        }
        try? context.save()
        return reservation
    }

    /// Hotels and car rentals appear on both their first and last day.
    private static func stopMoments(for parsed: ParsedReservation) -> [(String, Date?)] {
        switch parsed.kind {
        case .hotel:
            return [("Check in", parsed.start)] + (parsed.end.map { [("Check out", $0)] } ?? [])
        case .car:
            return [("Pick up", parsed.start)] + (parsed.end.map { [("Drop off", $0)] } ?? [])
        default:
            return [("", parsed.start)]
        }
    }

    /// Places a timed stop between the existing stops by time of day.
    private static func sortOrder(for date: Date?, inDay day: Int, of trip: Trip) -> Double {
        let stops = trip.stops(onDay: day)
        guard let date else { return (stops.last?.sortOrder ?? 0) + 1 }
        if let next = stops.first(where: { ($0.fixedTime ?? .distantFuture) > date }) {
            let index = stops.firstIndex(of: next)!
            let previous = index > 0 ? stops[index - 1].sortOrder : next.sortOrder - 1
            return (previous + next.sortOrder) / 2
        }
        return (stops.last?.sortOrder ?? 0) + 1
    }

    static func addStop(_ place: PlaceSearch.Place, note: String = "", symbol: String = "mappin",
                        day: Int, to trip: Trip, context: ModelContext) {
        let order = (trip.stops(onDay: day).last?.sortOrder ?? 0) + 1
        let stop = Stop(name: place.name, address: place.address, coordinate: place.coordinate,
                        dayIndex: day, sortOrder: order, note: note, symbol: symbol)
        context.insert(stop)
        stop.trip = trip
        try? context.save()
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
