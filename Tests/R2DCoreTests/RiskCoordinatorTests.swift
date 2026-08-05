import Foundation
import Testing
@testable import R2DCore

private actor CoordinatorRiskRepository: IRiskLayerRepository {
    var snapshot: RiskLayerSnapshot, fail = false, routeFetches = 0
    init(_ snapshot: RiskLayerSnapshot) { self.snapshot = snapshot }
    func fetchCells(boundingBox: GeoBoundingBox, zoomLevel: Int?, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { if fail { throw RiskLayerError.offline }; return snapshot }
    func fetchCells(along route: Route, corridorWidthM: Double, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { routeFetches += 1; if fail { throw RiskLayerError.offline }; return knownLayerVersion == snapshot.layerVersion ? .init(layerVersion: snapshot.layerVersion, generatedAt: snapshot.generatedAt, expiresAt: snapshot.expiresAt, cells: [], notModified: true) : snapshot }
    func fetchCell(id: String) async throws -> RoadCell { snapshot.cells[0] }
    func configure(_ snapshot: RiskLayerSnapshot? = nil, fail: Bool? = nil) { if let snapshot { self.snapshot = snapshot }; if let fail { self.fail = fail } }
    func count() -> Int { routeFetches }
}
private final class CoordinatorProgressRepository: IRideProgressRepository, @unchecked Sendable {
    private let lock = NSLock(); var riskVersion: String?
    init(_ version: String?) { riskVersion = version }
    func fetchRideProgress(rideId: String) async throws -> RideProgress { .init(validDistance: 0, confirmedDistance: 0, processingChunks: 0, acknowledgedChunks: 0, remainingChunks: 0) }
    func fetchBossProgress(rideId: String) async throws -> BossProgress? { .init(bossHP: 100, confirmedDamage: 0, pendingDamage: 0, processingState: .confirmed) }
    func fetchRewardProgress(rideId: String) async throws -> RewardProgress { .init(pendingReward: 0, confirmedReward: 0) }
    func fetchRiskLayerVersion(rideId: String) async throws -> String? { lock.withLock { riskVersion } }
    func setVersion(_ value: String?) { lock.withLock { riskVersion = value } }
}
private let coordinatorOrigin = Coordinate(latitude: 37.55, longitude: 127.04)
private func coordinatorRoute() -> Route { .init(id: "risk-route", polyline: [coordinatorOrigin, .init(latitude: 37.552, longitude: 127.04)], totalDistance: 222, totalDuration: 60, turnList: [.init(coordinate: .init(latitude: 37.552, longitude: 127.04), instruction: "도착", distance: 222)], riskCells: [.init(id: "unverified-route-hint", geometry: "POINT(127.04 37.5502)", riskScore: 1, confidence: 1)]) }
private func coordinatorSnapshot(version: String = "v1", cells: [RoadCell]? = nil) -> RiskLayerSnapshot {
    let value = RoadCell(id: "server-cell", geometry: .point(.init(latitude: 37.55025, longitude: 127.04)), dataState: .verified, riskState: .confirmedDamage, riskScore: 95, confidence: 0.96, lastObservedAt: nil, validUntil: nil, observationCount: 8, independentDeviceCount: 3, cellVersion: "c1", layerVersion: version)
    return .init(layerVersion: version, generatedAt: Date(timeIntervalSince1970: 1_000), expiresAt: Date(timeIntervalSince1970: 2_000_000_000), cells: cells ?? [value])
}

@MainActor private func riskCoordinator(repository: CoordinatorRiskRepository, progress: CoordinatorProgressRepository = .init("v1"), location: MockLocationTracker = .init()) -> ActiveRideCoordinator {
    let worker = RiskLayerSyncWorker(repository: repository, cache: InMemoryRiskLayerCache())
    return ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: location, sensors: MockSensorCollector(), routes: MockRouteRepository(), riskLayerWorker: worker, queue: MemoryTelemetryQueue(), progress: progress)
}

@Test @MainActor func routeSelectionSyncsVerifiedRiskAndOnlyReplacesRiskLayer() async throws {
    let repository = CoordinatorRiskRepository(coordinatorSnapshot()), coordinator = riskCoordinator(repository: repository); let route = coordinatorRoute(); coordinator.selectRoute(route); try await Task.sleep(for: .milliseconds(30))
    let state = coordinator.getSnapshot(); #expect(await repository.count() == 1); #expect(state.mapState.route?.routeID == route.id); #expect(state.mapState.turns.count == 1); #expect(state.mapState.riskOverlays.map(\.id) == ["server-cell"]); #expect(!state.mapState.riskOverlays.contains { $0.id == "unverified-route-hint" })
}

@Test @MainActor func locationUpdateEvaluatesWarningAndGameKeepsSafetyState() async throws {
    let repository = CoordinatorRiskRepository(coordinatorSnapshot()), location = MockLocationTracker(), coordinator = riskCoordinator(repository: repository, location: location); coordinator.selectRoute(coordinatorRoute()); _ = try coordinator.prepare(); _ = try coordinator.start(); try await Task.sleep(for: .milliseconds(30))
    location.simulate(.init(coordinate: coordinatorOrigin, speedMps: 6, heading: 0, mapMatchConfidence: 0.95)); try await Task.sleep(for: .milliseconds(20)); #expect(coordinator.getSnapshot().roadWarning?.cellID == "server-cell")
    coordinator.switchView(.game); #expect(coordinator.getSnapshot().roadWarning?.cellID == "server-cell"); #expect(coordinator.getSnapshot().session?.state == .active)
}

@Test @MainActor func progressVersionChangeTriggersRiskSyncOnlyWhenChanged() async throws {
    let risk = CoordinatorRiskRepository(coordinatorSnapshot()), progress = CoordinatorProgressRepository("v1"), coordinator = riskCoordinator(repository: risk, progress: progress); coordinator.selectRoute(coordinatorRoute()); _ = try coordinator.prepare(); _ = try coordinator.start(); try await Task.sleep(for: .milliseconds(30)); let initial = await risk.count()
    await coordinator.sync(); try await Task.sleep(for: .milliseconds(20)); #expect(await risk.count() == initial)
    await risk.configure(coordinatorSnapshot(version: "v2")); progress.setVersion("v2"); await coordinator.sync(); try await Task.sleep(for: .milliseconds(30)); #expect(await risk.count() == initial + 1); #expect(coordinator.getSnapshot().riskLayerVersion == "v2")
}

@Test @MainActor func riskFailureDoesNotEndRideAndKeepsCachedOverlay() async throws {
    let risk = CoordinatorRiskRepository(coordinatorSnapshot()), progress = CoordinatorProgressRepository("v1"), coordinator = riskCoordinator(repository: risk, progress: progress); coordinator.selectRoute(coordinatorRoute()); _ = try coordinator.prepare(); _ = try coordinator.start(); try await Task.sleep(for: .milliseconds(30)); let overlays = coordinator.getSnapshot().mapState.riskOverlays
    await risk.configure(coordinatorSnapshot(version: "v2"), fail: true); progress.setVersion("v2"); await coordinator.sync(); try await Task.sleep(for: .milliseconds(30))
    #expect(coordinator.getSnapshot().session?.state == .active); #expect(coordinator.getSnapshot().mapState.riskOverlays == overlays)
}

@Test @MainActor func emptySnapshotClearsOnlyRiskOverlays() async throws {
    let risk = CoordinatorRiskRepository(coordinatorSnapshot()), coordinator = riskCoordinator(repository: risk); coordinator.selectRoute(coordinatorRoute()); try await Task.sleep(for: .milliseconds(30)); let route = coordinator.getSnapshot().mapState.route, turns = coordinator.getSnapshot().mapState.turns
    await risk.configure(coordinatorSnapshot(version: "v2", cells: [])); await coordinator.syncRiskViewport(.init(minLatitude: 37, minLongitude: 127, maxLatitude: 38, maxLongitude: 128), zoomLevel: 14)
    #expect(coordinator.getSnapshot().mapState.riskOverlays.isEmpty); #expect(coordinator.getSnapshot().mapState.route == route); #expect(coordinator.getSnapshot().mapState.turns == turns)
}

@Test @MainActor func finishClearsWarningAndRiskContext() async throws {
    let repository = CoordinatorRiskRepository(coordinatorSnapshot()), location = MockLocationTracker(), coordinator = riskCoordinator(repository: repository, location: location); coordinator.selectRoute(coordinatorRoute()); _ = try coordinator.prepare(); _ = try coordinator.start(); try await Task.sleep(for: .milliseconds(30)); location.simulate(.init(coordinate: coordinatorOrigin, speedMps: 6, heading: 0, mapMatchConfidence: 0.95)); try await Task.sleep(for: .milliseconds(20)); _ = try await coordinator.finish()
    #expect(coordinator.getSnapshot().roadWarning == nil); #expect(coordinator.getSnapshot().riskLayerSnapshot == nil); #expect(coordinator.getSnapshot().mapState == .empty)
}
