import SwiftUI
import SwiftData
import CoreLocation
import WebKit

/// Export the trip as a web page (one .html file) to send to people without the
/// app. Pick which cities to include, rename them, preview, then share.
struct ExportTripView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var sections: [TripExport.Section] = []
    @State private var included = Set<String>()
    @State private var names: [String: String] = [:]
    @State private var title = ""
    @State private var titleEdited = false
    @State private var includeTravel = true
    @State private var includeBookingCodes = false
    @State private var exported: URL?
    @State private var previewing = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if sections.isEmpty {
                        Text("Add hotels or places to the trip first.").foregroundStyle(.secondary)
                    }
                    ForEach(sections) { section in
                        HStack(spacing: 12) {
                            Button {
                                if included.contains(section.id) { included.remove(section.id) } else { included.insert(section.id) }
                                exported = nil
                            } label: {
                                Image(systemName: included.contains(section.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(included.contains(section.id) ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(included.contains(section.id) ? "Included" : "Not included")
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("City name", text: nameBinding(section))
                                    .font(.body.weight(.medium))
                                Text(subtitle(section)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Cities")
                } footer: {
                    Text("Grouped by hotel. Tap a name to change it.")
                }

                Section {
                    TextField("Page title", text: Binding(get: { title }, set: { title = $0; titleEdited = true; exported = nil }))
                    Toggle("Flights and trains", isOn: $includeTravel)
                    Toggle("Booking codes", isOn: $includeBookingCodes)
                } header: {
                    Text("Page")
                } footer: {
                    Text(includeBookingCodes
                         ? "Anyone with the file can see the booking codes, which can be enough to change a booking."
                         : "Booking codes are left out, so the page is safe to pass around.")
                }

                Section {
                    Button { export(); previewing = true } label: { Label("Preview", systemImage: "eye") }
                        .disabled(included.isEmpty)
                    if let exported {
                        ShareLink(item: exported) { Label("Share web page", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { export() } label: { Label("Create web page", systemImage: "doc.richtext") }
                            .disabled(included.isEmpty)
                    }
                } footer: {
                    Text("Creates one .html file that opens in any browser. Send it with Messages, AirDrop or email, or save it to Files.")
                }
            }
            .navigationTitle("Export trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $previewing) {
                if let exported { HTMLPreview(url: exported) }
            }
            .task { await load() }
            .onChange(of: included) { _, _ in if !titleEdited { title = defaultTitle } }
            .onChange(of: includeTravel) { _, _ in exported = nil }
            .onChange(of: includeBookingCodes) { _, _ in exported = nil }
        }
    }

    // MARK: Building

    private func load() async {
        // Only once: the sheet can reappear (e.g. after Preview) and must keep the picks.
        guard !loaded else { return }
        loaded = true
        let stays = await TripExportBuilder.stays(of: trip, includeCodes: true)
        sections = TripExport.sections(days: TripExportBuilder.days(of: trip), stays: stays)
        included = Set(sections.map(\.id))
        title = defaultTitle
    }

    private var chosen: [TripExport.Section] {
        sections.filter { included.contains($0.id) }.map { section in
            var s = section
            if let name = names[s.id], !name.trimmingCharacters(in: .whitespaces).isEmpty { s.name = name }
            if !includeBookingCodes { s.stay?.confirmation = nil }
            return s
        }
    }

    private var defaultTitle: String {
        let picked = chosen
        if picked.count == sections.count || picked.count > 3 { return trip.name }
        return picked.map(\.name).joined(separator: " & ")
    }

    private func export() {
        let picked = chosen
        guard let first = picked.first?.days.first?.date, let last = picked.last?.days.last?.date else { return }
        var options = TripExport.Options(title: title.isEmpty ? trip.name : title, subtitle: TripExportBuilder.dateRange(first, last))
        if includeTravel {
            options.journeys = TripExportBuilder.journeys(of: trip, from: first, to: last, includeCodes: includeBookingCodes)
        }
        let html = TripExport.html(sections: picked, options: options)
        let safeName = options.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safeName).html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            exported = url
        } catch {
            exported = nil
        }
    }

    private func nameBinding(_ section: TripExport.Section) -> Binding<String> {
        Binding(get: { names[section.id] ?? section.name },
                set: { names[section.id] = $0; exported = nil; if !titleEdited { title = defaultTitle } })
    }

    private func subtitle(_ section: TripExport.Section) -> String {
        let range = TripExportBuilder.dateRange(section.days.first?.date ?? .now, section.days.last?.date ?? .now)
        if let stay = section.stay { return "\(range) · \(stay.name)" }
        return "\(range) · no hotel"
    }
}

/// Reads the trip's SwiftData models into TripExport's plain values.
@MainActor
enum TripExportBuilder {
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func days(of trip: Trip) -> [TripExport.Day] {
        (0..<trip.dayCount).map { index in
            let items = trip.stops(onDay: index).map { stop in
                TripExport.Item(time: stop.fixedTime.map(time.string(from:)),
                                name: stop.name,
                                localName: stop.distinctLocalName,
                                note: stop.note.isEmpty ? nil : stop.note,
                                isJourney: stop.reservation?.kind.isJourney == true,
                                stayID: stop.reservation?.kind == .hotel ? stop.reservation?.id.uuidString : nil)
            }
            return TripExport.Day(index: index, date: trip.date(forDay: index), items: items)
        }
    }

    static func stays(of trip: Trip, includeCodes: Bool) async -> [TripExport.Stay] {
        var result: [TripExport.Stay] = []
        for hotel in trip.reservations where hotel.kind == .hotel {
            guard let start = hotel.start else { continue }
            let first = trip.dayIndex(for: start) ?? 0
            let last = hotel.end.flatMap { trip.dayIndex(for: $0) } ?? first + 1
            let localAddress = hotel.stops.lazy.compactMap(\.localAddress).first
            let (city, localCity) = await cityName(for: hotel, localAddress: localAddress)
            result.append(TripExport.Stay(id: hotel.id.uuidString, name: hotel.title, localName: hotel.localName,
                                          address: hotel.address, localAddress: localAddress,
                                          confirmation: includeCodes ? hotel.confirmationCode : nil,
                                          firstDay: first, lastDay: last, city: city, cityLocalName: localCity))
        }
        return result
    }

    /// Chinese addresses give the city directly (昆明 → Kunming); otherwise ask the geocoder.
    private static func cityName(for hotel: Reservation, localAddress: String?) async -> (String, String?) {
        for address in [hotel.address, localAddress].compactMap({ $0 }) {
            if let chinese = TripExport.chineseCity(fromAddress: address) { return (TripExport.pinyin(chinese), chinese) }
        }
        if let coordinate = hotel.coordinate,
           let placemark = try? await CLGeocoder().reverseGeocodeLocation(
               CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
               preferredLocale: Locale(identifier: "en_US")).first,
           let city = placemark.locality ?? placemark.administrativeArea {
            return (city, nil)
        }
        return (hotel.title, nil)
    }

    static func journeys(of trip: Trip, from: Date, to: Date, includeCodes: Bool) -> [TripExport.Journey] {
        let start = Calendar.current.startOfDay(for: from)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!
        return trip.sortedReservations.compactMap { r in
            guard r.kind.isJourney, let departs = r.start, departs >= start, departs < end else { return nil }
            let code = includeCodes ? r.confirmationCode : nil
            if let flight = FlightInfo(r) {
                var detail = time.string(from: departs) + " → " + (flight.arrives.map(time.string(from:)) ?? "")
                if flight.dayOffset > 0 { detail += " (+\(flight.dayOffset))" }
                return TripExport.Journey(date: departs, route: "\(flight.from ?? "") ✈ \(flight.to ?? "")",
                                          number: flight.number, detail: detail, isTrain: false, confirmation: code)
            }
            let detail = "Departs " + time.string(from: departs) + (r.end.map { ", arrives " + time.string(from: $0) } ?? "")
            return TripExport.Journey(date: departs, route: r.title, number: nil, detail: detail,
                                      isTrain: r.kind == .train, confirmation: code)
        }
    }

    static func dateRange(_ a: Date, _ b: Date) -> String {
        let en = Locale(identifier: "en_US")
        if Calendar.current.isDate(a, inSameDayAs: b) { return a.formatted(.dateTime.month(.abbreviated).day().year().locale(en)) }
        return "\(a.formatted(.dateTime.month(.abbreviated).day().locale(en))) – \(b.formatted(.dateTime.month(.abbreviated).day().year().locale(en)))"
    }
}

/// Shows the exported page before sharing it.
private struct HTMLPreview: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
        }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
