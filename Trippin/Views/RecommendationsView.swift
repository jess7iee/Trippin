import SwiftUI
import SwiftData
import MapKit

/// Turns the trip's to-do list into specific places from Claude, checks each
/// one in Apple Maps, and adds the picks to days, then optimizes those days.
struct RecommendationsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip
    /// Zero-based day to plan for only, or nil for the whole trip.
    var focusDay: Int? = nil

    @State private var extra = ""
    @State private var results: [Suggestion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showingSettings = false

    struct Suggestion: Identifiable {
        var id: String { rec.id }
        var rec: Recommendation
        var place: PlaceSearch.Place?
        var day: Int
        var selected = true
        /// True when Apple Maps didn't know the place and Claude's location is used.
        var approximate = false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let todos = trip.todos.filter { !$0.isDone }
                    if todos.isEmpty && focusDay == nil {
                        Text("Add things to the “Want to do” list on the Summary page.").foregroundStyle(.secondary)
                    }
                    ForEach(todos) { Text("• \($0.text)") }
                    TextField(focusDay == nil ? "Anything else? (budget, pace, dietary needs…)"
                                              : "What do you feel like? (lunch nearby, a museum, a rainy-day plan…)",
                              text: $extra, axis: .vertical)
                } header: {
                    Text("You want to do")
                } footer: {
                    if focusDay != nil { Text("Suggestions stay close to what's already planned for this day.") }
                }

                Section {
                    if !KeychainStore.hasAPIKey {
                        Button("Add a Claude API key in Settings") { showingSettings = true }
                    } else {
                        Button { Task { await load() } } label: {
                            HStack {
                                Label(results.isEmpty ? "Get recommendations" : "Try again", systemImage: "sparkles")
                                if loading { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(loading)
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else if loading { Text("Asking Claude and checking each place in Apple Maps. This can take up to a minute.") }
                }

                ForEach(groupedDays, id: \.self) { day in
                    Section("Day \(day + 1) · \(trip.date(forDay: day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))") {
                        ForEach($results) { $s in
                            if s.day == day {
                                SuggestionRow(suggestion: $s, dayCount: trip.dayCount,
                                              countryCode: trip.stops(onDay: day).lazy.compactMap(\.countryCode).first
                                                ?? trip.stops.lazy.compactMap(\.countryCode).first)
                            }
                        }
                    }
                }
            }
            .navigationTitle(focusDay.map { "Ideas for Day \($0 + 1)" } ?? "Recommendations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedCount)") { addSelected() }
                        .disabled(selectedCount == 0)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private var groupedDays: [Int] {
        Array(Set(results.map(\.day))).sorted()
    }

    private var selectedCount: Int {
        results.filter { $0.selected && $0.place != nil }.count
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        let dayPlans = (0..<trip.dayCount).compactMap { day -> String? in
            let stops = trip.stops(onDay: day)
            guard !stops.isEmpty else { return nil }
            let list = stops.map { stop in
                [stop.fixedTime?.formatted(date: .omitted, time: .shortened), stop.name, stop.address.map { "(\($0))" }]
                    .compactMap { $0 }.joined(separator: " ")
            }
            return "Day \(day + 1): " + list.joined(separator: "; ")
        }
        let context = ClaudeClient.TripContext(
            destination: trip.destination.isEmpty ? trip.name : trip.destination,
            startDate: trip.startDate,
            dayCount: trip.dayCount,
            dayPlans: dayPlans,
            todos: trip.todos.filter { !$0.isDone }.map(\.text),
            extraRequest: extra,
            focusDay: focusDay.map { $0 + 1 })
        do {
            let recs = try await ClaudeClient().recommendations(for: context)
            let destinationRegion = await PlaceSearch.region(for: trip.destination)
            var found: [Suggestion] = []
            for rec in recs {
                let day = rec.suggestedDay - 1
                // Search near that day's own stops (e.g. your Beijing hotel), not the trip's headline city.
                let region = Self.region(near: day, in: trip) ?? destinationRegion
                var place = await PlaceSearch.best([rec.localName, rec.searchQuery, rec.name], near: region)
                var approximate = false
                if place == nil, let fallback = Self.claudeLocation(rec, near: region) {
                    place = fallback
                    approximate = true
                }
                found.append(Suggestion(rec: rec, place: place, day: day, selected: place != nil, approximate: approximate))
            }
            results = found
            if found.isEmpty {
                error = focusDay == nil && trip.todos.allSatisfy(\.isDone)
                    ? "Everything on your list is planned. Add more to “Want to do”, or describe what you'd like above."
                    : "No recommendations came back. Try adding more detail."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addSelected() {
        var touchedDays = Set<Int>()
        for s in results where s.selected {
            guard var place = s.place else { continue }
            place.name = s.rec.name
            let note = s.approximate ? s.rec.reason + " (Approximate location; check it in Amap.)" : s.rec.reason
            TripPlanner.addStop(place, localName: s.rec.localName, note: note, symbol: symbol(for: s.rec.category), day: s.day, to: trip, context: context)
            touchedDays.insert(s.day)
        }
        for day in touchedDays { TripPlanner.optimize(day: day, of: trip) }
        tickOffTodos()
        try? context.save()
        dismiss()
    }

    /// A region around the day's located stops, or the nearest day that has some.
    static func region(near day: Int, in trip: Trip) -> MKCoordinateRegion? {
        let offsets = [0] + (1..<max(trip.dayCount, 1)).flatMap { [-$0, $0] }
        for offset in offsets {
            let d = day + offset
            guard d >= 0, d < trip.dayCount else { continue }
            let points = trip.stops(onDay: d).flatMap { [$0.coordinate, $0.arrivalCoordinate].compactMap { $0 } }
            guard !points.isEmpty else { continue }
            // After a flight, the day's later stops are where the traveler is.
            let last = points.suffix(3)
            let center = CLLocationCoordinate2D(latitude: last.map(\.latitude).reduce(0, +) / Double(last.count),
                                                longitude: last.map(\.longitude).reduce(0, +) / Double(last.count))
            return MKCoordinateRegion(center: center, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }
        return nil
    }

    /// Claude's own location for a place, if it gave one near where the day is.
    static func claudeLocation(_ rec: Recommendation, near region: MKCoordinateRegion?) -> PlaceSearch.Place? {
        guard rec.latitude != 0 || rec.longitude != 0,
              abs(rec.latitude) <= 90, abs(rec.longitude) <= 180 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: rec.latitude, longitude: rec.longitude)
        if let region {
            let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            guard center.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 150_000 else { return nil }
        }
        return PlaceSearch.Place(name: rec.name, address: rec.address.isEmpty ? nil : rec.address, coordinate: coordinate)
    }

    /// Crosses off each to-do that got at least one place, so the next search skips it.
    private func tickOffTodos() {
        let added = results.filter { $0.selected && $0.place != nil }
        for todo in trip.todos where !todo.isDone {
            let names = added.filter { TodoMatch.answers($0.rec.forTodo, todo: todo.text) }.map(\.rec.name)
            guard !names.isEmpty else { continue }
            todo.isDone = true
            todo.plannedAs = names.joined(separator: ", ")
        }
    }

    private func symbol(for category: String) -> String {
        let c = category.lowercased()
        if c.contains("food") || c.contains("restaurant") || c.contains("cafe") { return "fork.knife" }
        if c.contains("shop") { return "bag.fill" }
        if c.contains("night") || c.contains("bar") { return "wineglass.fill" }
        if c.contains("errand") { return "checklist" }
        if c.contains("nature") || c.contains("park") { return "leaf.fill" }
        if c.contains("museum") || c.contains("art") { return "building.columns.fill" }
        return "star.fill"
    }
}

private struct SuggestionRow: View {
    @Binding var suggestion: RecommendationsView.Suggestion
    let dayCount: Int
    let countryCode: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button { suggestion.selected.toggle() } label: {
                    Image(systemName: suggestion.selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(suggestion.selected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(suggestion.place == nil)
                .accessibilityLabel(suggestion.selected ? "Selected" : "Not selected")

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.rec.name).font(.body.weight(.medium))
                    if !suggestion.rec.localName.isEmpty, suggestion.rec.localName != suggestion.rec.name {
                        Text(suggestion.rec.localName).font(.subheadline).textSelection(.enabled)
                    }
                    Text(suggestion.rec.reason).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text("For: \(suggestion.rec.forTodo)")
                        Text("~\(suggestion.rec.durationMinutes) min")
                    }
                    .font(.caption).foregroundStyle(.tertiary)
                    if suggestion.place == nil {
                        Text("Couldn't find where this is").font(.caption).foregroundStyle(.orange)
                    } else if suggestion.approximate {
                        Label("Apple Maps doesn't list this place; using Claude's approximate location", systemImage: "mappin.slash")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if !suggestion.rec.address.isEmpty {
                        Text(suggestion.rec.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Spacer()
                if let place = suggestion.place {
                    OpenInMapsButton(place: MapPlace(place, localName: suggestion.rec.localName.isEmpty ? nil : suggestion.rec.localName,
                                                     countryCode: countryCode)) { Image(systemName: "map") }
                        .buttonStyle(.borderless)
                }
            }
            Picker("Day", selection: $suggestion.day) {
                ForEach(0..<dayCount, id: \.self) { Text("Day \($0 + 1)").tag($0) }
            }
            .font(.caption)
        }
    }
}
