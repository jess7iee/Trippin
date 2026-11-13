import SwiftUI
import SwiftData

/// A trip split into pages: Summary, Day 1, Day 2, …
struct TripDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var trip: Trip
    /// -1 is the Summary page; 0… are days.
    @State private var page = -1
    @State private var showingImport = false
    @State private var showingRecommendations = false
    @State private var showingEditor = false

    var body: some View {
        VStack(spacing: 0) {
            PagePicker(trip: trip, page: $page)
            Divider()
            TabView(selection: $page) {
                SummaryView(trip: trip, page: $page,
                            onImport: { showingImport = true },
                            onRecommend: { showingRecommendations = true })
                    .tag(-1)
                ForEach(0..<trip.dayCount, id: \.self) { day in
                    DayView(trip: trip, day: day)
                        .tag(day)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingImport = true } label: { Label("Add reservation from email", systemImage: "envelope.open") }
                    Button { showingRecommendations = true } label: { Label("Get recommendations", systemImage: "sparkles") }
                    Button { showingEditor = true } label: { Label("Edit trip", systemImage: "pencil") }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $showingImport) { ImportEmailView(trip: trip, initialText: "") }
        .sheet(isPresented: $showingRecommendations) { RecommendationsView(trip: trip) }
        .sheet(isPresented: $showingEditor) { TripEditorView(trip: trip) }
        .task(id: trip.stops.count) {
            await LocalNames.fill(trip, context: context)
        }
        .onChange(of: trip.dayCount) { _, count in
            if page >= count { page = count - 1 }
        }
        #if DEBUG
        .onAppear { if let demo = DemoData.openPage { page = demo } }
        #endif
    }
}

private struct PagePicker: View {
    let trip: Trip
    @Binding var page: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "Summary", subtitle: nil, tag: -1)
                    ForEach(0..<trip.dayCount, id: \.self) { day in
                        chip(title: "Day \(day + 1)",
                             subtitle: trip.date(forDay: day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                             tag: day)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: page) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func chip(title: String, subtitle: String?, tag: Int) -> some View {
        let selected = page == tag
        return Button {
            withAnimation { page = tag }
        } label: {
            VStack(spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle { Text(subtitle).font(.caption2) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 40)
            .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .id(tag)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
