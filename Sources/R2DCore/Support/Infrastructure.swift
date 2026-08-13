import Foundation

public final class MemoryRideSessionRepository: RideSessionRepository, @unchecked Sendable {
    private let lock = NSLock(); private var stored: RideSession?
    private let ids: IdGenerator
    public init(ids: IdGenerator = UUIDGenerator()) { self.ids = ids }
    public func create(routeId: String, boss: BossContext?) throws -> RideSession {
        lock.lock(); defer { lock.unlock() }
        if let stored, [.created, .ready, .active, .paused, .finishing].contains(stored.state) { throw RideError.activeSessionExists }
        let value = RideSession(id: ids.next(), routeId: routeId, bossContext: boss); stored = value; return value
    }
    public func active() -> RideSession? { lock.withLock { stored } }
    public func save(_ session: RideSession) throws { lock.withLock { stored = session } }
}

public final class FileRideSessionRepository: RideSessionRepository, @unchecked Sendable {
    private let lock = NSLock(), fileURL: URL, ids: IdGenerator
    private var stored: RideSession?
    public init(fileURL: URL, ids: IdGenerator = UUIDGenerator()) throws {
        self.fileURL = fileURL; self.ids = ids
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) { stored = try JSONDecoder().decode(RideSession.self, from: Data(contentsOf: fileURL)) }
    }
    public func create(routeId: String, boss: BossContext?) throws -> RideSession {
        try lock.withLock {
            if let stored, [.created, .ready, .active, .paused, .finishing].contains(stored.state) { throw RideError.activeSessionExists }
            let session = RideSession(id: ids.next(), routeId: routeId, bossContext: boss); stored = session; try persist(session); return session
        }
    }
    public func active() -> RideSession? { lock.withLock { stored } }
    public func save(_ session: RideSession) throws { try lock.withLock { stored = session; try persist(session) } }
    private func persist(_ session: RideSession) throws { try JSONEncoder().encode(session).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen]) }
}

public final class MemoryTelemetryQueue: TelemetryQueue, @unchecked Sendable {
    private let lock = NSLock(); private var chunks: [SensorChunk] = []
    public init() {}
    public func enqueue(_ chunk: SensorChunk) throws { lock.withLock { if !chunks.contains(where: { $0.sessionId == chunk.sessionId && $0.chunkSeq == chunk.chunkSeq }) { chunks.append(chunk) } } }
    public func pending(sessionId: String) -> [SensorChunk] { lock.withLock { chunks.filter { $0.sessionId == sessionId }.sorted { $0.chunkSeq < $1.chunkSeq } } }
    public func acknowledge(sessionId: String, through sequence: Int) throws { lock.withLock { chunks.removeAll { $0.sessionId == sessionId && $0.chunkSeq <= sequence } } }
}

public final class MockLocationTracker: LocationTracker, @unchecked Sendable {
    private let lock = NSLock(); private var listeners: [UUID: @Sendable (LocationSnapshot) -> Void] = [:]
    public private(set) var snapshot: LocationSnapshot = .empty
    public private(set) var isRunning = false; private var paused = false
    public init() {}
    public func start(sessionId: String) throws { isRunning = true; paused = false }
    public func stop() { isRunning = false }
    public func pause() { paused = true }; public func resume() { paused = false }
    public func subscribe(_ listener: @escaping @Sendable (LocationSnapshot) -> Void) -> Unsubscribe {
        let id = UUID(); lock.withLock { listeners[id] = listener }
        return { [weak self] in self?.lock.withLock { self?.listeners[id] = nil } }
    }
    public func readiness() -> LocationReadiness { .init(servicesEnabled: true, authorization: .authorizedWhenInUse, isAccuracySufficient: true) }
    public func requestAuthorization() {}
    public func simulate(_ value: LocationSnapshot) {
        guard isRunning, !paused else { return }; snapshot = value
        let current = lock.withLock { Array(listeners.values) }; current.forEach { $0(value) }
    }
}

public final class MockSensorCollector: SensorCollector, @unchecked Sendable {
    private let lock = NSLock(); private var listeners: [UUID: @Sendable (SensorChunk) -> Void] = [:]
    public private(set) var isRunning = false; private var paused = false
    public init() {}
    public func start(sessionId: String, profileId: String) throws { isRunning = true; paused = false }
    public func stop() { isRunning = false }; public func pause() { paused = true }; public func resume() { paused = false }
    public func subscribe(_ listener: @escaping @Sendable (SensorChunk) -> Void) -> Unsubscribe {
        let id = UUID(); lock.withLock { listeners[id] = listener }; return { [weak self] in self?.lock.withLock { self?.listeners[id] = nil } }
    }
    public func readiness() -> SensorReadiness { .init(accelerometerAvailable: true, gyroscopeAvailable: true, motionAvailable: true, isCollecting: isRunning) }
    public func simulate(_ chunk: SensorChunk) { guard isRunning, !paused else { return }; lock.withLock { Array(listeners.values) }.forEach { $0(chunk) } }
}

