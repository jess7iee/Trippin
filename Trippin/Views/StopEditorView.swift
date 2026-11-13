import SwiftUI
import SwiftData
import MapKit

/// Change a stop's name, note, time, day or location.
///
/// Stops that come from a reservation take their name, day and time from it,
/// so those fields are edited on the reservation instead.
struct StopEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var stop: Stop
    let trip: Trip
    /// Called to switch to the booking editor for a reservation stop.
    var onEditReservation: (Reservation) -> Void

    @State private var name = ""
    @State private var note = ""
    @State private var day = 0
    @State private var time: Date?
    @State private var newPlace: PlaceSearch.Place?

    init(stop: Stop, trip: Trip, onEditReservation: @escaping (Reservation) -> Void) {
        self.stop = stop
        self.trip = trip
        self.onEditReservation = onEditReservation
        // Seeded once here; onAppear can fire again (e.g. after a menu closes) and would undo edits.
        _name = State(initialValue: stop.name)
        _note = State(initialValue: stop.note)
        _day = State(initialValue: stop.dayIndex)
        _time = State(initialValue: stop.fixedTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if stop.reservation == nil {
                        TextField("Name", text: $name)
                    } else {
                        LabeledContent("Name", value: stop.name)
                    }
                    TextField("Note", text: $note, prompt: Text("e.g. book ahead, cash only, meet Sam here"), axis: .vertical)
                        .lineLimit(1...5)
                }

                if let reservation = stop.reservation {
                    Section {
                        Button {
                            stop.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            onEditReservation(reservation)
                        } label: {
                            Label("Edit \(reservation.kind.label.lowercased()) booking", systemImage: reservation.kind.symbol)
                        }
                    } footer: {
                        Text("This stop comes from your \(reservation.title) booking. Change its day, time or place there.")
                    }
                } else {
                    Section("When") {
                        Picker("Day", selection: $day) {
                            ForEach(0..<trip.dayCount, id: \.self) { index in
                                Text("Day \(index + 1) · \(trip.date(forDay: index).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                                    .tag(index)
                            }
                        }
                        OptionalDatePicker(title: "Time", date: $time, suggested: suggestedTime,
                                           components: .hourAndMinute)
                    }

                    Section {
                        if let coordinate = newPlace?.coordinate ?? stop.coordinate {
                            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                                Marker(newPlace?.name ?? stop.name, coordinate: coordinate)
                            }
                            .id("\(coordinate.latitude),\(coordinate.longitude)")
                            .frame(height: 160)
                            .listRowInsets(EdgeInsets())
                            .allowsHitTesting(false)
                        }
                        if let address = newPlace?.address ?? stop.address ?? stop.localAddress {
                            Text(address).font(.subheadline).foregroundStyle(.secondary)
                        } else if newPlace == nil && stop.coordinate == nil {
                            Text("Location not found").foregroundStyle(.orange)
                        }
                        NavigationLink {
                            RelocateSearchView(initialQuery: name.isEmpty ? stop.name : name,
                                               destination: trip.destination) { place in
                                newPlace = place
                            }
                        } label: {
                            Label(stop.coordinate == nil && newPlace == nil ? "Find on map" : "Change place",
                                  systemImage: "mappin.and.ellipse")
                        }
                    } header: {
                        Text("Place")
                    }
                }

                Section {
                    Button("Remove from itinerary", role: .destructive) {
                        context.delete(stop)
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(stop.reservation == nil && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// 10:00 on the chosen day.
    private var suggestedTime: Date {
        Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: trip.date(forDay: day)) ?? .now
    }

    private func save() {
        stop.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if stop.reservation == nil {
            let typed = name.trimmingCharacters(in: .whitespaces)
            let renamed = typed != stop.name
            // A new place brings its own name unless the user typed one.
            if let newPlace { TripPlanner.relocate(stop, to: newPlace, rename: !renamed) }
            if renamed { stop.name = typed }
            // Keep the time on the stop's own day.
            let timeChanged = time != stop.fixedTime
            stop.fixedTime = time.flatMap { t in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: t)
                return Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0,
                                             of: trip.date(forDay: stop.dayIndex))
            }
            if day != stop.dayIndex {
                TripPlanner.move(stop, toDay: day, of: trip)
            } else if timeChanged {
                TripPlanner.resort(stop, in: trip)
            }
        }
        try? context.save()
        dismiss()
    }
}

/// Search Apple Maps for a stop's new location.
private struct RelocateSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let initialQuery: String
    let destination: String
    var onPick: (PlaceSearch.Place) -> Void

    @State private var query = ""
    @State private var results: [PlaceSearch.Place] = []
    @State private var region: MKCoordinateRegion?
    @State private var searching = false

    var body: some View {
        List(results) { place in
            Button {
                onPick(place)
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
            if searching && results.isEmpty { ProgressView() }
            else if results.isEmpty && !query.isEmpty && !searching { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places")
        .navigationTitle("Change place")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if query.isEmpty { query = initialQuery } }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !query.isEmpty else { return }
            searching = true
            if region == nil { region = await PlaceSearch.region(for: destination) }
            results = await PlaceSearch.search(query, near: region)
            searching = false
        }
    }
}
