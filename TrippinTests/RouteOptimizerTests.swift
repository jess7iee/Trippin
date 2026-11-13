import Testing
import Foundation

struct RouteOptimizerTests {
    private func item(_ lat: Double, _ lon: Double, at time: Date? = nil) -> RouteOptimizer.Item {
        RouteOptimizer.Item(id: UUID(), point: GeoPoint(latitude: lat, longitude: lon), fixedTime: time)
    }

    @Test func shortensZigZagRoute() {
        // Points along a line, given out of order.
        let a = item(35.00, 139.00), b = item(35.01, 139.00), c = item(35.02, 139.00), d = item(35.03, 139.00)
        let input = [a, c, b, d]
        let order = RouteOptimizer.optimize(input, start: a.point)
        let byID = Dictionary(uniqueKeysWithValues: input.map { ($0.id, $0) })
        let optimized = order.map { byID[$0]! }
        #expect(RouteOptimizer.length(optimized, start: a.point) < RouteOptimizer.length(input, start: a.point))
        #expect(order == [a, b, c, d].map(\.id))
    }

    @Test func keepsFixedStopsInTimeOrder() {
        let now = Date()
        let lunch = item(35.05, 139.0, at: now.addingTimeInterval(3 * 3600))
        let breakfast = item(35.00, 139.0, at: now)
        let flex1 = item(35.01, 139.0)
        let flex2 = item(35.06, 139.0)
        let order = RouteOptimizer.optimize([lunch, flex2, breakfast, flex1])
        let iBreakfast = order.firstIndex(of: breakfast.id)!
        let iLunch = order.firstIndex(of: lunch.id)!
        #expect(iBreakfast < iLunch)
        // The stop near breakfast goes right after it; the one past lunch goes after lunch.
        #expect(order.firstIndex(of: flex1.id)! == iBreakfast + 1)
        #expect(order.firstIndex(of: flex2.id)! > iLunch)
    }

    @Test func keepsStopsWithoutLocation() {
        let unknown = RouteOptimizer.Item(id: UUID(), point: nil, fixedTime: nil)
        let order = RouteOptimizer.optimize([item(35, 139), unknown, item(35.1, 139)])
        #expect(order.count == 3)
        #expect(order.last == unknown.id)
    }
}
