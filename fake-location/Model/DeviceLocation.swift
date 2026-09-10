import CoreLocation
import Observation

/// Where this device currently reports itself to be.
///
/// Once the agent is spoofing, CoreLocation here returns the faked coordinate too — which
/// is the app's own proof that the spoof took hold system-wide.
@Observable
final class DeviceLocation: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var isAuthorized = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    // CoreLocation calls its delegate on the thread the manager was created on, which
    // is the main thread here.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated {
            coordinate = latest.coordinate
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
            if isAuthorized { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        // A transient failure just means no fix yet; the next update supersedes it.
    }
}
