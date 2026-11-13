import SwiftUI
import MapKit

/// What a flight card shows, read from a flight reservation.
struct FlightInfo {
    var number: String?
    var from: String?
    var to: String?
    var departs: Date?
    var arrives: Date?

    init?(_ reservation: Reservation?) {
        guard let reservation, reservation.kind == .flight else { return nil }
        let route = EmailParser.flightRoute(in: reservation.title)
        number = EmailParser.flightNumber(in: reservation.title)
        from = route?.from
        to = route?.to
        departs = reservation.start
        arrives = reservation.end
        guard from != nil || number != nil else { return nil }
    }

    /// Days between departure and arrival, e.g. 1 for an overnight flight.
    var dayOffset: Int {
        guard let departs, let arrives else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: departs), to: cal.startOfDay(for: arrives)).day ?? 0
    }
}

/// A boarding-pass style summary: SFO ✈ PEK with times and the flight number.
struct FlightCard: View {
    let info: FlightInfo
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            end(code: info.from, time: info.departs, alignment: .leading)
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    dashes
                    Image(systemName: "airplane")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                    dashes
                }
                if let number = info.number {
                    Text(number.replacingOccurrences(of: " ", with: ""))
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            end(code: info.to, time: info.arrives, alignment: .trailing, offset: info.dayOffset)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var dashes: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .foregroundStyle(.tertiary)
            .frame(height: 1.5)
    }

    private func end(code: String?, time: Date?, alignment: HorizontalAlignment, offset: Int = 0) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(code ?? "—")
                .font(.title2.weight(.bold).monospaced())
            if let time {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(alignment == .leading ? tint : .secondary)
                    if offset > 0 {
                        Text("+\(offset)").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                    }
                }
            }
        }
        .fixedSize()
    }

    private var accessibilityText: String {
        var parts = ["Flight"]
        if let number = info.number { parts.append(number) }
        if let from = info.from, let to = info.to { parts.append("from \(from) to \(to)") }
        if let departs = info.departs { parts.append("departs \(departs.formatted(date: .omitted, time: .shortened))") }
        if let arrives = info.arrives {
            parts.append("arrives \(arrives.formatted(date: .omitted, time: .shortened))" + (info.dayOffset > 0 ? " the next day" : ""))
        }
        return parts.joined(separator: ", ")
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// A flight drawn on a map as a curved path between airports.
struct FlightPath: Identifiable {
    var id: UUID
    var from: CLLocationCoordinate2D
    var to: CLLocationCoordinate2D
    var toCode: String?
    var day: Int

    init?(_ reservation: Reservation) {
        guard reservation.kind == .flight,
              let from = reservation.coordinate, let to = reservation.arrivalCoordinate else { return nil }
        id = reservation.id
        self.from = from
        self.to = to
        toCode = EmailParser.flightRoute(in: reservation.title)?.to
        day = reservation.stops.map(\.dayIndex).min() ?? 0
    }
}
