import SwiftUI
import UIKit
import MapKit

/// A place to show on a map or open in a maps app.
struct MapPlace: Identifiable, Equatable {
    var id: UUID
    var name: String
    var address: String?
    var coordinate: CLLocationCoordinate2D?
    var day: Int
    var symbol: String
    var number: Int?
    var localName: String?
    var localAddress: String?

    static func == (a: MapPlace, b: MapPlace) -> Bool { a.id == b.id && a.number == b.number }

    init?(_ stop: Stop) {
        guard stop.coordinate != nil else { return nil }
        self.init(stop: stop, number: nil)
    }

    init(stop: Stop, number: Int?) {
        id = stop.id
        name = stop.name
        address = stop.address
        coordinate = stop.coordinate
        day = stop.dayIndex
        symbol = stop.symbol
        self.number = number
        localName = stop.distinctLocalName
        localAddress = stop.localAddress
    }

    init(_ reservation: Reservation) {
        id = reservation.id
        name = reservation.title
        address = reservation.address
        coordinate = reservation.coordinate
        day = 0
        symbol = reservation.kind.symbol
        localName = reservation.localName
        localAddress = reservation.stops.lazy.compactMap(\.localAddress).first
    }

    init(_ place: PlaceSearch.Place) {
        id = place.id
        name = place.name
        address = place.address
        coordinate = place.coordinate
        day = 0
        symbol = "mappin"
    }
}

enum DayColor {
    static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo, .brown, .mint]
    static func color(_ day: Int) -> Color { palette[((day % palette.count) + palette.count) % palette.count] }
}

/// Map with numbered pins and, optionally, the route between them.
struct TripMapView: View {
    var places: [MapPlace]
    var showRoute: Bool
    var routes: [MKRoute] = []
    var flights: [FlightPath] = []
    @Binding var selection: MapPlace?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(flights) { flight in
                MapPolyline(coordinates: [flight.from, flight.to], contourStyle: .geodesic)
                    .stroke(DayColor.color(flight.day).opacity(0.85),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                // Below the point, so it doesn't cover a departure pin (which sits above) at the same airport.
                Annotation(flight.toCode ?? "Arrival", coordinate: flight.to, anchor: .top) {
                    arrivalPin(flight)
                }
                .annotationTitles(.hidden)
            }
            ForEach(places) { place in
                if let coordinate = place.coordinate {
                    Annotation(place.name, coordinate: coordinate, anchor: .bottom) {
                        Button { selection = place } label: { pin(place) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(place.name), open in maps")
                    }
                    // A flight's long title runs off the map; its path and arrival badge say enough.
                    .annotationTitles(place.symbol == ReservationKind.flight.symbol ? .hidden : .automatic)
                }
            }
            if showRoute {
                if routes.isEmpty {
                    let coordinates = places.compactMap(\.coordinate)
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.secondary, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    }
                } else {
                    ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                        MapPolyline(route).stroke(Color.accentColor, lineWidth: 5)
                    }
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear { position = framing }
        .onChange(of: places.map(\.id) + flights.map(\.id)) { _, _ in
            withAnimation { position = framing }
        }
        .overlay {
            if places.isEmpty {
                Text("Places you add will show here")
                    .font(.footnote)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    /// A lone place gets a neighbourhood-sized view instead of the closest zoom,
    /// which for an airport shows nothing but a roof.
    private var framing: MapCameraPosition {
        let coordinates = places.compactMap(\.coordinate)
        if flights.isEmpty, coordinates.count == 1, let only = coordinates.first {
            return .region(MKCoordinateRegion(center: only, latitudinalMeters: 6000, longitudinalMeters: 6000))
        }
        return .automatic
    }

    private func arrivalPin(_ flight: FlightPath) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "airplane.arrival")
            if let code = flight.toCode { Text(code).monospaced() }
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(DayColor.color(flight.day), in: Capsule())
        .foregroundStyle(.white)
        .shadow(radius: 1.5)
        .accessibilityLabel("Arrival \(flight.toCode ?? "")")
    }

    private func pin(_ place: MapPlace) -> some View {
        let color = DayColor.color(place.day)
        return ZStack {
            Circle().fill(color).frame(width: 30, height: 30)
                .shadow(radius: 2)
            if let number = place.number {
                Text("\(number)").font(.caption.bold()).foregroundStyle(.white)
            } else {
                Image(systemName: place.symbol).font(.caption.bold()).foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Open in Apple Maps / Google Maps / Amap

private struct OpenInMapsDialog: ViewModifier {
    @Binding var place: MapPlace?
    @State private var card: MapPlace?

    func body(content: Content) -> some View {
        content.confirmationDialog(place?.name ?? "", isPresented: Binding(
            get: { place != nil },
            set: { if !$0 { place = nil } }
        ), titleVisibility: .visible, presenting: place) { place in
            ForEach(MapsApp.allCases) { app in
                Button("Open in \(app.name)") {
                    app.open(name: searchName(place, for: app), coordinate: place.coordinate, address: place.address)
                }
            }
            ForEach(MapsApp.allCases) { app in
                Button("Directions in \(app.name)") {
                    app.open(name: searchName(place, for: app), coordinate: place.coordinate, address: place.address, directions: true)
                }
            }
            if place.localName != nil || place.localAddress != nil {
                Button("Show in local language") { card = place }
            }
            Button("Cancel", role: .cancel) {}
        } message: { place in
            if let local = place.localName {
                Text([local, place.address].compactMap { $0 }.joined(separator: "\n"))
            } else if let address = place.address {
                Text(address)
            }
        }
        .sheet(item: $card) { LocalNameCard(place: $0) }
    }

    /// Amap searches best with the local (Chinese) name.
    private func searchName(_ place: MapPlace, for app: MapsApp) -> String {
        app == .amap ? (place.localName ?? place.name) : place.name
    }
}

/// Big, clear local name and address to show a taxi driver, station staff or a host.
struct LocalNameCard: View {
    @Environment(\.dismiss) private var dismiss
    let place: MapPlace
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let local = place.localName {
                        Text(local)
                            .font(.system(size: 44, weight: .bold))
                            .minimumScaleFactor(0.5)
                            .textSelection(.enabled)
                    }
                    if let address = place.localAddress {
                        Text(address)
                            .font(.title2)
                            .textSelection(.enabled)
                    }
                    Divider()
                    Text(place.name).font(.headline).foregroundStyle(.secondary)
                    if let address = place.address {
                        Text(address).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Show this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        UIPasteboard.general.string = [place.localName, place.localAddress].compactMap { $0 }.joined(separator: "\n")
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }
}

extension View {
    /// Shows the Apple Maps / Google Maps / Amap picker when `place` is set.
    func openInMapsDialog(place: Binding<MapPlace?>) -> some View {
        modifier(OpenInMapsDialog(place: place))
    }
}
