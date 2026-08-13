import Foundation
import R2DCore

public struct SensorVector3: Codable, Equatable, Sendable {
    public let x: Double, y: Double, z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}

/// Canonical payload shared by CoreMotion and imported Sensor Logger recordings.
public struct RoadSurfaceSensorSample: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case accelerometer, gyroscope, deviceMotion, sensorLogger }
    public let timestamp: TimeInterval, source: Source
    public let acceleration: SensorVector3?, rotationRate: SensorVector3?, gravity: SensorVector3?
    public let vibrationRMS: Double?, jerk: Double?, coordinate: Coordinate?, speedMps: Double?
    public init(timestamp: TimeInterval, source: Source, acceleration: SensorVector3? = nil, rotationRate: SensorVector3? = nil, gravity: SensorVector3? = nil, vibrationRMS: Double? = nil, jerk: Double? = nil, coordinate: Coordinate? = nil, speedMps: Double? = nil) {
        self.timestamp = timestamp; self.source = source; self.acceleration = acceleration; self.rotationRate = rotationRate; self.gravity = gravity; self.vibrationRMS = vibrationRMS; self.jerk = jerk; self.coordinate = coordinate; self.speedMps = speedMps
    }
}

public struct SensorLoggerCSVDecoder: Sendable {
    public enum SensorKind: Sendable { case accelerometer, gyroscope, gravity, location, combined }
    public init() {}
    public func decode(_ data: Data, kind: SensorKind = .combined) throws -> [RoadSurfaceSensorSample] {
        let rows = try CSVTable.rows(from: data)
        func value(_ row: [String: String], _ aliases: [String]) -> Double? {
            let normalized = Dictionary(uniqueKeysWithValues: row.map { ($0.key.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: ""), $0.value) })
            return aliases.lazy.compactMap { Double(normalized[$0.lowercased().replacingOccurrences(of: "_", with: "")] ?? "") }.first
        }
        let samples = rows.compactMap { row -> RoadSurfaceSensorSample? in
            let elapsed = value(row, ["seconds_elapsed", "elapsed_s", "seconds", "timestamp", "시간"])
            let epochNanoseconds = value(row, ["time"])
            guard let timestamp = elapsed ?? epochNanoseconds.map({ $0 / 1_000_000_000 }) else { return nil }
            let xyz = zip3(value(row, ["x", "ax", "accel_x", "accelerometer_x", "useraccelerationx"]), value(row, ["y", "ay", "accel_y", "accelerometer_y", "useraccelerationy"]), value(row, ["z", "az", "accel_z", "accelerometer_z", "useraccelerationz"]))
            let rotation = zip3(value(row, ["gx", "gyro_x", "rotationratex"]), value(row, ["gy", "gyro_y", "rotationratey"]), value(row, ["gz", "gyro_z", "rotationratez"])).map { SensorVector3(x: $0.0, y: $0.1, z: $0.2) }
            let coordinate = zip2(value(row, ["latitude", "lat", "위도"]), value(row, ["longitude", "lon", "lng", "경도"])).map { Coordinate(latitude: $0.0, longitude: $0.1) }
            switch kind {
            case .accelerometer:
                guard let xyz else { return nil }; return .init(timestamp: timestamp, source: .sensorLogger, acceleration: .init(x: xyz.0, y: xyz.1, z: xyz.2))
            case .gyroscope:
                guard let xyz else { return nil }; return .init(timestamp: timestamp, source: .sensorLogger, rotationRate: .init(x: xyz.0, y: xyz.1, z: xyz.2))
            case .gravity:
                guard let xyz else { return nil }; return .init(timestamp: timestamp, source: .sensorLogger, gravity: .init(x: xyz.0, y: xyz.1, z: xyz.2))
            case .location:
                guard coordinate != nil else { return nil }; return .init(timestamp: timestamp, source: .sensorLogger, coordinate: coordinate, speedMps: value(row, ["speed_mps", "speed", "속도"]))
            case .combined:
                guard let xyz else { return nil }; return .init(timestamp: timestamp, source: .sensorLogger, acceleration: .init(x: xyz.0, y: xyz.1, z: xyz.2), rotationRate: rotation, vibrationRMS: value(row, ["vibration_rms", "rms", "진동"]), jerk: value(row, ["jerk", "jerk_mps3"]), coordinate: coordinate, speedMps: value(row, ["speed_mps", "speed", "속도"]))
            }
        }
        guard !samples.isEmpty else { throw CSVError.noValidRows }
        return samples.sorted { $0.timestamp < $1.timestamp }
    }
}

