import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var showingNewTrip = false
    @State private var showingSettings = false
    @State private var path: [Trip] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "suitcase.rolling")
                    } description: {
                        Text("Create a trip, then paste or share your booking emails to fill in each day.")
                    } actions: {
                        Button("New trip") { showingNewTrip = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(trips) { trip in
                            NavigationLink(value: trip) {
                                TripRow(trip: trip)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(trips[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewTrip = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New trip")
                }
            }
            .sheet(isPresented: $showingNewTrip) { TripEditorView(trip: nil) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            #if DEBUG
            .task {
                DemoData.seedIfNeeded(context)
                if DemoData.openPage != nil, let first = trips.first { path = [first] }
            }
            #endif
        }
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.name).font(.headline)
            HStack(spacing: 6) {
                if !trip.destination.isEmpty {
                    Label(trip.destination, systemImage: "mappin.and.ellipse")
                }
                Text("\(trip.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(trip.endDate.formatted(.dateTime.month(.abbreviated).day().year()))")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("\(trip.dayCount) days · \(trip.reservations.count) reservations")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// Create or edit a trip's name, destination and dates.
struct TripEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let trip: Trip?

    @State private var name = ""
    @State private var destination = ""
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now))!

    var body: some View {
        NavigationStack {
            Form {
                TextField("Trip name", text: $name)
                TextField("Destination (city or country)", text: $destination)
                DatePicker("Starts", selection: $start, displayedComponents: .date)
                DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
            }
            .navigationTitle(trip == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && destination.isEmpty)
                }
            }
            .onAppear {
                guard let trip else { return }
                name = trip.name
                destination = trip.destination
                start = trip.startDate
                end = trip.endDate
            }
        }
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? destination : name
        if let trip {
            trip.name = title
            trip.destination = destination
            trip.startDate = Calendar.current.startOfDay(for: start)
            trip.endDate = Calendar.current.startOfDay(for: max(start, end))
        } else {
            context.insert(Trip(name: title, destination: destination, startDate: start, endDate: end))
        }
        try? context.save()
        dismiss()
    }
}
