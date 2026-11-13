import SwiftUI
import MapKit

/// Drag the map until the pin in the middle sits on the place, then tap Use This Spot.
/// For places Apple Maps doesn't know (common for China when the phone is outside China).
struct PinPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// Where to start: the current (maybe approximate) location, or somewhere nearby.
    let start: CLLocationCoordinate2D?
    var onPick: (CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var query = ""
    @State private var searchFailed = false

    var body: some View {
        NavigationStack {
            Map(position: $position)
                .mapStyle(.standard(pointsOfInterest: .all))
                .mapControls { MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
                .overlay {
                    // The pin's point marks the centre of the map.
                    Image(systemName: "mappin")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.red)
                        .shadow(radius: 2)
                        .offset(y: -20)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .safeAreaInset(edge: .top) {
                    // Jump to an area Apple Maps does know (a district, station or landmark), then fine-tune.
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Jump to an area, e.g. Shunyi or a nearby station", text: $query)
                            .submitLabel(.search)
                            .onSubmit { Task { await jump() } }
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 6)
                }
                .safeAreaInset(edge: .bottom) {
                    Text(searchFailed ? "Couldn't find that area. Try a district, station or landmark."
                                      : "Drag the map so the pin sits on \(title).")
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
                .navigationTitle("Adjust pin")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use This Spot") {
                            if let center { onPick(center) }
                            dismiss()
                        }
                        .disabled(center == nil)
                    }
                }
                .task(id: query.isEmpty) { searchFailed = false }
                .onAppear {
                    if let start {
                        position = .region(MKCoordinateRegion(center: start, latitudinalMeters: 1500, longitudinalMeters: 1500))
                        center = start
                    }
                }
        }
    }

    private func jump() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let region = center.map { MKCoordinateRegion(center: $0, latitudinalMeters: 200_000, longitudinalMeters: 200_000) }
        guard let place = await PlaceSearch.first(text, near: region) else { searchFailed = true; return }
        searchFailed = false
        withAnimation {
            position = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000))
        }
    }
}
