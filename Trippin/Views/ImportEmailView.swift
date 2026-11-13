import SwiftUI
import SwiftData
import UIKit

/// Paste (or receive from the share sheet) a confirmation email, review what
/// was found, and save it to a trip.
struct ImportEmailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    /// nil when the email came from the share sheet and the user picks the trip.
    let trip: Trip?
    let initialText: String

    @State private var text = ""
    @State private var drafts: [ParsedReservation] = []
    @State private var selectedTripID: UUID?
    @State private var parsing = false
    @State private var saving = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                if trip == nil {
                    Section("Trip") {
                        if trips.isEmpty {
                            Text("Create a trip first, then share the email again.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Add to", selection: $selectedTripID) {
                                ForEach(trips) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                    }
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: drafts.isEmpty ? 220 : 100)
                        .font(.callout)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste a flight, hotel, restaurant or ticket confirmation email")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Button { if let s = UIPasteboard.general.string { text = s } } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        Spacer()
                        Button { Task { await parse() } } label: {
                            if parsing { ProgressView() } else { Label("Find reservations", systemImage: "wand.and.stars") }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsing)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Email")
                } footer: {
                    if let note { Text(note) }
                }

                ForEach($drafts) { $draft in
                    Section {
                        Picker("Type", selection: $draft.kind) {
                            ForEach(ReservationKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                        TextField("Title", text: $draft.title)
                        TextField("Confirmation code", text: Binding(
                            get: { draft.confirmationCode ?? "" },
                            set: { draft.confirmationCode = $0.isEmpty ? nil : $0 }))
                        OptionalDatePicker(title: startLabel(draft.kind), date: $draft.start)
                        OptionalDatePicker(title: endLabel(draft.kind), date: $draft.end)
                        TextField("Address or place", text: Binding(
                            get: { draft.address ?? "" },
                            set: { draft.address = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        Button("Remove", role: .destructive) { drafts.removeAll { $0.id == draft.id } }
                    } header: {
                        Text(draft.kind.label)
                    }
                }
            }
            .navigationTitle("Add reservation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Save") { Task { await save() } }
                            .disabled(drafts.isEmpty || targetTrip == nil)
                    }
                }
            }
            .task {
                selectedTripID = trip?.id ?? bestTripGuess()?.id
                guard text.isEmpty, !initialText.isEmpty else { return }
                text = initialText
                await parse()
            }
        }
    }

    private var targetTrip: Trip? {
        trip ?? trips.first { $0.id == selectedTripID }
    }

    /// The trip that is happening now or next.
    private func bestTripGuess() -> Trip? {
        let today = Calendar.current.startOfDay(for: .now)
        return trips.first { $0.endDate >= today } ?? trips.last
    }

    private func parse() async {
        parsing = true
        defer { parsing = false }
        note = nil
        if KeychainStore.hasAPIKey {
            do {
                let found = try await ClaudeClient().extractReservations(from: text)
                if !found.isEmpty {
                    drafts = found
                    note = "Found \(found.count) with Claude. Check the details before saving."
                    return
                }
            } catch {
                note = "\(error.localizedDescription) Used the on-device reader instead."
            }
        }
        let local = EmailParser.parse(text)
        drafts = [local]
        if note == nil {
            note = KeychainStore.hasAPIKey
                ? "Check the details before saving."
                : "Read on this device. Add a Claude API key in Settings for better results with multi-flight emails."
        }
        // When the email came from the share sheet, prefer the trip that covers the booking date.
        if trip == nil, let start = local.start, let match = trips.first(where: { $0.dayIndex(for: start) != nil }) {
            selectedTripID = match.id
        }
    }

    private func save() async {
        guard let target = targetTrip else { return }
        saving = true
        for draft in drafts {
            await TripPlanner.add(draft, rawText: text, to: target, context: context)
        }
        saving = false
        dismiss()
    }

    private func startLabel(_ kind: ReservationKind) -> String {
        switch kind {
        case .hotel: "Check in"
        case .flight, .train: "Departs"
        case .car: "Pick up"
        default: "Starts"
        }
    }

    private func endLabel(_ kind: ReservationKind) -> String {
        switch kind {
        case .hotel: "Check out"
        case .flight, .train: "Arrives"
        case .car: "Drop off"
        default: "Ends"
        }
    }
}

private struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        if let value = date {
            HStack {
                DatePicker(title, selection: Binding(get: { value }, set: { date = $0 }))
                Button { date = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear \(title)")
            }
        } else {
            Button("Add \(title.lowercased()) time") { date = .now }
        }
    }
}
