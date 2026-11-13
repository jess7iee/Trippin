import Foundation

struct GeoPoint: Equatable {
    var latitude: Double
    var longitude: Double

    /// Great-circle distance in meters.
    func distance(to other: GeoPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Orders one day's stops to cut travel distance.
///
/// Stops with a fixed time (flights, restaurant bookings, check-ins) stay in
/// time order and act as anchors; flexible stops are inserted between them
/// where they add the least distance, then each run of flexible stops is
/// tidied with 2-opt.
enum RouteOptimizer {

    struct Item: Equatable {
        var id: UUID
        var point: GeoPoint?
        var fixedTime: Date?
    }

    static func optimize(_ items: [Item], start: GeoPoint? = nil) -> [UUID] {
        let anchors = items.filter { $0.fixedTime != nil }.sorted { $0.fixedTime! < $1.fixedTime! }
        let flexible = items.filter { $0.fixedTime == nil && $0.point != nil }
        let unlocated = items.filter { $0.fixedTime == nil && $0.point == nil }

        var route = anchors
        for item in nearestNeighborOrder(flexible, from: start ?? anchors.first?.point) {
            let position = bestInsertion(of: item, into: route, start: start)
            route.insert(item, at: position)
        }
        route = twoOptFlexibleRuns(route, start: start)
        return route.map(\.id) + unlocated.map(\.id)
    }

    /// Total distance of a route in meters, skipping stops without a location.
    static func length(_ items: [Item], start: GeoPoint? = nil) -> Double {
        var points = items.compactMap(\.point)
        if let start { points.insert(start, at: 0) }
        return zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    // MARK: Steps

    private static func nearestNeighborOrder(_ items: [Item], from origin: GeoPoint?) -> [Item] {
        var remaining = items
        var ordered: [Item] = []
        var current = origin
        while !remaining.isEmpty {
            let index: Int
            if let current {
                index = remaining.indices.min { remaining[$0].point!.distance(to: current) < remaining[$1].point!.distance(to: current) }!
            } else {
                index = 0
            }
            let next = remaining.remove(at: index)
            ordered.append(next)
            current = next.point
        }
        return ordered
    }

    private static func bestInsertion(of item: Item, into route: [Item], start: GeoPoint?) -> Int {
        guard let p = item.point else { return route.count }
        var bestIndex = route.count
        var bestCost = Double.infinity
        for i in 0...route.count {
            let prev = i == 0 ? start : lastPoint(in: route, before: i)
            let next = nextPoint(in: route, from: i)
            let cost: Double
            switch (prev, next) {
            case let (a?, b?): cost = a.distance(to: p) + p.distance(to: b) - a.distance(to: b)
            case let (a?, nil): cost = a.distance(to: p)
            case let (nil, b?): cost = p.distance(to: b)
            case (nil, nil): cost = 0
            }
            if cost < bestCost - 0.001 {
                bestCost = cost
                bestIndex = i
            }
        }
        return bestIndex
    }

    private static func lastPoint(in route: [Item], before index: Int) -> GeoPoint? {
        route[..<index].last(where: { $0.point != nil })?.point
    }

    private static func nextPoint(in route: [Item], from index: Int) -> GeoPoint? {
        route[index...].first(where: { $0.point != nil })?.point
    }

    /// Reverses sub-sequences inside each run of flexible stops while that shortens the route.
    private static func twoOptFlexibleRuns(_ route: [Item], start: GeoPoint?) -> [Item] {
        var route = route
        var improved = true
        var passes = 0
        while improved && passes < 50 {
            improved = false
            passes += 1
            var runStart = 0
            while runStart < route.count {
                guard route[runStart].fixedTime == nil else { runStart += 1; continue }
                var runEnd = runStart
                while runEnd + 1 < route.count && route[runEnd + 1].fixedTime == nil { runEnd += 1 }
                if runEnd > runStart {
                    for i in runStart..<runEnd {
                        for j in (i + 1)...runEnd {
                            var candidate = route
                            candidate[i...j].reverse()
                            if length(candidate, start: start) + 0.5 < length(route, start: start) {
                                route = candidate
                                improved = true
                            }
                        }
                    }
                }
                runStart = runEnd + 1
            }
        }
        return route
    }
}
