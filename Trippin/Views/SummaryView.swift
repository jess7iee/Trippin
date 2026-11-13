import SwiftUI
import SwiftData

struct SummaryView: View {
    @Environment(\.modelContext) private var context
    @Bindable var trip: Trip
    @Binding var page: Int
    var onImport: () -> Void
    var onRecommend: () -> Void

    @State private var newTodo = ""
    @State private var placeToOpen: MapPlace?
    @State private var editingReservation: Reservation?
    // Which sections are open. Remembered across launches.
    @AppStorage("summary.showReservations") private var showReservations = true
    @AppStorage("summary.showDays") private var showDays = true
    @AppStorage("summary.showTodos") private var showTodos = true

    var body: some View {
        List {
            Section {
                TripMapView(places: allPlaces, showRoute: false,
                            flights: trip.reservations.compactMap(FlightPath.init), selection: $placeToOpen)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                HStack {
                    stat("\(trip.dayCount)", "days")
                    Divider()
                    stat("\(trip.reservations.count)", "bookings")
                    Divider()
                    stat("\(trip.stops.count)", "stops")
                }
                .frame(maxWidth: .infinity)
            }

            Section {
                if showReservations {
                    if trip.reservations.isEmpty {
                        Text("Paste a confirmation email, or share one to Trippin from Mail or Gmail.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(trip.sortedReservations) { reservation in
                        ReservationRow(reservation: reservation) { placeToOpen = MapPlace(reservation) }
                            .contentShape(Rectangle())
                            .onTapGesture { editingReservation = reservation }
                            .accessibilityAction(named: "Edit") { editingReservation = reservation }
                    }
                    .onDelete { offsets in
                        let items = trip.sortedReservations
                        for index in offsets { context.delete(items[index]) }
                    }
                    Button(action: onImport) { Label("Add reservation", systemImage: "envelope.open") }
                }
            } header: {
                CollapsibleHeader(title: "Reservations", detail: "\(trip.reservations.count)", isExpanded: $showReservations)
            }

            Section {
                if showDays {
                    ForEach(0..<trip.dayCount, id: \.self) { day in
                        Button { withAnimation { page = day } } label: {
                            HStack {
                                Circle().fill(DayColor.color(day)).frame(width: 10, height: 10)
                                Text("Day \(day + 1)").font(.body.weight(.medium))
                                Text(trip.date(forDay: day).formatted(.dateTime.weekday(.wide).month().day()))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let names = trip.stops(onDay: day).map(\.name)
                                Text(names.isEmpty ? "Free day" : names.count == 1 ? "1 stop" : "\(names.count) stops")
                                    .font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } header: {
                CollapsibleHeader(title: "Days", detail: "\(trip.dayCount)", isExpanded: $showDays)
            }

            Section {
                if showTodos {
                    ForEach(trip.todos.sorted { $0.createdAt < $1.createdAt }) { todo in
                        TodoRow(todo: todo)
                    }
                    .onDelete { offsets in
                        let items = trip.todos.sorted { $0.createdAt < $1.createdAt }
                        for index in offsets { context.delete(items[index]) }
                    }
                    HStack {
                        TextField("Add something you want or need to do", text: $newTodo)
                            .onSubmit(addTodo)
                            .submitLabel(.done)
                        Button(action: addTodo) { Image(systemName: "plus.circle.fill") }
                            .disabled(newTodo.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("Add to-do")
                    }
                    Button(action: onRecommend) { Label("Get recommendations and plan days", systemImage: "sparkles") }
                        .disabled(trip.todos.isEmpty)
                }
            } header: {
                CollapsibleHeader(title: "Want to do", detail: "\(trip.todos.count)", isExpanded: $showTodos)
            } footer: {
                if showTodos {
                    Text("e.g. “best ramen”, “buy a SIM card”, “teamLab”, “souvenirs for mom”.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .openInMapsDialog(place: $placeToOpen)
        .sheet(item: $editingReservation) { ReservationEditorView(reservation: $0) }
        #if DEBUG
        .onAppear {
            let items = trip.sortedReservations
            if DemoData.openPage == -1, let n = DemoData.openEditor, items.indices.contains(n - 1) {
                editingReservation = items[n - 1]
            }
        }
        #endif
    }

    private var allPlaces: [MapPlace] {
        trip.stops.sorted { ($0.dayIndex, $0.sortOrder) < ($1.dayIndex, $1.sortOrder) }.compactMap(MapPlace.init)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func addTodo() {
        let text = newTodo.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let todo = TodoItem(text: text)
        context.insert(todo)
        todo.trip = trip
        newTodo = ""
    }
}

/// A section header you tap to hide or show the section.
private struct CollapsibleHeader: View {
    let title: String
    let detail: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if !isExpanded {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Shown" : "Hidden, \(detail)")
        .accessibilityHint(isExpanded ? "Hides this section" : "Shows this section")
    }
}

private struct TodoRow: View {
    @Bindable var todo: TodoItem

    var body: some View {
        Button { todo.isDone.toggle() } label: {
            HStack {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? Color.accentColor : .secondary)
                Text(todo.text)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ReservationRow: View {
    let reservation: Reservation
    var onOpenMap: () -> Void

    var body: some View {
        if let flight = FlightInfo(reservation) {
            flightBody(flight)
        } else {
            standardBody
        }
    }

    private func flightBody(_ flight: FlightInfo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let start = reservation.start {
                    Text(start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                FlightCard(info: flight)
                if let code = reservation.confirmationCode {
                    Text("Booking \(code)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if reservation.coordinate != nil {
                Button(action: onOpenMap) { Image(systemName: "map") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open in maps")
            }
        }
    }

    private var standardBody: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reservation.kind.symbol)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.title).font(.body.weight(.medium))
                if let local = reservation.localName, !local.isEmpty, local != reservation.title {
                    Text(local).font(.subheadline).textSelection(.enabled)
                }
                if let start = reservation.start {
                    Text(timeRange(start, reservation.end)).font(.subheadline).foregroundStyle(.secondary)
                }
                if let code = reservation.confirmationCode {
                    Text("Confirmation \(code)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if reservation.coordinate != nil || reservation.address != nil {
                Button(action: onOpenMap) { Image(systemName: "map") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open in maps")
            }
        }
    }

    private func timeRange(_ start: Date, _ end: Date?) -> String {
        let s = start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        guard let end else { return s }
        return "\(s) → \(end.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }
}
