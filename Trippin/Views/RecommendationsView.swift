import SwiftUI
import SwiftData
import MapKit

/// Turns the trip's to-do list into specific places from Claude, checks each
/// one in Apple Maps, and adds the picks to days, then optimizes those days.
struct RecommendationsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip

    @State private var extra = ""
    @State private var results: [Suggestion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showingSettings = false
    @State private var placeToOpen: MapPlace?

    struct Suggestion: Identifiable {
        var id: String { rec.id }
        var rec: Recommendation
        var place: PlaceSearch.Place?
        var day: Int
        var selected = true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("You want to do") {
                    let todos = trip.todos.filter { !$0.isDone }
                    if todos.isEmpty {
                        Text("Add things to the “Want to do” list on the Summary page.").foregroundStyle(.secondary)
                    }
                    ForEach(todos) { Text("• \($0.text)") }
                    TextField("Anything else? (budget, pace, dietary needs…)", text: $extra, axis: .vertical)
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
                            if s.day == day { SuggestionRow(suggestion: $s, dayCount: trip.dayCount) { placeToOpen = $0 } }
                        }
                    }
                }
            }
            .navigationTitle("Recommendations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedCount)") { addSelected() }
                        .disabled(selectedCount == 0)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .openInMapsDialog(place: $placeToOpen)
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
            extraRequest: extra)
        do {
            let recs = try await ClaudeClient().recommendations(for: context)
            let region = await PlaceSearch.region(for: trip.destination)
            var found: [Suggestion] = []
            for rec in recs {
                let place = await PlaceSearch.first(rec.searchQuery, near: region)
                found.append(Suggestion(rec: rec, place: place, day: rec.suggestedDay - 1, selected: place != nil))
            }
            results = found
            if found.isEmpty { error = "No recommendations came back. Try adding more detail." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addSelected() {
        var touchedDays = Set<Int>()
        for s in results where s.selected {
            guard var place = s.place else { continue }
            place.name = s.rec.name
            TripPlanner.addStop(place, localName: s.rec.localName, note: s.rec.reason, symbol: symbol(for: s.rec.category), day: s.day, to: trip, context: context)
            touchedDays.insert(s.day)
        }
        for day in touchedDays { TripPlanner.optimize(day: day, of: trip) }
        try? context.save()
        dismiss()
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
    var onMap: (MapPlace) -> Void

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
                        Text("Couldn't find this in Apple Maps").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                if let place = suggestion.place {
                    Button { onMap(MapPlace(place)) } label: { Image(systemName: "map") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open in maps")
                }
            }
            Picker("Day", selection: $suggestion.day) {
                ForEach(0..<dayCount, id: \.self) { Text("Day \($0 + 1)").tag($0) }
            }
            .font(.caption)
        }
    }
}
