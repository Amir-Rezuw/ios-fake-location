import MapKit
import Observation

/// Live "search as you type" suggestions, resolved to coordinates on selection.
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            completer.queryFragment = query
            if query.isEmpty { suggestions = [] }
        }
    }

    private(set) var suggestions: [Suggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Cities and landmarks are what you teleport to; street addresses just add noise.
        completer.resultTypes = [.address, .pointOfInterest]
    }

    // MapKit delivers completer callbacks on the main thread, so asserting the
    // isolation is accurate here — and it traps loudly if that ever changes.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            suggestions = completer.results.prefix(8).map {
                Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            suggestions = []
        }
    }

    /// Turns a suggestion into a `Place`, which needs a second round trip for coordinates.
    func resolve(_ suggestion: Suggestion) async -> Place? {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            return nil
        }

        let region = suggestion.subtitle.isEmpty
            ? (item.address?.shortAddress ?? "Dropped pin")
            : suggestion.subtitle

        return Place(
            name: item.name ?? suggestion.title,
            region: region,
            coordinate: item.location.coordinate,
            palette: Palette.forCoordinate(item.location.coordinate)
        )
    }

    func clear() {
        query = ""
        suggestions = []
    }
}

extension Palette {
    /// Gives arbitrary searched places a stable colour, so the backdrop still shifts
    /// when you pick somewhere that isn't in the curated list.
    static func forCoordinate(_ coordinate: CLLocationCoordinate2D) -> Palette {
        let options: [Palette] = [.aurora, .ember, .neon, .jade, .dusk]
        let bucket = Int(abs(coordinate.latitude * 7 + coordinate.longitude * 13)) % options.count
        return options[bucket]
    }
}
