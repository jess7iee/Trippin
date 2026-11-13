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
    /// What to search for in a maps app: the place's own name, without labels
    /// like "Check in:". For flights and trains, the airport or station.
    var searchName: String
    /// ISO country code when known, e.g. "CN".
    var countryCode: String?
    /// The coordinate is an estimate (or missing): maps apps search by name instead.
    var isApproximate = false

    /// The apps worth offering for this place.
    var mapsApps: [MapsApp] { MapsApp.allCases.filter { $0.isUseful(inCountry: countryCode) } }

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
        localAddress = Self.bestLocalAddress(stop.localAddress, address: stop.address)
        searchName = Self.searchName(title: stop.reservation?.title ?? stop.name,
                                     kind: stop.reservation?.kind, address: stop.address)
        countryCode = stop.countryCode
        isApproximate = stop.approximateLocation || stop.coordinate == nil
        if isApproximate, let query = stop.searchQuery, !query.isEmpty { searchName = query }
    }

    /// The booking's own address when it's already in the local script and fuller
    /// than the geocoder's (which can be as sparse as "云南").
    private static func bestLocalAddress(_ local: String?, address: String?) -> String? {
        if let address, EmailParser.isLocalScript(address), local == nil || address.contains(local!) { return address }
        return local
    }

    private static func searchName(title: String, kind: ReservationKind?, address: String?) -> String {
        if kind?.isJourney == true, let address, !address.isEmpty { return address }
        return title
    }

    init(_ reservation: Reservation) {
        id = reservation.id
        name = reservation.title
        address = reservation.address
        coordinate = reservation.coordinate
        day = 0
        symbol = reservation.kind.symbol
        localName = reservation.localName
        localAddress = Self.bestLocalAddress(reservation.stops.lazy.compactMap(\.localAddress).first, address: reservation.address)
        searchName = Self.searchName(title: reservation.title, kind: reservation.kind, address: reservation.address)
        countryCode = reservation.stops.lazy.compactMap(\.countryCode).first
        isApproximate = reservation.coordinate == nil || reservation.stops.contains(where: \.approximateLocation)
    }

    init(_ place: PlaceSearch.Place, localName: String? = nil, countryCode: String? = nil, hasLocation: Bool = true,
         isApproximate: Bool = false, searchName: String? = nil) {
        id = place.id
        name = place.name
        address = place.address
        coordinate = hasLocation ? place.coordinate : nil
        day = 0
        symbol = "mappin"
        self.searchName = searchName ?? place.name
        self.localName = localName
        self.countryCode = countryCode
        self.isApproximate = isApproximate || !hasLocation
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

extension MapPlace {
    /// The maps app searches for the place by name (e.g. "Fairfield by Marriott
    /// Kunming Xishan", not "Check in: …" or the street address). Amap gets the
    /// local-language name, which it searches best.
    func searchText(for app: MapsApp) -> String {
        if app == .amap || app == .dianping, let local = localName, !local.isEmpty { return local }
        return searchName.isEmpty ? (address ?? name) : searchName
    }

    var hasLocalCard: Bool { localName != nil || localAddress != nil }
}

/// A button that opens a small menu right beside it: Open in Apple Maps,
/// Google Maps or Amap, and the local-language card.
struct OpenInMapsButton<Label: View>: View {
    let place: MapPlace
    @ViewBuilder var label: () -> Label
    @State private var card: MapPlace?

    var body: some View {
        Menu {
            Section(menuTitle) {
                ForEach(place.mapsApps) { app in
                    Button("Open in \(app.name)", systemImage: "map") {
                        app.open(text: place.searchText(for: app), coordinate: place.coordinate, exact: !place.isApproximate)
                    }
                }
            }
            if place.hasLocalCard {
                Button("Show in local language", systemImage: "character.bubble") { card = place }
            }
        } label: {
            label()
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Open \(place.name) in maps")
        .sheet(item: $card) { LocalNameCard(place: $0) }
    }

    private var menuTitle: String {
        [place.searchName, place.localName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Used for pins on a map: the same choices, shown when `place` is set.
private struct OpenInMapsDialog: ViewModifier {
    @Binding var place: MapPlace?
    @State private var card: MapPlace?

    func body(content: Content) -> some View {
        content.confirmationDialog(place?.name ?? "", isPresented: Binding(
            get: { place != nil },
            set: { if !$0 { place = nil } }
        ), titleVisibility: .visible, presenting: place) { place in
            ForEach(place.mapsApps) { app in
                Button("Open in \(app.name)") {
                    app.open(text: place.searchText(for: app), coordinate: place.coordinate, exact: !place.isApproximate)
                }
            }
            if place.hasLocalCard {
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
    /// Attach it to the map whose pins set `place`, so it appears there.
    func openInMapsDialog(place: Binding<MapPlace?>) -> some View {
        modifier(OpenInMapsDialog(place: place))
    }
}
