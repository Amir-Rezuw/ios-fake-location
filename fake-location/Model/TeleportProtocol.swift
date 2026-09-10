import CoreLocation

/// Wire format spoken with `agent/teleportd.py` over Bonjour-discovered TCP.
///
/// Messages are newline-delimited JSON. The `Stage` cases must stay in step with the
/// `Stage` class in the daemon.
enum Teleport {
    static let serviceType = "_teleport._tcp"

    struct Command: Encodable {
        enum Verb: String, Encodable {
            case set, clear, status
        }

        var command: Verb
        var latitude: Double?
        var longitude: Double?
        var name: String?

        static func set(to place: Place) -> Command {
            Command(
                command: .set,
                latitude: place.coordinate.latitude,
                longitude: place.coordinate.longitude,
                name: place.name
            )
        }

        static let clear = Command(command: .clear)
        static let status = Command(command: .status)
    }

    struct Status: Decodable, Equatable {
        enum Stage: String, Decodable {
            /// `pymobiledevice3 remote tunneld` isn't running on the Mac.
            case tunnelOffline
            /// The tunnel is up but no trusted device is attached to it.
            case noDevice
            case connecting
            /// Attached to the device, real GPS still in effect.
            case ready
            case spoofing
            case error
        }

        var stage: Stage
        var device: String?
        var latitude: Double?
        var longitude: Double?
        var place: String?
        var detail: String?

        var coordinate: CLLocationCoordinate2D? {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

extension Teleport.Status {
    /// Short label for the status pill.
    var headline: String {
        switch stage {
        case .tunnelOffline: "Tunnel offline"
        case .noDevice: "No device"
        case .connecting: "Connecting"
        case .ready: "Ready"
        case .spoofing: place.map { "In \($0)" } ?? "Spoofing"
        case .error: "Agent error"
        }
    }

    var symbol: String {
        switch stage {
        case .tunnelOffline: "bolt.horizontal.circle"
        case .noDevice: "iphone.slash"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .ready: "checkmark.seal"
        case .spoofing: "location.fill.viewfinder"
        case .error: "exclamationmark.triangle"
        }
    }

    /// Whether a teleport can be requested right now.
    var acceptsCommands: Bool {
        stage == .ready || stage == .spoofing
    }
}
