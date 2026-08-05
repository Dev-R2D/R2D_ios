import Foundation
import R2DCore

public struct LocationTrackingConfiguration: Sendable {
    public let desiredAccuracyM: Double, distanceFilterM: Double, maximumSampleAgeSec: Double
    public let maximumHorizontalAccuracyM: Double, maximumPlausibleSpeedMps: Double
    public init(desiredAccuracyM: Double = 10, distanceFilterM: Double = 3, maximumSampleAgeSec: Double = 10, maximumHorizontalAccuracyM: Double = 50, maximumPlausibleSpeedMps: Double = 30) {
        self.desiredAccuracyM = desiredAccuracyM; self.distanceFilterM = distanceFilterM; self.maximumSampleAgeSec = maximumSampleAgeSec; self.maximumHorizontalAccuracyM = maximumHorizontalAccuracyM; self.maximumPlausibleSpeedMps = maximumPlausibleSpeedMps
    }
}

public struct RawLocationSample: Equatable, Sendable {
    public let latitude: Double, longitude: Double, altitudeM: Double, speedMps: Double, courseDegrees: Double
    public let horizontalAccuracyM: Double, timestamp: Date
    public init(latitude: Double, longitude: Double, altitudeM: Double, speedMps: Double, courseDegrees: Double, horizontalAccuracyM: Double, timestamp: Date) {
        self.latitude = latitude; self.longitude = longitude; self.altitudeM = altitudeM; self.speedMps = speedMps; self.courseDegrees = courseDegrees; self.horizontalAccuracyM = horizontalAccuracyM; self.timestamp = timestamp
    }
}

public struct LocationSampleFilter: Sendable {
    public let configuration: LocationTrackingConfiguration
    public init(configuration: LocationTrackingConfiguration = .init()) { self.configuration = configuration }
    public func filter(_ raw: RawLocationSample, now: Date, previous: LocationSample?) -> LocationSample? {
        guard raw.horizontalAccuracyM >= 0, raw.horizontalAccuracyM <= configuration.maximumHorizontalAccuracyM,
              now.timeIntervalSince(raw.timestamp) <= configuration.maximumSampleAgeSec,
              previous?.timestamp != raw.timestamp else { return nil }
        let speed = raw.speedMps >= 0 ? raw.speedMps : nil, bearing = raw.courseDegrees >= 0 ? raw.courseDegrees : nil
        let jump = speed.map { $0 > configuration.maximumPlausibleSpeedMps } ?? false
        return .init(latitude: raw.latitude, longitude: raw.longitude, altitudeM: raw.altitudeM, speedMps: speed, bearingDegrees: bearing, horizontalAccuracyM: raw.horizontalAccuracyM, timestamp: raw.timestamp, quality: jump ? .implausibleJump : .valid)
    }
}
