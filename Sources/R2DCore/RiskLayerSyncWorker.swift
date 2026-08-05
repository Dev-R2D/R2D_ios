import Foundation

public struct RiskLayerSyncConfiguration: Sendable {
    public let routeCorridorWidthM: Double
    public init(routeCorridorWidthM: Double = 35) { self.routeCorridorWidthM = routeCorridorWidthM }
}
public struct AppConfiguration: Sendable {
    public let riskLayerSync: RiskLayerSyncConfiguration, roadWarning: RoadWarningConfiguration
    public let features: FeatureFlags
    public init(riskLayerSync: RiskLayerSyncConfiguration = .init(), roadWarning: RoadWarningConfiguration = .init(), features: FeatureFlags = .production) { self.riskLayerSync = riskLayerSync; self.roadWarning = roadWarning; self.features = features }
}

public struct FeatureFlags: Equatable, Sendable {
    public let navigatorOnlyDemo: Bool, gameEnabled: Bool, gamePreviewOnly: Bool
    public let rewardEnabled: Bool, missionEnabled: Bool, liveLocationEnabled: Bool, replayLocationEnabled: Bool, liveServerEnabled: Bool, demoControlsEnabled: Bool
    public init(navigatorOnlyDemo: Bool, gameEnabled: Bool, gamePreviewOnly: Bool = false, rewardEnabled: Bool, missionEnabled: Bool, liveLocationEnabled: Bool, replayLocationEnabled: Bool, liveServerEnabled: Bool, demoControlsEnabled: Bool = false) {
        self.navigatorOnlyDemo = navigatorOnlyDemo; self.gameEnabled = gameEnabled; self.gamePreviewOnly = gamePreviewOnly; self.rewardEnabled = rewardEnabled; self.missionEnabled = missionEnabled; self.liveLocationEnabled = liveLocationEnabled; self.replayLocationEnabled = replayLocationEnabled; self.liveServerEnabled = liveServerEnabled; self.demoControlsEnabled = demoControlsEnabled
    }
    public static let production = Self(navigatorOnlyDemo: false, gameEnabled: true, rewardEnabled: true, missionEnabled: true, liveLocationEnabled: true, replayLocationEnabled: false, liveServerEnabled: true)
    public static let navigatorDemo = Self(navigatorOnlyDemo: true, gameEnabled: true, gamePreviewOnly: true, rewardEnabled: false, missionEnabled: false, liveLocationEnabled: false, replayLocationEnabled: true, liveServerEnabled: false, demoControlsEnabled: true)
}

public enum DemoReplayTarget: String, CaseIterable, Sendable { case start, risk, reroute, destination }
public protocol DemoReplayControlling: AnyObject, Sendable {
    var playbackSpeed: Double { get }
    func restart()
    func setPlaybackSpeed(_ speed: Double)
    func seek(to target: DemoReplayTarget)
}

public actor NoopRiskLayerSyncWorker: IRiskLayerSyncWorker {
    public init() {}
    public func start() async {}; public func stop() async {}; public func syncViewport(_ boundingBox: GeoBoundingBox, zoomLevel: Int?) async {}; public func syncRoute(_ route: Route) async {}; public func syncIfVersionChanged(_ layerVersion: String?) async {}; public func refreshIfStale() async {}; public func cachedSnapshot() async -> RiskLayerSnapshot? { nil }; public func updates() async -> AsyncStream<RiskLayerSnapshot> { AsyncStream { $0.finish() } }; public func clearRouteContext() async {}
}

public actor RiskLayerSyncWorker: IRiskLayerSyncWorker {
    private let repository: IRiskLayerRepository, cache: IRiskLayerCache, clock: Clock, configuration: RiskLayerSyncConfiguration
    private var snapshot: RiskLayerSnapshot?, activeRoute: Route?, activeRequestKey: String?
    private var pendingVersion: String?
    private var routeTask: Task<RiskLayerSnapshot?, Never>?, viewportTask: Task<RiskLayerSnapshot?, Never>?
    private var continuation: AsyncStream<RiskLayerSnapshot>.Continuation?
    public init(repository: IRiskLayerRepository, cache: IRiskLayerCache, clock: Clock = SystemClock(), configuration: RiskLayerSyncConfiguration = .init()) { self.repository = repository; self.cache = cache; self.clock = clock; self.configuration = configuration }
    public func updates() async -> AsyncStream<RiskLayerSnapshot> { AsyncStream { continuation in self.continuation = continuation } }
    public func start() async {
        if snapshot == nil {
            if let route = try? await cache.load(.route) { snapshot = route }
            else if let viewport = try? await cache.load(.viewport) { snapshot = viewport }
            if let snapshot { continuation?.yield(snapshot) }
        }
    }
    public func stop() async { routeTask?.cancel(); viewportTask?.cancel(); routeTask = nil; viewportTask = nil; activeRequestKey = nil }
    public func cachedSnapshot() async -> RiskLayerSnapshot? { snapshot }
    public func clearRouteContext() async { routeTask?.cancel(); routeTask = nil; activeRoute = nil; activeRequestKey = nil; pendingVersion = nil }

    public func syncViewport(_ boundingBox: GeoBoundingBox, zoomLevel: Int?) async {
        if let viewportTask { _ = await viewportTask.value; return }
        let repository = self.repository, known = snapshot?.layerVersion
        let task = Task<RiskLayerSnapshot?, Never> { try? await repository.fetchCells(boundingBox: boundingBox, zoomLevel: zoomLevel, knownLayerVersion: known) }
        viewportTask = task; let value = await task.value; viewportTask = nil; await accept(value, context: .viewport)
    }

    public func syncRoute(_ route: Route) async { activeRoute = route; await performRouteSync(versionHint: nil, force: true) }
    public func syncIfVersionChanged(_ layerVersion: String?) async {
        guard let layerVersion, layerVersion != snapshot?.layerVersion, let activeRoute else { return }
        pendingVersion = layerVersion; self.activeRoute = activeRoute; await performRouteSync(versionHint: layerVersion, force: false)
    }
    public func refreshIfStale() async {
        guard pendingVersion != nil || snapshot?.isStale(at: clock.now()) != false, let route = activeRoute else { return }
        activeRoute = route; await performRouteSync(versionHint: pendingVersion, force: true)
    }

    private func performRouteSync(versionHint: String?, force: Bool) async {
        guard let route = activeRoute else { return }
        let key = "\(route.id):\(versionHint ?? snapshot?.layerVersion ?? "none")"
        if let routeTask { _ = await routeTask.value; return }
        if !force, activeRequestKey == key { return }
        activeRequestKey = key
        let repository = self.repository, cache = self.cache, known = snapshot?.layerVersion, width = configuration.routeCorridorWidthM
        let task = Task<RiskLayerSnapshot?, Never> { try? await repository.fetchCells(along: route, corridorWidthM: width, knownLayerVersion: known) }
        routeTask = task; let value = await task.value; routeTask = nil
        if value == nil, snapshot == nil { snapshot = try? await cache.load(.route); if let snapshot { continuation?.yield(snapshot) } }
        else { await accept(value, context: .route) }
    }
    private func accept(_ value: RiskLayerSnapshot?, context: RiskLayerCacheContext) async {
        guard let value else { return }
        if value.notModified { return }
        snapshot = value; if pendingVersion == value.layerVersion { pendingVersion = nil }; try? await cache.save(value, context: context); continuation?.yield(value)
    }
}
