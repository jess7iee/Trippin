import SwiftUI
import SwiftData

// Read-only pages shown when a stop or reservation is tapped. Editing is behind
// the Edit button at the top right.

/// What an Edit button is showing. Switching from a stop to its booking swaps the sheet.
enum EditTarget: Identifiable {
    case stop(Stop), reservation(Reservation)

    var id: UUID {
        switch self {
        case .stop(let stop): stop.id
        case .reservation(let reservation): reservation.id
        }
    }
}

// MARK: - Stop

struct StopDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let stop: Stop
    let trip: Trip
    @State private var editing: EditTarget?

    var body: some View {
        NavigationStack {
            // A booking edit rebuilds its stops, so this one may be gone when the editor closes.
            if stop.modelContext == nil || stop.isDeleted {
                Color.clear.onAppear { dismiss() }
            } else {
                content
            }
        }
    }

    private var content: some View {
        List {
            Section {
                DetailHeader(symbol: stop.symbol, title: stop.reservation.flatMap { FlightInfo($0) } == nil ? stop.name : nil,
                             localName: stop.distinctLocalName, flight: FlightInfo(stop.reservation),
                             tint: DayColor.color(stop.dayIndex))
            }

            Section("When") {
                LabeledContent("Day \(stop.dayIndex + 1)",
                               value: trip.date(forDay: stop.dayIndex).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                if let time = stop.fixedTime {
                    LabeledContent("Time", value: time.formatted(date: .omitted, time: .shortened))
                }
            }

            if !stop.note.isEmpty {
                Section("Note") { Text(stop.note).textSelection(.enabled) }
            }

            PlaceSection(place: MapPlace(stop: stop, number: nil), flights: stop.reservation.flatMap(FlightPath.init).map { [$0] } ?? [],
                         address: stop.address, localAddress: stop.localAddress)

            if let reservation = stop.reservation {
                Section("Booking") {
                    NavigationLink {
                        ReservationDetailView(reservation: reservation, isRoot: false)
                    } label: {
                        Label(reservation.title, systemImage: reservation.kind.symbol)
                    }
                }
            }
        }
        .navigationTitle("Stop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = .stop(stop) } }
        }
        .sheet(item: $editing) { target in
            switch target {
            case .stop(let stop):
                StopEditorView(stop: stop, trip: trip) { editing = .reservation($0) }
            case .reservation(let reservation):
                ReservationEditorView(reservation: reservation)
            }
        }
    }
}

// MARK: - Reservation

struct ReservationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let reservation: Reservation
    /// False when pushed from a stop's page, which already has a Done button.
    var isRoot = true
    @State private var editing = false

    var body: some View {
        if isRoot {
            NavigationStack { guarded }
        } else {
            guarded
        }
    }

    @ViewBuilder private var guarded: some View {
        if reservation.modelContext == nil || reservation.isDeleted {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
        let flight = FlightInfo(reservation)
        return List {
            Section {
                DetailHeader(symbol: reservation.kind.symbol, title: flight == nil ? reservation.title : nil,
                             localName: reservation.localName.flatMap { $0 == reservation.title ? nil : $0 },
                             flight: flight, tint: .accentColor)
            }

            Section("Details") {
                if let code = reservation.confirmationCode {
                    LabeledContent("Confirmation") {
                        Text(code).monospaced().textSelection(.enabled)
                    }
                }
                if let start = reservation.start {
                    LabeledContent(reservation.kind.startLabel, value: start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                }
                if let end = reservation.end {
                    LabeledContent(reservation.kind.endLabel, value: end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                }
                if reservation.kind.isJourney, let arrival = reservation.arrivalAddress {
                    LabeledContent("Arrives at", value: arrival)
                }
            }

            PlaceSection(place: MapPlace(reservation), flights: FlightPath(reservation).map { [$0] } ?? [],
                         address: reservation.address, localAddress: reservation.stops.lazy.compactMap(\.localAddress).first)

            if !reservation.stops.isEmpty {
                Section("On your itinerary") {
                    ForEach(reservation.stops.sorted { ($0.dayIndex, $0.sortOrder) < ($1.dayIndex, $1.sortOrder) }) { stop in
                        LabeledContent(stop.name, value: "Day \(stop.dayIndex + 1)")
                    }
                }
            }

            if !reservation.rawText.isEmpty {
                Section {
                    DisclosureGroup("Original email") {
                        Text(reservation.rawText).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(reservation.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) { ReservationEditorView(reservation: reservation) }
    }
}

// MARK: - Shared pieces

/// Icon and big title, or a flight card for flights, plus the local name.
private struct DetailHeader: View {
    let symbol: String
    let title: String?
    let localName: String?
    let flight: FlightInfo?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let flight {
                FlightCard(info: flight, tint: tint)
            }
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(title).font(.title2.weight(.semibold))
                }
            }
            if let localName {
                Text(localName).font(.title3).textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A small map, the address in English and the local language, and Open in Maps.
private struct PlaceSection: View {
    let place: MapPlace
    let flights: [FlightPath]
    let address: String?
    let localAddress: String?

    var body: some View {
        Section("Place") {
            if place.coordinate != nil {
                TripMapView(places: [place], showRoute: false, flights: flights, selection: .constant(nil))
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                    .allowsHitTesting(false)
            }
            if let address {
                Text(address).textSelection(.enabled)
            }
            // Skip a local address that's only part of the full one (e.g. just "云南").
            if let localAddress, !(address?.contains(localAddress) ?? false) {
                Text(localAddress).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if address == nil, localAddress == nil, place.coordinate == nil {
                Text("Location not found").foregroundStyle(.orange)
            }
            if place.coordinate != nil || address != nil {
                OpenInMapsButton(place: place) {
                    Label("Open in Maps", systemImage: "map")
                }
            }
        }
    }
}
