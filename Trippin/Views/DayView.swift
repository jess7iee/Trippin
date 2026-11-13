import SwiftUI
import SwiftData
import MapKit

struct DayView: View {
    @Environment(\.modelContext) private var context
    @Bindable var trip: Trip
    let day: Int

    @State private var placeToOpen: MapPlace?
    @State private var showingSearch = false
    @State private var routes: [MKRoute] = []
    @State private var transport: Transport = .walking
    @State private var optimizeMessage: String?
    @State private var editing: EditTarget?

    enum Transport: String, CaseIterable, Identifiable {
        case walking = "Walk", driving = "Drive"
        var id: String { rawValue }
        var mkType: MKDirectionsTransportType { self == .walking ? .walking : .automobile }
    }

    private var stops: [Stop] { trip.stops(onDay: day) }

    var body: some View {
        List {
            Section {
                TripMapView(places: numberedPlaces, showRoute: true, routes: routes, flights: flights, selection: $placeToOpen)
                    .frame(height: 280)
                    .openInMapsDialog(place: $placeToOpen)
                    .listRowInsets(EdgeInsets())
                HStack {
                    Picker("Travel", selection: $transport) {
                        ForEach(Transport.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    Spacer()
                    if let total = totalTravel {
                        Text(total).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if stops.isEmpty {
                    Text("Nothing planned yet. Add places, or get recommendations from the Summary page.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(alignment: .leading, spacing: 6) {
                        StopRow(stop: stop, number: index + 1)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = .stop(stop) }
                        .accessibilityAction(named: "Edit") { editing = .stop(stop) }
                        if index < routes.count, index + 1 < stops.count, let leg = legText(index) {
                            Label(leg, systemImage: transport == .walking ? "figure.walk" : "car")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 40)
                        }
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)

                Button { showingSearch = true } label: { Label("Add a place", systemImage: "plus") }
            } header: {
                HStack {
                    Text(trip.date(forDay: day).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    Spacer()
                    EditButton().font(.caption).textCase(nil)
                }
            }

            if stops.count > 2 {
                Section {
                    Button(action: optimize) {
                        Label("Optimize route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                } footer: {
                    Text(optimizeMessage ?? "Reorders stops to cut travel. Bookings with a set time stay in time order.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingSearch) {
            PlaceSearchView(trip: trip, day: day)
        }
        .sheet(item: $editing) { target in
            switch target {
            case .stop(let stop):
                StopEditorView(stop: stop, trip: trip) { editing = .reservation($0) }
            case .reservation(let reservation):
                ReservationEditorView(reservation: reservation)
            }
        }
        .task(id: routeKey) { await loadRoutes() }
        #if DEBUG
        .onAppear {
            if DemoData.openPage == day, let n = DemoData.openEditor, stops.indices.contains(n - 1) {
                editing = .stop(stops[n - 1])
            }
        }
        #endif
    }

    private var flights: [FlightPath] {
        var seen = Set<UUID>()
        return stops.compactMap(\.reservation).filter { seen.insert($0.id).inserted }.compactMap(FlightPath.init)
    }

    private var numberedPlaces: [MapPlace] {
        stops.enumerated().map { MapPlace(stop: $1, number: $0 + 1) }.filter { $0.coordinate != nil }
    }

    // MARK: Routes

    /// Changes whenever the order, locations or travel mode change.
    private var routeKey: String {
        stops.map { "\($0.id)\($0.latitude ?? 0)\($0.longitude ?? 0)\($0.arrivalCoordinate?.latitude ?? 0)" }.joined() + transport.rawValue
    }

    private func loadRoutes() async {
        // After a flight or train, the next leg starts where it arrives.
        let located = stops.compactMap { stop in stop.coordinate.map { (start: $0, end: stop.arrivalCoordinate ?? $0) } }
        guard located.count > 1 else { routes = []; return }
        var result: [MKRoute] = []
        for (from, next) in zip(located, located.dropFirst()) {
            let (a, b) = (from.end, next.start)
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            request.transportType = transport.mkType
            guard let route = try? await MKDirections(request: request).calculate().routes.first else {
                routes = []
                return
            }
            if Task.isCancelled { return }
            result.append(route)
        }
        routes = result
    }

    /// Travel time to the next stop. Only accurate when every stop has a location.
    private func legText(_ index: Int) -> String? {
        guard stops.allSatisfy({ $0.coordinate != nil }) else { return nil }
        let route = routes[index]
        return "\(duration(route.expectedTravelTime)) · \(distance(route.distance)) to next stop"
    }

    private var totalTravel: String? {
        guard !routes.isEmpty else { return nil }
        let time = routes.reduce(0) { $0 + $1.expectedTravelTime }
        let meters = routes.reduce(0) { $0 + $1.distance }
        return "\(duration(time)) · \(distance(meters))"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    // MARK: Editing

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = stops
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, stop) in reordered.enumerated() { stop.sortOrder = Double(index + 1) }
        optimizeMessage = nil
    }

    private func delete(_ offsets: IndexSet) {
        let current = stops
        for index in offsets { context.delete(current[index]) }
    }

    private func optimize() {
        let saved = TripPlanner.optimize(day: day, of: trip)
        optimizeMessage = saved > 50
            ? "Saved about \(distance(saved)) of travel."
            : "This order is already about as short as it gets."
    }
}

/// What the edit sheet is showing. Switching from a stop to its booking swaps the sheet.
enum EditTarget: Identifiable {
    case stop(Stop), reservation(Reservation)

    var id: UUID {
        switch self {
        case .stop(let stop): stop.id
        case .reservation(let reservation): reservation.id
        }
    }
}

private struct StopRow: View {
    let stop: Stop
    let number: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 26, height: 26)
                .background(DayColor.color(stop.dayIndex), in: Circle())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                if let flight = FlightInfo(stop.reservation) {
                    FlightCard(info: flight, tint: DayColor.color(stop.dayIndex))
                        .padding(.trailing, 4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: stop.symbol).foregroundStyle(.secondary).font(.caption)
                        Text(stop.name).font(.body.weight(.medium))
                    }
                    if let local = stop.distinctLocalName {
                        Text(local)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .accessibilityLabel("Local name: \(local)")
                    }
                    if let time = stop.fixedTime {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if !stop.note.isEmpty {
                    Text(stop.note).font(.subheadline).foregroundStyle(.secondary)
                }
                if let address = stop.address ?? stop.localAddress {
                    Text(address).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                        .textSelection(.enabled)
                } else if stop.coordinate == nil {
                    Text("Location not found").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            OpenInMapsButton(place: MapPlace(stop: stop, number: number)) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Search Apple Maps and add a result to a day.
struct PlaceSearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let day: Int

    @State private var query = ""
    @State private var results: [PlaceSearch.Place] = []
    @State private var region: MKCoordinateRegion?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List(results) { place in
                Button {
                    TripPlanner.addStop(place, day: day, to: trip, context: context)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(place.name).foregroundStyle(.primary)
                        if let address = place.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if searching { ProgressView() }
                else if results.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places in \(trip.destination)")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, !query.isEmpty else { return }
                searching = true
                if region == nil { region = await PlaceSearch.region(for: trip.destination) }
                results = await PlaceSearch.search(query, near: region)
                searching = false
            }
            .navigationTitle("Add to Day \(day + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
