import SwiftUI
import SwiftData

/// The fields of a reservation, shared by the email import and the editor.
struct ReservationFields: View {
    @Binding var draft: ParsedReservation

    var body: some View {
        Picker("Type", selection: $draft.kind) {
            ForEach(ReservationKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
        }
        TextField("Title", text: $draft.title)
        TextField("Local name (e.g. パーク ハイアット 東京)", text: optional(\.localName))
        TextField("Confirmation code", text: optional(\.confirmationCode))
        OptionalDatePicker(title: draft.kind.startLabel, date: $draft.start)
        OptionalDatePicker(title: draft.kind.endLabel, date: $draft.end)
        TextField("Address or place", text: optional(\.address), axis: .vertical)
    }

    /// Binds an optional string field to a text field, storing nil when empty.
    private func optional(_ keyPath: WritableKeyPath<ParsedReservation, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" },
                set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }
}

struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?
    /// Used as the starting value when a time is added.
    var suggested: Date = .now
    var components: DatePickerComponents = [.date, .hourAndMinute]

    var body: some View {
        if let value = date {
            HStack {
                DatePicker(title, selection: Binding(get: { value }, set: { date = $0 }), displayedComponents: components)
                Button { date = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear \(title)")
            }
        } else {
            Button(title.localizedCaseInsensitiveContains("time") ? "Add \(title.lowercased())" : "Add \(title.lowercased()) time") {
                date = suggested
            }
        }
    }
}

/// View and change a saved reservation. Saving rebuilds its stops on the right days.
struct ReservationEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let reservation: Reservation

    @State private var draft = ParsedReservation()
    @State private var saving = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section { ReservationFields(draft: $draft) } footer: {
                    Text("Changing the times moves this booking to the matching days. Changing the address finds it on the map again.")
                }

                if !reservation.stops.isEmpty {
                    Section("On your itinerary") {
                        ForEach(reservation.stops.sorted { $0.dayIndex < $1.dayIndex }) { stop in
                            LabeledContent(stop.name, value: "Day \(stop.dayIndex + 1)")
                        }
                    }
                }

                if !reservation.rawText.isEmpty {
                    Section {
                        DisclosureGroup("Original email") {
                            Text(reservation.rawText)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button("Delete reservation", role: .destructive) { confirmingDelete = true }
                }
            }
            .navigationTitle(reservation.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Save") { Task { await save() } }
                            .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("Delete \(reservation.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete reservation and its stops", role: .destructive) {
                    context.delete(reservation)
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear { draft = reservation.fields }
        }
    }

    private func save() async {
        saving = true
        if draft != reservation.fields || reservation.coordinate == nil {
            await TripPlanner.update(reservation, with: draft, context: context)
        }
        saving = false
        dismiss()
    }
}
