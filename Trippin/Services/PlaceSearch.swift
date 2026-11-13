import MapKit

/// Finds places and addresses with Apple Maps.
enum PlaceSearch {
    struct Place: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var address: String?
        var coordinate: CLLocationCoordinate2D

        static func == (a: Place, b: Place) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    static func search(_ query: String, near region: MKCoordinateRegion? = nil, limit: Int = 10) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let region { request.region = region }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(limit).map { item in
            Place(name: item.name ?? query,
                  address: formattedAddress(item),
                  coordinate: item.placemark.coordinate)
        }
    }

    static func first(_ query: String, near region: MKCoordinateRegion? = nil) async -> Place? {
        await search(query, near: region, limit: 1).first
    }

    /// Region around a destination name, used to bias searches.
    static func region(for destination: String) async -> MKCoordinateRegion? {
        guard !destination.isEmpty, let place = await first(destination) else { return nil }
        return MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }

    private static func formattedAddress(_ item: MKMapItem) -> String? {
        let p = item.placemark
        let parts = [p.subThoroughfare.flatMap { n in p.thoroughfare.map { "\(n) \($0)" } } ?? p.thoroughfare,
                     p.locality, p.administrativeArea, p.country]
        let joined = parts.compactMap { $0 }.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }
}
