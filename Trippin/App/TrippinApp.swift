import SwiftUI
import SwiftData

@main
struct TrippinApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Trip.self, Reservation.self, Stop.self, TodoItem.self])
    }
}

/// Holds emails that arrived from the share extension until the user files them.
struct PendingEmail: Identifiable {
    let id = UUID()
    let text: String
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var pending: [PendingEmail] = []

    var body: some View {
        TripListView()
            .sheet(item: Binding(get: { pending.first }, set: { if $0 == nil, !pending.isEmpty { pending.removeFirst() } })) { email in
                ImportEmailView(trip: nil, initialText: email.text)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                pending += SharedInbox.takeAll().map(PendingEmail.init)
            }
    }
}
