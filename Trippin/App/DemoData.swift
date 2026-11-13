#if DEBUG
import Foundation
import SwiftData
import CoreLocation

/// Debug-only sample trip. Launch with `-seedDemo` to load it,
/// and `-openDemoPage N` (-1 = Summary) to jump straight to a page.
enum DemoData {
    static var shouldSeed: Bool { ProcessInfo.processInfo.arguments.contains("-seedDemo") }

    static var openPage: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-openDemoPage"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard shouldSeed, (try? context.fetchCount(FetchDescriptor<Trip>())) == 0 else { return }
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2027, month: 3, day: 6))!
        let trip = Trip(name: "Tokyo spring", destination: "Tokyo, Japan", startDate: start,
                        endDate: cal.date(byAdding: .day, value: 3, to: start)!)
        context.insert(trip)

        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: start)!
        }

        let hotel = Reservation(from: ParsedReservation(kind: .hotel, title: "Park Hyatt Tokyo", confirmationCode: "88231045",
                                                        start: at(0, 15), end: at(3, 12),
                                                        address: "3-7-1-2 Nishi Shinjuku, Shinjuku, Tokyo", localName: "パーク ハイアット 東京"), rawText: "")
        hotel.latitude = 35.6856; hotel.longitude = 139.6907
        let dinner = Reservation(from: ParsedReservation(kind: .restaurant, title: "Sushi Saito", confirmationCode: "RS2291A",
                                                         start: at(1, 19, 30), address: "Minato, Tokyo", localName: "鮨 さいとう"), rawText: "")
        dinner.latitude = 35.6672; dinner.longitude = 139.7400
        for r in [hotel, dinner] { context.insert(r); r.trip = trip }

        let stops: [(String, Double, Double, Int, Date?, String, Reservation?, String)] = [
            ("Check in: Park Hyatt Tokyo", 35.6856, 139.6907, 0, at(0, 15), "bed.double.fill", hotel, "パーク ハイアット 東京"),
            ("Omoide Yokocho", 35.6930, 139.6995, 0, nil, "fork.knife", nil, "思い出横丁"),
            ("Senso-ji", 35.7148, 139.7967, 1, nil, "building.columns.fill", nil, "浅草寺"),
            ("Meiji Jingu", 35.6764, 139.6993, 1, nil, "leaf.fill", nil, "明治神宮"),
            ("Tokyo Skytree", 35.7101, 139.8107, 1, nil, "star.fill", nil, "東京スカイツリー"),
            ("Sushi Saito", 35.6672, 139.7400, 1, at(1, 19, 30), "fork.knife", dinner, "鮨 さいとう"),
            ("teamLab Planets", 35.6491, 139.7898, 2, nil, "star.fill", nil, "チームラボプラネッツ TOKYO DMM"),
            ("Shinjuku Station", 35.6896, 139.7006, 3, nil, "tram.fill", nil, "新宿駅"),
            ("Check out: Park Hyatt Tokyo", 35.6856, 139.6907, 3, at(3, 12), "bed.double.fill", hotel, "パーク ハイアット 東京"),
        ]
        for (index, s) in stops.enumerated() {
            let stop = Stop(name: s.0, coordinate: CLLocationCoordinate2D(latitude: s.1, longitude: s.2),
                            dayIndex: s.3, sortOrder: Double(index), fixedTime: s.4, symbol: s.5)
            context.insert(stop)
            stop.trip = trip
            stop.reservation = s.6
            stop.localName = s.7
        }
        for text in ["Best ramen", "Buy a SIM card", "Souvenirs for mom"] {
            let todo = TodoItem(text: text)
            context.insert(todo)
            todo.trip = trip
        }
        try? context.save()
    }
}
#endif
