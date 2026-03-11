import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<String?, Never>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var isFetching = false

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Request location and reverse geocode to a city/area string.
    /// Returns nil if permission denied, location unavailable, or geocode fails.
    func fetchLocationString() async -> String? {
        // Guard against concurrent calls
        guard !isFetching else { return nil }
        isFetching = true
        defer { isFetching = false }

        let status = manager.authorizationStatus
        if status == .notDetermined {
#if os(iOS)
            manager.requestWhenInUseAuthorization()
#else
            manager.requestAlwaysAuthorization()
#endif
            // Wait for actual authorization callback instead of fixed sleep
            let newStatus = await withCheckedContinuation { continuation in
                self.authContinuation = continuation
            }
#if os(iOS)
            guard newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways else {
                return nil
            }
#else
            guard newStatus == .authorizedAlways else {
                return nil
            }
#endif
        } else {
#if os(iOS)
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                return nil
            }
#else
            guard status == .authorizedAlways else {
                return nil
            }
#endif
        }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        authContinuation?.resume(returning: status)
        authContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
            return
        }

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let name = placemarks?.first.flatMap { placemark in
                [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
            self?.locationContinuation?.resume(returning: name?.isEmpty == true ? nil : name)
            self?.locationContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }
}