public enum SensorLogEmulator {
    public enum Profile: Sendable { case smooth, rough, impact }
    public static func samples(profile: Profile, duration: TimeInterval = 20, sampleRateHz: Double = 50) -> [RoadSurfaceSensorSample] {
        let count = max(1, Int(duration * sampleRateHz))
        return (0..<count).map { index in
            let time = Double(index) / sampleRateHz, wave = sin(time * 30)
            let amplitude = profile == .smooth ? 0.3 : 2.75
            let impact = profile == .impact && index == count / 2 ? 26.5 : 0
            return .init(timestamp: time, source: .sensorLogger, acceleration: .init(x: amplitude * sin(time * 11), y: amplitude * cos(time * 17), z: 9.80665 + amplitude * wave + impact), rotationRate: .init(x: amplitude / 10, y: amplitude / 20, z: amplitude / 30), vibrationRMS: abs(amplitude * wave) + impact, jerk: index == count / 2 ? impact * sampleRateHz : amplitude * 30)
        }
    }
}

public final class SensorLogReplayCollector: SensorCollector, @unchecked Sendable {
    private let lock = NSLock(), samples: [RoadSurfaceSensorSample], chunkDurationSec: TimeInterval
    private var listeners: [UUID: @Sendable (SensorChunk) -> Void] = [:], running = false, paused = false, sessionID = ""
    public var isRunning: Bool { lock.withLock { running } }
    public init(samples: [RoadSurfaceSensorSample], chunkDurationSec: TimeInterval = 5) { self.samples = samples; self.chunkDurationSec = chunkDurationSec }
    public func start(sessionId: String, profileId: String) throws {
        try lock.withLock { guard !running else { throw SensorCollectionError.alreadyRunning }; running = true; paused = false; sessionID = sessionId }
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.emitAll() }
    }
    public func stop() { lock.withLock { running = false; paused = false } }
    public func pause() { lock.withLock { paused = true } }
    public func resume() { lock.withLock { paused = false } }
    public func readiness() -> SensorReadiness { .init(accelerometerAvailable: true, gyroscopeAvailable: true, motionAvailable: true, isCollecting: lock.withLock { running && !paused }, effectiveHz: 50, sampleCount: samples.count) }
    public func subscribe(_ listener: @escaping @Sendable (SensorChunk) -> Void) -> Unsubscribe { let id = UUID(); lock.withLock { listeners[id] = listener }; return { [weak self] in self?.lock.withLock { self?.listeners[id] = nil } } }
    public func emitAll() {
        guard let first = samples.first else { return }
        let groups = Dictionary(grouping: samples) { Int(($0.timestamp - first.timestamp) / chunkDurationSec) }
        for key in groups.keys.sorted() {
            guard let values = groups[key], lock.withLock({ running && !paused }) else { return }
            let payload = (try? JSONEncoder().encode(values)) ?? Data(), base = Date()
            let chunk = SensorChunk(sessionId: lock.withLock { sessionID }, chunkSeq: key + 1, startedAt: base.addingTimeInterval(values.first!.timestamp - first.timestamp), endedAt: base.addingTimeInterval(values.last!.timestamp - first.timestamp), checksum: "sensor-log-\(key + 1)-\(values.count)", sampleCount: values.count, clientEventId: "sensor-log-\(key + 1)", isSimulated: true, payload: payload)
            lock.withLock { Array(listeners.values) }.forEach { $0(chunk) }
        }
    }
}

private func zip2(_ a: Double?, _ b: Double?) -> (Double, Double)? { guard let a, let b else { return nil }; return (a, b) }
private func zip3(_ a: Double?, _ b: Double?, _ c: Double?) -> (Double, Double, Double)? { guard let a, let b, let c else { return nil }; return (a, b, c) }
