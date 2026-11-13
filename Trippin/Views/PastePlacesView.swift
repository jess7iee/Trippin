import SwiftUI
import SwiftData
import UIKit
import MapKit

/// Paste a places list prepared elsewhere (for example, researched in a chat with
/// Claude), check it, and add the places to their days.
struct PastePlacesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var text = ""
    @State private var places: [PlacesImport.Place] = []
    @State private var excluded = Set<UUID>()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(height: places.isEmpty ? 200 : 90)
                        .font(.caption.monospaced())
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste a Trippin places list")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else { return }
                            Task { @MainActor in text = pasted; read() }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        Spacer()
                        Button("Read list", action: read)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Places list")
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else if places.isEmpty {
                        Text("Lists made in a chat with Claude can be pasted here. Each place is added to the day it's for.")
                    } else if !outsideTrip.isEmpty {
                        Text("\(outsideTrip.count) place(s) fall outside the trip's dates and will be skipped.")
                    }
                }

                ForEach(days, id: \.self) { day in
                    Section("Day \(day + 1) · \(trip.date(forDay: day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))") {
                        ForEach(places.filter { trip.dayIndex(for: $0.date) == day }) { place in
                            row(place)
                        }
                    }
                }
            }
            .navigationTitle("Paste places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)", action: add).disabled(selected.isEmpty)
                }
            }
        }
    }

    private func row(_ place: PlacesImport.Place) -> some View {
        let on = !excluded.contains(place.id)
        return Button {
            if on { excluded.insert(place.id) } else { excluded.remove(place.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let time = place.time.flatMap({ Calendar.current.date(from: $0) }) {
                            Text(time.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                        }
                        Text(place.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    }
                    if let local = place.localName, local != place.name { Text(local).font(.subheadline).foregroundStyle(.primary) }
                    if let note = place.note { Text(note).font(.subheadline).foregroundStyle(.secondary) }
                    if let address = place.address { Text(address).font(.caption).foregroundStyle(.tertiary) }
                    if place.latitude == nil {
                        Text("No map location; you can set it after adding.").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "Selected" : "Not selected")
    }

    private var days: [Int] {
        Array(Set(places.compactMap { trip.dayIndex(for: $0.date) })).sorted()
    }

    private var outsideTrip: [PlacesImport.Place] {
        places.filter { trip.dayIndex(for: $0.date) == nil }
    }

    private var selected: [PlacesImport.Place] {
        places.filter { !excluded.contains($0.id) && trip.dayIndex(for: $0.date) != nil }
    }

    private func read() {
        do {
            places = try PlacesImport.parse(text)
            excluded = []
            error = nil
        } catch {
            places = []
            self.error = error.localizedDescription
        }
    }

    private func add() {
        var touched = Set<Int>()
        for place in selected {
            guard let day = trip.dayIndex(for: place.date) else { continue }
            let symbol = Self.symbol(for: place.category ?? "")
            let time = place.time.flatMap { Calendar.current.date(bySettingHour: $0.hour ?? 0, minute: $0.minute ?? 0, second: 0, of: trip.date(forDay: day)) }
            if let lat = place.latitude, let lon = place.longitude {
                // Researched outside Apple Maps, so treat the location as an estimate:
                // maps apps search by name, and the pin can be adjusted.
                TripPlanner.addStop(PlaceSearch.Place(name: place.name, address: place.address,
                                                      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)),
                                    localName: place.localName, note: place.note ?? "", symbol: symbol,
                                    approximate: true, searchQuery: place.searchQuery, day: day, to: trip, context: context)
            } else {
                TripPlanner.addUnlocatedStop(name: place.name, address: place.address, localName: place.localName,
                                             note: place.note ?? "", symbol: symbol, searchQuery: place.searchQuery,
                                             day: day, to: trip, context: context)
            }
            if let time, let stop = trip.stops(onDay: day).last {
                stop.fixedTime = time
                TripPlanner.resort(stop, in: trip)
            }
            touched.insert(day)
        }
        for day in touched { TripPlanner.optimize(day: day, of: trip) }
        try? context.save()
        dismiss()
    }

    static func symbol(for category: String) -> String {
        let c = category.lowercased()
        if c.contains("food") || c.contains("restaurant") || c.contains("cafe") { return "fork.knife" }
        if c.contains("shop") || c.contains("market") { return "bag.fill" }
        if c.contains("night") || c.contains("bar") { return "wineglass.fill" }
        if c.contains("errand") { return "checklist" }
        if c.contains("nature") || c.contains("park") { return "leaf.fill" }
        if c.contains("museum") || c.contains("art") || c.contains("temple") || c.contains("sight") { return "building.columns.fill" }
        return "star.fill"
    }
}
