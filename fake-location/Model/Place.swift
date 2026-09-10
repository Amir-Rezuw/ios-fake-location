import CoreLocation
import SwiftUI

/// Somewhere you can be.
struct Place: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    /// Drives the aurora backdrop so each destination has its own light.
    var palette: Palette = .aurora

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        name: String,
        region: String,
        latitude: Double,
        longitude: Double,
        palette: Palette = .aurora
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.palette = palette
    }

    init(name: String, region: String, coordinate: CLLocationCoordinate2D, palette: Palette = .aurora) {
        self.init(
            name: name,
            region: region,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            palette: palette
        )
    }

    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Place {
    /// Formatted for the coordinate readout, with a hemisphere letter instead of a sign.
    var prettyCoordinate: String {
        let lat = String(format: "%.4f° %@", abs(latitude), latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.4f° %@", abs(longitude), longitude >= 0 ? "E" : "W")
        return "\(lat)  \(lon)"
    }
}

/// A three-stop colour set used for the animated mesh backdrop.
struct Palette: Hashable {
    var low: Color
    var mid: Color
    var high: Color

    static let aurora = Palette(
        low: Color(red: 0.05, green: 0.09, blue: 0.20),
        mid: Color(red: 0.18, green: 0.36, blue: 0.85),
        high: Color(red: 0.53, green: 0.85, blue: 0.98)
    )

    static let ember = Palette(
        low: Color(red: 0.16, green: 0.05, blue: 0.09),
        mid: Color(red: 0.72, green: 0.22, blue: 0.24),
        high: Color(red: 0.99, green: 0.71, blue: 0.38)
    )

    static let neon = Palette(
        low: Color(red: 0.10, green: 0.04, blue: 0.19),
        mid: Color(red: 0.55, green: 0.18, blue: 0.78),
        high: Color(red: 0.99, green: 0.45, blue: 0.79)
    )

    static let jade = Palette(
        low: Color(red: 0.03, green: 0.14, blue: 0.13),
        mid: Color(red: 0.09, green: 0.51, blue: 0.44),
        high: Color(red: 0.58, green: 0.94, blue: 0.75)
    )

    static let dusk = Palette(
        low: Color(red: 0.09, green: 0.07, blue: 0.16),
        mid: Color(red: 0.36, green: 0.29, blue: 0.72),
        high: Color(red: 0.96, green: 0.76, blue: 0.55)
    )
}

extension Place {
    /// Hand-picked destinations for the carousel.
    static let featured: [Place] = [
        Place(name: "Berlin", region: "Germany", latitude: 52.5200, longitude: 13.4050, palette: .neon),
        Place(name: "Tokyo", region: "Japan", latitude: 35.6762, longitude: 139.6503, palette: .ember),
        Place(name: "New York", region: "United States", latitude: 40.7128, longitude: -74.0060, palette: .aurora),
        Place(name: "Reykjavík", region: "Iceland", latitude: 64.1466, longitude: -21.9426, palette: .jade),
        Place(name: "Tehran", region: "Iran", latitude: 35.6892, longitude: 51.3890, palette: .dusk),
        Place(name: "Cape Town", region: "South Africa", latitude: -33.9249, longitude: 18.4241, palette: .jade),
        Place(name: "Rio de Janeiro", region: "Brazil", latitude: -22.9068, longitude: -43.1729, palette: .ember),
        Place(name: "Sydney", region: "Australia", latitude: -33.8688, longitude: 151.2093, palette: .aurora),
        Place(name: "Marrakesh", region: "Morocco", latitude: 31.6295, longitude: -7.9811, palette: .ember),
        Place(name: "Kyoto", region: "Japan", latitude: 35.0116, longitude: 135.7681, palette: .dusk),
        Place(name: "Zürich", region: "Switzerland", latitude: 47.3769, longitude: 8.5417, palette: .aurora),
        Place(name: "Istanbul", region: "Türkiye", latitude: 41.0082, longitude: 28.9784, palette: .neon),
    ]
}