public struct MockRouteRepository: IRouteRepository {
    public init() {}
    public func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] { [makeRoute(id: "route-fast", origin: origin, destination: destination)] }
    public func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route { makeRoute(id: "\(route.id)-reroute", origin: currentLocation, destination: route.polyline.last ?? currentLocation) }
    public func cancelSearch() async {}
    private func makeRoute(id: String, origin: Coordinate, destination: Coordinate) -> Route {
        let middle = Coordinate(latitude: (origin.latitude + destination.latitude) / 2, longitude: (origin.longitude + destination.longitude) / 2)
        let distance = infrastructureDistance(origin, middle) + infrastructureDistance(middle, destination)
        return .init(id: id, polyline: [origin, middle, destination], totalDistance: distance, totalDuration: max(60, distance / 5), turnList: [.init(coordinate: middle, instruction: "경로를 따라 직진", distance: distance / 2), .init(coordinate: destination, instruction: "목적지에 도착", distance: distance / 2)], riskCells: [.init(id: "risk-preview", geometry: "POINT(\(middle.longitude) \(middle.latitude))", riskScore: 0.25, confidence: 0.9)])
    }
}

private func infrastructureDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
    let dy = (b.latitude - a.latitude) * 111_320, dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * .pi / 180)
    return sqrt(dx * dx + dy * dy)
}

public actor InMemoryRiskLayerCache: IRiskLayerCache {
    private var values: [RiskLayerCacheContext: RiskLayerSnapshot] = [:]
    public init() {}
    public func load(_ context: RiskLayerCacheContext) async throws -> RiskLayerSnapshot? { values[context] }
    public func save(_ snapshot: RiskLayerSnapshot, context: RiskLayerCacheContext) async throws { values[context] = snapshot }
}

public actor MockRiskLayerRepository: IRiskLayerRepository {
    public var snapshot: RiskLayerSnapshot
    public init(snapshot: RiskLayerSnapshot = .init(layerVersion: "mock-risk-v1", generatedAt: Date(timeIntervalSince1970: 1_700_000_000), expiresAt: Date(timeIntervalSince1970: 2_000_000_000), cells: [])) { self.snapshot = snapshot }
    public func fetchCells(boundingBox: GeoBoundingBox, zoomLevel: Int?, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { knownLayerVersion == snapshot.layerVersion ? .init(layerVersion: snapshot.layerVersion, generatedAt: snapshot.generatedAt, expiresAt: snapshot.expiresAt, cells: [], notModified: true) : snapshot }
    public func fetchCells(along route: Route, corridorWidthM: Double, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { knownLayerVersion == snapshot.layerVersion ? .init(layerVersion: snapshot.layerVersion, generatedAt: snapshot.generatedAt, expiresAt: snapshot.expiresAt, cells: [], notModified: true) : snapshot }
    public func fetchCell(id: String) async throws -> RoadCell { guard let cell = snapshot.cells.first(where: { $0.id == id }) else { throw RiskLayerError.invalidResponse }; return cell }
}

public final class MockProgressServer: IRideProgressRepository, @unchecked Sendable {
    private let lock = NSLock()
    public var rideProgress = RideProgress(validDistance: 0, confirmedDistance: 0, processingChunks: 0, acknowledgedChunks: 0, remainingChunks: 0)
    public var bossProgress: BossProgress? = .init(bossHP: 100, confirmedDamage: 0, pendingDamage: 0, processingState: .confirmed)
    public var rewardProgress = RewardProgress(pendingReward: 0, confirmedReward: 0)
    public var riskLayerVersion: String? = "layer-2026-08"
    public init() {}
    public func fetchRideProgress(rideId: String) async throws -> RideProgress { lock.withLock { rideProgress } }
    public func fetchBossProgress(rideId: String) async throws -> BossProgress? { lock.withLock { bossProgress } }
    public func fetchRewardProgress(rideId: String) async throws -> RewardProgress { lock.withLock { rewardProgress } }
    public func fetchRiskLayerVersion(rideId: String) async throws -> String? { lock.withLock { riskLayerVersion } }
}
