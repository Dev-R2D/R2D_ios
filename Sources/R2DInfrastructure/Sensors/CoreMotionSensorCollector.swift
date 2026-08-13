#if os(iOS) && canImport(CoreMotion)
import CoreMotion
import Foundation
import R2DCore

public struct SensorCollectionConfiguration: Sendable {
    public let accelerometerHz: Double, gyroscopeHz: Double, chunkDurationSec: Double, qualitySnapshotIntervalSec: Double, maximumBufferDurationSec: Double
    public init(accelerometerHz: Double = 100, gyroscopeHz: Double = 50, chunkDurationSec: Double = 5, qualitySnapshotIntervalSec: Double = 1, maximumBufferDurationSec: Double = 30) {
        self.accelerometerHz = accelerometerHz; self.gyroscopeHz = gyroscopeHz; self.chunkDurationSec = chunkDurationSec; self.qualitySnapshotIntervalSec = qualitySnapshotIntervalSec; self.maximumBufferDurationSec = maximumBufferDurationSec
    }
}

// CMMotionManager and OperationQueue are not Sendable. All buffer state is guarded by lock and only immutable chunks cross the boundary.
public final class CoreMotionSensorCollector: SensorCollector, @unchecked Sendable {
    private static let standardGravity = 9.80665
    private let manager: CMMotionManager, configuration: SensorCollectionConfiguration, operationQueue: OperationQueue, lock = NSLock()
    private var listeners: [UUID: @Sendable (SensorChunk) -> Void] = [:], running = false, paused = false
    private var sessionId = "", sequence = 0, sampleCount = 0, chunkStartedAt: Date?, lastSampleAt: Date?
    private var samples: [RoadSurfaceSensorSample] = []
    public var isRunning: Bool { lock.withLock { running } }
    public init(configuration: SensorCollectionConfiguration = .init(), manager: CMMotionManager = CMMotionManager()) {
        self.configuration = configuration; self.manager = manager; operationQueue = OperationQueue(); operationQueue.name = "app.r2d.motion"; operationQueue.maxConcurrentOperationCount = 1
    }
    public func readiness() -> SensorReadiness { lock.withLock { .init(accelerometerAvailable: manager.isAccelerometerAvailable, gyroscopeAvailable: manager.isGyroAvailable, motionAvailable: manager.isDeviceMotionAvailable, isCollecting: running && !paused, effectiveHz: effectiveHz(), sampleCount: sampleCount, lastSampleAt: lastSampleAt) } }
    public func start(sessionId: String, profileId: String) throws {
        guard manager.isAccelerometerAvailable || manager.isGyroAvailable || manager.isDeviceMotionAvailable else { throw SensorCollectionError.motionUnavailable }
        try lock.withLock { guard !running else { throw SensorCollectionError.alreadyRunning }; running = true; paused = false; self.sessionId = sessionId; sequence = 0; sampleCount = 0; chunkStartedAt = Date() }
        beginUpdates()
    }
    public func stop() { flush(); lock.withLock { running = false; paused = false }; manager.stopAccelerometerUpdates(); manager.stopGyroUpdates(); manager.stopDeviceMotionUpdates() }
    public func pause() { flush(); lock.withLock { paused = true }; manager.stopAccelerometerUpdates(); manager.stopGyroUpdates(); manager.stopDeviceMotionUpdates() }
    public func resume() { guard lock.withLock({ running }) else { return }; lock.withLock { paused = false; chunkStartedAt = Date() }; beginUpdates() }
    public func subscribe(_ listener: @escaping @Sendable (SensorChunk) -> Void) -> Unsubscribe { let id = UUID(); lock.withLock { listeners[id] = listener }; return { [weak self] in self?.lock.withLock { self?.listeners[id] = nil } } }
    private func beginUpdates() {
        if manager.isAccelerometerAvailable { manager.accelerometerUpdateInterval = 1 / configuration.accelerometerHz; manager.startAccelerometerUpdates(to: operationQueue) { [weak self] data, _ in guard let data else { return }; let g = Self.standardGravity; self?.recordSample(.init(timestamp: data.timestamp, source: .accelerometer, acceleration: .init(x: data.acceleration.x * g, y: data.acceleration.y * g, z: data.acceleration.z * g))) } }
        if manager.isGyroAvailable { manager.gyroUpdateInterval = 1 / configuration.gyroscopeHz; manager.startGyroUpdates(to: operationQueue) { [weak self] data, _ in guard let data else { return }; self?.recordSample(.init(timestamp: data.timestamp, source: .gyroscope, rotationRate: .init(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z))) } }
        if manager.isDeviceMotionAvailable { manager.deviceMotionUpdateInterval = 1 / configuration.gyroscopeHz; manager.startDeviceMotionUpdates(to: operationQueue) { [weak self] data, _ in guard let data else { return }; let g = Self.standardGravity; self?.recordSample(.init(timestamp: data.timestamp, source: .deviceMotion, rotationRate: .init(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z), gravity: .init(x: data.gravity.x * g, y: data.gravity.y * g, z: data.gravity.z * g))) } }
    }
    private func recordSample(_ sample: RoadSurfaceSensorSample, now: Date = Date()) {
        guard lock.withLock({ running && !paused }) else { return }
        var shouldFlush = false; lock.withLock { sampleCount += 1; samples.append(sample); let maximumSamples = Int(configuration.maximumBufferDurationSec * (configuration.accelerometerHz + configuration.gyroscopeHz * 2)); if samples.count > maximumSamples { samples.removeFirst(samples.count - maximumSamples) }; lastSampleAt = now; shouldFlush = chunkStartedAt.map { now.timeIntervalSince($0) >= configuration.chunkDurationSec } ?? false }
        if shouldFlush { flush(at: now) }
    }
    private func flush(at end: Date = Date()) {
        var delivery: (SensorChunk, [@Sendable (SensorChunk) -> Void])?
        lock.withLock {
            guard let start = chunkStartedAt, sampleCount > 0 else { chunkStartedAt = end; return }
            sequence += 1; let payload = (try? JSONEncoder().encode(samples)) ?? Data(); let chunk = SensorChunk(sessionId: sessionId, chunkSeq: sequence, startedAt: start, endedAt: end, checksum: "motion-\(sequence)-\(sampleCount)", sampleCount: sampleCount, clientEventId: UUID().uuidString, isSimulated: false, payload: payload)
            delivery = (chunk, Array(listeners.values)); sampleCount = 0; samples.removeAll(keepingCapacity: true); chunkStartedAt = end
        }
        if let delivery { delivery.1.forEach { $0(delivery.0) } }
    }
    private func effectiveHz() -> Double { guard let start = chunkStartedAt else { return 0 }; let duration = Date().timeIntervalSince(start); return duration > 0 ? Double(sampleCount) / duration : 0 }
}
#endif
