import Foundation
import Testing
@testable import R2DCore

private actor RiskRepositorySpy: IRiskLayerRepository {
    var value: RiskLayerSnapshot, routeIDs: [String] = [], viewportCount = 0, shouldFail = false, delay: Duration = .zero
    init(_ value: RiskLayerSnapshot) { self.value = value }
    func fetchCells(boundingBox: GeoBoundingBox, zoomLevel: Int?, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { viewportCount += 1; if shouldFail { throw RiskLayerError.offline }; try await Task.sleep(for: delay); return value }
    func fetchCells(along route: Route, corridorWidthM: Double, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { routeIDs.append(route.id); if shouldFail { throw RiskLayerError.offline }; try await Task.sleep(for: delay); return knownLayerVersion == value.layerVersion ? .init(layerVersion: value.layerVersion, generatedAt: value.generatedAt, expiresAt: value.expiresAt, cells: [], notModified: true) : value }
    func fetchCell(id: String) async throws -> RoadCell { try #require(value.cells.first) }
    func configure(value: RiskLayerSnapshot? = nil, fail: Bool? = nil, delay: Duration? = nil) { if let value { self.value = value }; if let fail { shouldFail = fail }; if let delay { self.delay = delay } }
    func counts() -> ([String], Int) { (routeIDs, viewportCount) }
}
private struct RiskFixedClock: Clock { let value: Date; func now() -> Date { value } }
private func syncCell(layer: String = "v1") -> RoadCell { .init(id: "sync-cell", geometry: .point(.init(latitude: 37.5502, longitude: 127.04)), dataState: .verified, riskState: .confirmedDamage, riskScore: 90, confidence: 0.95, lastObservedAt: nil, validUntil: nil, observationCount: 4, independentDeviceCount: 2, cellVersion: "c1", layerVersion: layer) }
private func syncSnapshot(version: String = "v1", expires: Date? = Date(timeIntervalSince1970: 2_000)) -> RiskLayerSnapshot { .init(layerVersion: version, generatedAt: Date(timeIntervalSince1970: 900), expiresAt: expires, cells: [syncCell(layer: version)]) }
private func syncRoute(id: String = "route-1") -> Route { .init(id: id, polyline: [.init(latitude: 37.55, longitude: 127.04), .init(latitude: 37.56, longitude: 127.04)], totalDistance: 1000, totalDuration: 200, turnList: [], riskCells: []) }

@Test func routeSelectionSyncsAndPersistsSnapshot() async {
    let repository = RiskRepositorySpy(syncSnapshot()), cache = InMemoryRiskLayerCache(), worker = RiskLayerSyncWorker(repository: repository, cache: cache)
    await worker.syncRoute(syncRoute()); #expect(await worker.cachedSnapshot()?.layerVersion == "v1"); #expect((try? await cache.load(.route)) != nil); #expect(await repository.counts().0 == ["route-1"])
}

@Test func identicalVersionDoesNotRequestAgain() async {
    let repository = RiskRepositorySpy(syncSnapshot()), worker = RiskLayerSyncWorker(repository: repository, cache: InMemoryRiskLayerCache())
    await worker.syncRoute(syncRoute()); await worker.syncIfVersionChanged("v1"); #expect(await repository.counts().0.count == 1)
}

@Test func concurrentRouteRequestsAreCoalesced() async {
    let repository = RiskRepositorySpy(syncSnapshot()); await repository.configure(delay: .milliseconds(50)); let worker = RiskLayerSyncWorker(repository: repository, cache: InMemoryRiskLayerCache())
    async let first: Void = worker.syncRoute(syncRoute()); async let second: Void = worker.syncRoute(syncRoute()); _ = await (first, second); #expect(await repository.counts().0.count == 1)
}

@Test func changedProgressVersionFetchesNewLayer() async {
    let repository = RiskRepositorySpy(syncSnapshot()), worker = RiskLayerSyncWorker(repository: repository, cache: InMemoryRiskLayerCache())
    await worker.syncRoute(syncRoute()); await repository.configure(value: syncSnapshot(version: "v2")); await worker.syncIfVersionChanged("v2")
    #expect(await worker.cachedSnapshot()?.layerVersion == "v2"); #expect(await repository.counts().0.count == 2)
}

@Test func foregroundRefreshesExpiredSnapshot() async {
    let repository = RiskRepositorySpy(syncSnapshot(expires: Date(timeIntervalSince1970: 950))), worker = RiskLayerSyncWorker(repository: repository, cache: InMemoryRiskLayerCache(), clock: RiskFixedClock(value: Date(timeIntervalSince1970: 1_000)))
    await worker.syncRoute(syncRoute()); await repository.configure(value: syncSnapshot(version: "v2")); await worker.refreshIfStale(); #expect(await repository.counts().0.count == 2)
}

@Test func foregroundRetriesVersionThatFailedWithoutPollingDuplicates() async {
    let repository = RiskRepositorySpy(syncSnapshot()), worker = RiskLayerSyncWorker(repository: repository, cache: InMemoryRiskLayerCache())
    await worker.syncRoute(syncRoute()); await repository.configure(value: syncSnapshot(version: "v2"), fail: true); await worker.syncIfVersionChanged("v2"); await worker.syncIfVersionChanged("v2")
    #expect(await repository.counts().0.count == 2)
    await repository.configure(fail: false); await worker.refreshIfStale(); #expect(await repository.counts().0.count == 3); #expect(await worker.cachedSnapshot()?.layerVersion == "v2")
}

@Test func offlineStartUsesPersistentCacheAndFailureKeepsIt() async throws {
    let cache = InMemoryRiskLayerCache(), cached = syncSnapshot(); try await cache.save(cached, context: .route)
    let repository = RiskRepositorySpy(syncSnapshot(version: "v2")); await repository.configure(fail: true); let worker = RiskLayerSyncWorker(repository: repository, cache: cache)
    await worker.start(); await worker.syncRoute(syncRoute()); #expect(await worker.cachedSnapshot() == cached)
}

@Test func rerouteFetchesNewCorridorAndFinishClearsContext() async {
    let repository = RiskRepositorySpy(syncSnapshot()), worker = RiskLayerSyncWorker(repository: repository, cache: InMemoryRiskLayerCache())
    await worker.syncRoute(syncRoute()); await repository.configure(value: syncSnapshot(version: "v2")); await worker.syncRoute(syncRoute(id: "route-2")); await worker.clearRouteContext(); await repository.configure(value: syncSnapshot(version: "v3")); await worker.syncIfVersionChanged("v3")
    #expect(await repository.counts().0 == ["route-1", "route-2"])
}

@Test func viewportSyncIsIndependentAndCached() async {
    let repository = RiskRepositorySpy(syncSnapshot()), cache = InMemoryRiskLayerCache(), worker = RiskLayerSyncWorker(repository: repository, cache: cache)
    await worker.syncViewport(.init(minLatitude: 37, minLongitude: 127, maxLatitude: 38, maxLongitude: 128), zoomLevel: 14)
    #expect(await repository.counts().1 == 1); #expect((try? await cache.load(.viewport)) != nil)
}
