import CoreLocation
import MapKit
import Observation

/// The app's single source of truth: what you've aimed at, what the device is doing,
/// and where the animation sequence has got to.
@Observable
final class TeleportStore {
    /// Drives the whole arrival choreography, so the views stay declarative.
    enum Phase: Equatable {
        case idle
        /// Command sent, waiting for the agent to confirm.
        case charging
        /// Confirmed — plays the shockwave and the arc.
        case arrived
    }

    let link = AgentLink()
    let search = PlaceSearch()
    let device = DeviceLocation()

    /// Where the reticle is aimed. Starts somewhere recognisable.
    private(set) var target: Place = Place.featured[0]
    private(set) var phase: Phase = .idle
    private(set) var history: [Place] = []
    /// Coordinate the last teleport departed from, for the arc overlay.
    private(set) var departure: CLLocationCoordinate2D?
    /// Changes whenever the target was chosen deliberately rather than by panning the
    /// map, which is the map's cue to fly there.
    private(set) var flightToken = UUID()

    private var confirmation: Task<Void, Never>?
    private var naming: Task<Void, Never>?

    /// The place currently in effect on the device, as reported by the agent.
    var pinned: Place? {
        guard link.status.stage == .spoofing, let coordinate = link.status.coordinate else {
            return nil
        }
        return Place(
            name: link.status.place ?? "Custom pin",
            region: link.status.device ?? "This device",
            coordinate: coordinate
        )
    }

    var isSpoofing: Bool { pinned != nil }

    func begin() {
        link.activate()
        device.start()
    }

    /// Picks a known place, and asks the map to fly to it.
    func aim(at place: Place) {
        naming?.cancel()
        target = place
        flightToken = UUID()
    }

    /// Aims at wherever the device currently claims to be — which is the faked
    /// coordinate once a teleport has taken hold.
    func aimAtDevice() {
        guard let coordinate = device.coordinate else { return }
        aim(at: Place(
            name: "Current location",
            region: "Where this iPhone reports itself",
            coordinate: coordinate,
            palette: target.palette
        ))
    }

    /// Follows the map as it's panned. Keeps the current name while the reticle is
    /// still essentially over that place, and re-identifies the spot once it isn't.
    func aimFreely(to coordinate: CLLocationCoordinate2D) {
        if target.coordinate.distance(to: coordinate) < 1_200 {
            target.latitude = coordinate.latitude
            target.longitude = coordinate.longitude
            return
        }

        target = Place(
            name: "Dropped pin",
            region: "Locating…",
            coordinate: coordinate,
            // Keeping the palette avoids the backdrop strobing while you pan.
            palette: target.palette
        )
        nameDroppedPin(at: coordinate)
    }

    /// Sends the target to the agent and waits for the device to confirm it took effect.
    func teleport() {
        guard link.canTeleport, phase != .charging else { return }

        departure = link.status.coordinate ?? device.coordinate
        phase = .charging
        let destination = target
        link.send(.set(to: destination))

        confirmation?.cancel()
        confirmation = Task { [weak self] in
            guard let self else { return }
            let landed = await waitForArrival(at: destination)
            guard !Task.isCancelled else { return }

            if landed {
                remember(destination)
                phase = .arrived
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
            }
            phase = .idle
        }
    }

    /// Hands the real GPS back to the device.
    func release() {
        guard link.linkState == .linked else { return }
        confirmation?.cancel()
        phase = .idle
        departure = nil
        link.send(.clear)
    }

    // MARK: - Private

    /// The agent reports asynchronously, so watch its status until the coordinate matches.
    private func waitForArrival(at destination: Place) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return false }
            if link.status.stage == .spoofing,
               let reported = link.status.coordinate,
               reported.isEssentially(destination.coordinate) {
                return true
            }
            if link.status.stage == .error { return false }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return false
    }

    /// Reverse-geocodes a dropped pin, debounced so panning doesn't fire a request per frame.
    private func nameDroppedPin(at coordinate: CLLocationCoordinate2D) {
        naming?.cancel()
        naming = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self, !Task.isCancelled else { return }
            guard let request = MKReverseGeocodingRequest(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ) else { return }

            guard let item = try? await request.mapItems.first, !Task.isCancelled else { return }
            // The map may have moved on while we were waiting.
            guard target.coordinate.distance(to: coordinate) < 1_200 else { return }

            target.name = item.name ?? "Dropped pin"
            target.region = item.address?.shortAddress ?? item.address?.fullAddress ?? "Unnamed place"
        }
    }

    private func remember(_ place: Place) {
        history.removeAll { $0.name == place.name && $0.region == place.region }
        history.insert(place, at: 0)
        if history.count > 12 { history.removeLast() }
    }
}

extension CLLocationCoordinate2D {
    /// Coordinates make a JSON round trip, so compare with a tolerance.
    func isEssentially(_ other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 0.0005 && abs(longitude - other.longitude) < 0.0005
    }

    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
