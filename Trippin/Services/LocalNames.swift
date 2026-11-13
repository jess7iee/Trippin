import Foundation
import CoreLocation
import SwiftData

/// Fills in each stop's name and address in the local language.
///
/// The address comes from Apple's geocoder in the local locale (no key
/// needed). Names come from Claude when an API key is set, in one request per
/// language.
@MainActor
enum LocalNames {

    /// Looks up local names and addresses for any stops on the trip that don't have them yet.
    static func fill(_ trip: Trip, context: ModelContext) async {
        let pending = trip.stops.filter { !$0.localLookupDone && $0.coordinate != nil }
        guard !pending.isEmpty else { return }

        var needsName: [String: (LocalLanguage, [Stop])] = [:]
        for stop in pending {
            guard let coordinate = stop.coordinate,
                  let placemark = await reverseGeocode(coordinate) else { continue }
            if let language = LocalLanguage.forCountry(placemark.isoCountryCode) {
                // A booking's own address in the local script (e.g. a full Chinese
                // address from the confirmation) beats the geocoder's, which can be sparse.
                if stop.localAddress == nil, let address = stop.address, EmailParser.isLocalScript(address) {
                    stop.localAddress = address
                }
                if stop.localAddress == nil {
                    stop.localAddress = await localAddress(coordinate, language: language)
                }
                if (stop.localName ?? "").isEmpty, !language.matches(.current) {
                    needsName[language.code, default: (language, [])].1.append(stop)
                }
            }
            stop.localLookupDone = true
        }

        if KeychainStore.hasAPIKey {
            for (language, stops) in needsName.values {
                let destination = trip.destination.isEmpty ? trip.name : trip.destination
                let places = stops.map { ClaudeClient.PlaceToName(name: baseName($0), address: $0.address ?? $0.localAddress) }
                guard let names = try? await ClaudeClient().localNames(for: places, language: language, near: destination) else {
                    stops.forEach { $0.localLookupDone = false }  // try again next time
                    continue
                }
                for (stop, name) in zip(stops, names) where !name.isEmpty {
                    stop.localName = name
                }
            }
        }

        // Keep reservations in step with their stops.
        for reservation in trip.reservations where (reservation.localName ?? "").isEmpty {
            reservation.localName = reservation.stops.lazy.compactMap(\.localName).first
        }
        for stop in trip.stops where (stop.localName ?? "").isEmpty {
            if let name = stop.reservation?.localName { stop.localName = name }
        }
        try? context.save()
    }

    /// "Check in: Park Hyatt Tokyo" → "Park Hyatt Tokyo".
    static func baseName(_ stop: Stop) -> String {
        guard let reservation = stop.reservation else { return stop.name }
        return reservation.title
    }

    private static func reverseGeocode(_ coordinate: CLLocationCoordinate2D, locale: Locale? = nil) async -> CLPlacemark? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: locale).first
    }

    private static func localAddress(_ coordinate: CLLocationCoordinate2D, language: LocalLanguage) async -> String? {
        guard let p = await reverseGeocode(coordinate, locale: language.locale) else { return nil }
        let eastAsian = ["ja", "zh", "ko"].contains(language.locale.language.languageCode?.identifier ?? "")
        let parts: [String?] = eastAsian
            // Big-to-small order, written without spaces: 東京都新宿区西新宿3丁目7-1
            ? [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare]
            : [[p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " "), p.postalCode, p.locality]
        var seen = Set<String>()
        let unique = parts.compactMap { $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { return nil }
        return unique.joined(separator: eastAsian ? "" : ", ")
    }
}
