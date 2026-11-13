import UIKit
import CoreLocation

/// Opens a place in Apple Maps, Google Maps or Amap. Falls back to the
/// web version when the app isn't installed.
enum MapsApp: String, CaseIterable, Identifiable {
    case apple, google, amap

    var id: String { rawValue }

    var name: String {
        switch self {
        case .apple: "Apple Maps"
        case .google: "Google Maps"
        case .amap: "Amap (高德地图)"
        }
    }

    var isInstalled: Bool {
        switch self {
        case .apple: true
        case .google: UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
        case .amap: UIApplication.shared.canOpenURL(URL(string: "iosamap://")!)
        }
    }

    /// `text` is what the maps app searches for: the place's name.
    /// The coordinate, when known, places the pin (Apple Maps, Amap) or centres the map (Google).
    func url(text: String, coordinate: CLLocationCoordinate2D?, directions: Bool) -> URL? {
        let query = text, name = text
        var c = URLComponents()
        let ll = coordinate.map { "\($0.latitude),\($0.longitude)" }

        switch self {
        case .apple:
            c.scheme = "https"; c.host = "maps.apple.com"; c.path = "/"
            var items = [URLQueryItem(name: "q", value: name)]
            if directions {
                items.append(URLQueryItem(name: "daddr", value: ll ?? query))
            } else if let ll {
                items.append(URLQueryItem(name: "ll", value: ll))
            } else {
                items[0] = URLQueryItem(name: "q", value: query)
            }
            c.queryItems = items

        case .google:
            if isInstalled {
                c.scheme = "comgooglemaps"; c.host = ""
                // Search by name; the coordinate only centres the map on the right area.
                c.queryItems = directions
                    ? [URLQueryItem(name: "daddr", value: query), URLQueryItem(name: "directionsmode", value: "transit")]
                    : [URLQueryItem(name: "q", value: query), URLQueryItem(name: "zoom", value: "16")]
                        + (ll.map { [URLQueryItem(name: "center", value: $0)] } ?? [])
            } else {
                c.scheme = "https"; c.host = "www.google.com"; c.path = "/maps/" + (directions ? "dir/" : "search/")
                c.queryItems = directions
                    ? [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: query)]
                    : [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
            }

        case .amap:
            if isInstalled, let coordinate {
                c.scheme = "iosamap"
                c.host = directions ? "path" : "viewMap"
                c.queryItems = directions
                    ? [URLQueryItem(name: "sourceApplication", value: "Trippin"),
                       URLQueryItem(name: "dlat", value: "\(coordinate.latitude)"),
                       URLQueryItem(name: "dlon", value: "\(coordinate.longitude)"),
                       URLQueryItem(name: "dname", value: name),
                       URLQueryItem(name: "dev", value: "0"),
                       URLQueryItem(name: "t", value: "1")]
                    : [URLQueryItem(name: "sourceApplication", value: "Trippin"),
                       URLQueryItem(name: "poiname", value: name),
                       URLQueryItem(name: "lat", value: "\(coordinate.latitude)"),
                       URLQueryItem(name: "lon", value: "\(coordinate.longitude)"),
                       URLQueryItem(name: "dev", value: "0")]
            } else if isInstalled {
                c.scheme = "iosamap"; c.host = "poi"
                c.queryItems = [URLQueryItem(name: "sourceApplication", value: "Trippin"),
                                URLQueryItem(name: "name", value: query)]
            } else {
                c.scheme = "https"; c.host = "uri.amap.com"
                if let coordinate {
                    c.path = directions ? "/navigation" : "/marker"
                    let position = "\(coordinate.longitude),\(coordinate.latitude)"
                    c.queryItems = directions
                        ? [URLQueryItem(name: "to", value: "\(position),\(name)"), URLQueryItem(name: "mode", value: "bus")]
                        : [URLQueryItem(name: "position", value: position), URLQueryItem(name: "name", value: name)]
                } else {
                    c.path = "/search"
                    c.queryItems = [URLQueryItem(name: "keyword", value: query)]
                }
            }
        }
        return c.url
    }

    @MainActor
    func open(text: String, coordinate: CLLocationCoordinate2D?, directions: Bool = false) {
        guard let url = url(text: text, coordinate: coordinate, directions: directions) else { return }
        UIApplication.shared.open(url)
    }
}
