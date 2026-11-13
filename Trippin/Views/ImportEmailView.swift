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
                        // Fixed height so a long itinerary scrolls inside the box and the buttons stay in view.
                        .frame(height: drafts.isEmpty ? 220 : 100)
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
                        // The system paste button works without the "Allow Paste" prompt,
                        // which a plain button reading UIPasteboard can trigger or be blocked by.
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else { return }
                            Task { @MainActor in text = pasted }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
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

                if drafts.isEmpty {
                    Section {
                        Button { drafts.append(ParsedReservation(start: suggestedStart)) } label: {
                            Label("Enter details yourself", systemImage: "square.and.pencil")
                        }
                    } footer: {
                        Text("No email? Type in a booking from a website, an app or a paper ticket.")
                    }
                }

                ForEach($drafts) { $draft in
                    Section {
                        ReservationFields(draft: $draft)
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
            } catch ClaudeClient.ClaudeError.unreachable {
                note = "Can't reach Claude from this network, so this was read on your device instead."
            } catch {
                note = "\(error.localizedDescription) Used the on-device reader instead."
            }
        }
        let local = EmailParser.parseAll(text)
        drafts = local
        if note == nil {
            let found = local.count > 1 ? "Found \(local.count) bookings on this device. " : "Read on this device. "
            note = KeychainStore.hasAPIKey
                ? found + "Check the details before saving."
                : found + "Check the details before saving, or add a Claude API key in Settings for better results."
        }
        // When the email came from the share sheet, prefer the trip that covers the booking date.
        if trip == nil, let start = local.compactMap(\.start).first,
           let match = trips.first(where: { $0.dayIndex(for: start) != nil }) {
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

    /// Noon on the trip's first day, so a typed-in booking lands on the trip.
    private var suggestedStart: Date? {
        guard let start = targetTrip?.startDate else { return nil }
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: start)
    }
}
