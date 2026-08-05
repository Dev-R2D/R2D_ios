#if canImport(CoreLocation)
import CoreLocation
import Foundation
import R2DCore

// CLLocationManager invokes delegates on its creation run loop. Mutable delivery state is serialized by lock;
// @unchecked Sendable is limited to this Apple delegate bridge and no CLLocation escapes the adapter.
public final class CoreLocationTracker: NSObject, LocationTracker, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager: CLLocationManager, filter: LocationSampleFilter, lock = NSLock()
    private var listeners: [UUID: @Sendable (LocationSnapshot) -> Void] = [:]
    private var latestSample: LocationSample?, running = false, paused = false
    public private(set) var snapshot: LocationSnapshot = .empty
    public var isRunning: Bool { lock.withLock { running } }

    public init(configuration: LocationTrackingConfiguration = .init(), manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager; filter = LocationSampleFilter(configuration: configuration); super.init()
        manager.delegate = self; manager.desiredAccuracy = configuration.desiredAccuracyM; manager.distanceFilter = configuration.distanceFilterM
    }
    public func readiness() -> LocationReadiness {
        .init(servicesEnabled: CLLocationManager.locationServicesEnabled(), authorization: normalize(manager.authorizationStatus), isAccuracySufficient: latestSample.map { $0.horizontalAccuracyM <= filter.configuration.maximumHorizontalAccuracyM } ?? false)
    }
    public func requestAuthorization() { manager.requestWhenInUseAuthorization() }
    public func start(sessionId: String) throws {
        let ready = readiness(); guard ready.servicesEnabled else { throw LocationTrackingError.serviceUnavailable }
        if ready.authorization == .denied { throw LocationTrackingError.authorizationDenied }
        if ready.authorization == .restricted { throw LocationTrackingError.authorizationRestricted }
        try lock.withLock { guard !running else { throw LocationTrackingError.alreadyRunning }; running = true; paused = false }
        manager.startUpdatingLocation()
    }
    public func stop() { lock.withLock { running = false; paused = false }; manager.stopUpdatingLocation() }
    public func pause() { lock.withLock { paused = true }; manager.stopUpdatingLocation() }
    public func resume() { guard lock.withLock({ running }) else { return }; lock.withLock { paused = false }; manager.startUpdatingLocation() }
    public func subscribe(_ listener: @escaping @Sendable (LocationSnapshot) -> Void) -> Unsubscribe {
        let id = UUID(); lock.withLock { listeners[id] = listener }; return { [weak self] in self?.lock.withLock { self?.listeners[id] = nil } }
    }
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard lock.withLock({ running && !paused }) else { return }
        for value in locations {
            let raw = RawLocationSample(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude, altitudeM: value.altitude, speedMps: value.speed, courseDegrees: value.course, horizontalAccuracyM: value.horizontalAccuracy, timestamp: value.timestamp)
            guard let sample = filter.filter(raw, now: Date(), previous: latestSample) else { continue }; latestSample = sample
            guard sample.quality == .valid else { continue }
            let next = LocationSnapshot(coordinate: .init(latitude: sample.latitude, longitude: sample.longitude), speedMps: sample.speedMps ?? 0, heading: sample.bearingDegrees ?? 0, mapMatchConfidence: accuracyConfidence(sample.horizontalAccuracyM))
            snapshot = next; lock.withLock { Array(listeners.values) }.forEach { $0(next) }
        }
    }
    private func normalize(_ value: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch value { case .notDetermined: .notDetermined; case .restricted: .restricted; case .denied: .denied; case .authorizedAlways: .authorizedAlways; case .authorizedWhenInUse: .authorizedWhenInUse; @unknown default: .denied }
    }
    private func accuracyConfidence(_ accuracy: Double) -> Double { max(0, min(1, 1 - accuracy / filter.configuration.maximumHorizontalAccuracyM)) }
}
#endif
