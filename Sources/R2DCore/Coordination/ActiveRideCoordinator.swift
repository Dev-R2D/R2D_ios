import Foundation

public struct RideConfiguration: Sendable {
    public var distanceStepM: Double = 100, baseDamagePerStep: Int = 1
    public init() {}
}

@MainActor
public final class ActiveRideCoordinator {
    public typealias Listener = (ActiveRideState) -> Void
    private let sessions: RideSessionRepository, location: LocationTracker, sensors: SensorCollector
    private let routes: IRouteRepository, navigationEngine: NavigationEngine, queue: TelemetryQueue, progressWorker: RideProgressSyncWorker, clock: Clock
    private let mapRenderer: IMapRenderer
    private let riskLayerWorker: IRiskLayerSyncWorker
    private let roadWarningOutput: IRoadWarningOutput
    private let evidenceRecorder: RideEvidenceRecording
    private let config: RideConfiguration
    private let telemetryPipeline: TelemetryPipeline?
    private var state = ActiveRideState.idle, listeners: [UUID: Listener] = [:]
    private var locationSubscription: Unsubscribe?, sensorSubscription: Unsubscribe?
    private var lastCoordinate: Coordinate?, roadWarningEngine: RoadWarningEngine

    public init(sessions: RideSessionRepository, location: LocationTracker, sensors: SensorCollector, routes: IRouteRepository, navigationEngine: NavigationEngine = .init(), mapRenderer: IMapRenderer = NoopMapRenderer(), riskLayerWorker: IRiskLayerSyncWorker = NoopRiskLayerSyncWorker(), roadWarningEngine: RoadWarningEngine = .init(), roadWarningOutput: IRoadWarningOutput = NoopRoadWarningOutput(), evidenceRecorder: RideEvidenceRecording = NoopRideEvidenceRecorder(), queue: TelemetryQueue, progress: IRideProgressRepository, telemetryPipeline: TelemetryPipeline? = nil, progressConfiguration: RideProgressSyncConfiguration = .init(), clock: Clock = SystemClock(), config: RideConfiguration = .init()) {
        self.sessions = sessions; self.location = location; self.sensors = sensors; self.routes = routes
        self.navigationEngine = navigationEngine; self.mapRenderer = mapRenderer; self.riskLayerWorker = riskLayerWorker; self.roadWarningEngine = roadWarningEngine; self.roadWarningOutput = roadWarningOutput; self.evidenceRecorder = evidenceRecorder; self.queue = queue; self.progressWorker = RideProgressSyncWorker(repository: progress, configuration: progressConfiguration); self.telemetryPipeline = telemetryPipeline; self.clock = clock; self.config = config
        locationSubscription = location.subscribe { [weak self] value in Task { @MainActor in self?.receive(location: value) } }
        sensorSubscription = sensors.subscribe { [weak self] chunk in Task { @MainActor in self?.receive(chunk: chunk) } }
        Task { [weak self, progressWorker] in
            let updates = await progressWorker.updates()
            for await snapshot in updates { await MainActor.run { self?.apply(snapshot) } }
        }
        if let telemetryPipeline {
            Task { [weak self] in await telemetryPipeline.setUploadAcknowledgementHandler { [weak self] _ in await self?.uploadDidSucceed() } }
        }
        Task { [weak self, riskLayerWorker] in
            await riskLayerWorker.start(); let updates = await riskLayerWorker.updates()
            for await snapshot in updates { await MainActor.run { self?.applyRiskLayer(snapshot) } }
        }
    }

    public func getSnapshot() -> ActiveRideState { state }
    public func refreshReadiness() {
        state.locationReadiness = location.readiness(); state.sensorReadiness = sensors.readiness(); publish()
    }
    public func requestLocationAuthorization() { location.requestAuthorization(); refreshReadiness() }
    public func startLocationPreview() {
        requestLocationAuthorization()
        try? location.start(sessionId: "location-preview")
        refreshReadiness()
    }
    @discardableResult public func subscribe(_ listener: @escaping Listener) -> Unsubscribe {
        let id = UUID(); listeners[id] = listener; listener(state)
        return { [weak self] in Task { @MainActor in self?.listeners[id] = nil } }
    }
    private func publish() { listeners.values.forEach { $0(state) } }

    public func searchRoutes(origin: Coordinate, destination: Coordinate, option: String? = nil) async throws {
        state.routes = try await routes.searchRoute(origin: origin, destination: destination, option: option); state.lastRiskLayerUpdate = clock.now(); publish()
    }
    public func searchRouteOptions(origin: Coordinate, destination: Coordinate, options: [String]) async throws {
        var results: [Route] = []
        for option in options {
            results.append(contentsOf: try await routes.searchRoute(origin: origin, destination: destination, option: option))
        }
        var seenRouteIDs = Set<String>()
        let uniqueResults = results.filter { seenRouteIDs.insert($0.id).inserted }
        state.routes = uniqueResults
        state.selectedRoute = uniqueResults.first
        state.lastRiskLayerUpdate = clock.now()
        publish()
    }
    public func loadRoutes(destination: String) async throws {
        let origin = state.location.coordinate ?? .init(latitude: 37.55, longitude: 127.04)
        try await searchRoutes(origin: origin, destination: .init(latitude: 37.56, longitude: 127.07))
    }
    public func cancelRouteSearch() async { await routes.cancelSearch() }
    public func selectRoute(_ route: Route) { state.selectedRoute = route; navigationEngine.setRoute(route); renderRouteOnMap(route, cameraMode: .fullRoute); publish(); Task { await syncRiskRoute(route) } }
    public func syncRiskViewport(_ boundingBox: GeoBoundingBox, zoomLevel: Int?) async { await riskLayerWorker.syncViewport(boundingBox, zoomLevel: zoomLevel); if let snapshot = await riskLayerWorker.cachedSnapshot() { applyRiskLayer(snapshot) } }
    public func showFullRoute() { guard let route = state.selectedRoute else { return }; renderRouteOnMap(route, cameraMode: .fullRoute); publish() }
    public func focusNextTurn() {
        guard let turn = state.navigationProgress?.nextTurn else { return }
        let camera = MapCameraState(center: turn.coordinate, latitudeDelta: 0.004, longitudeDelta: 0.004, heading: state.location.heading, mode: .nextTurn)
        state.mapState.camera = camera; mapRenderer.moveCamera(camera); publish()
    }

    @discardableResult public func prepare() throws -> RideSession {
        guard let route = state.selectedRoute else { throw RideError.routeNotSelected }
        var session = try sessions.create(routeId: route.routeId, boss: nil)
        try RideStateMachine.transition(&session, to: .ready, at: clock.now()); try sessions.save(session)
        state.session = session
        state.game = nil
        publish(); return session
    }

    public func injectExternalLocation(_ locationSnapshot: LocationSnapshot) {
        state.location = locationSnapshot
        state.mapState.currentLocation = locationSnapshot.coordinate
        if let coord = locationSnapshot.coordinate {
            let camera = MapCameraState(center: coord, latitudeDelta: 0.008, longitudeDelta: 0.008, heading: locationSnapshot.heading, mode: .automatic)
            state.mapState.camera = camera
            mapRenderer.showCurrentLocation(coord)
            mapRenderer.moveCamera(camera)
        }
        publish()
    }

    @discardableResult public func start() throws -> RideSession {
        guard var session = state.session else { throw RideError.noActiveRide }
        let locationStatus = location.readiness(), sensorStatus = sensors.readiness()
        guard locationStatus.canStart else { state.presentationError = locationStatus.authorization == .denied ? .locationPermissionRequired : .locationUnavailable; publish(); throw LocationTrackingError.authorizationDenied }
        guard sensorStatus.canStart else { state.presentationError = .sensorUnavailable; publish(); throw SensorCollectionError.motionUnavailable }
        try RideStateMachine.transition(&session, to: .active, at: clock.now())
        let startedAt = session.startedAt ?? clock.now()
        Task { await evidenceRecorder.startRide(rideId: session.id, routeId: session.routeId, startedAt: startedAt) }
        do {
            if !location.isRunning { try location.start(sessionId: session.id) }
            try sensors.start(sessionId: session.id, profileId: session.deviceProfileId)
        }
        catch { try? RideStateMachine.transition(&session, to: .aborted, at: clock.now()); try? sessions.save(session); state.session = session; publish(); throw error }
        try sessions.save(session); state.session = session; publish()
        Task { await progressWorker.startPolling(rideId: session.id) }
        return session
    }

    public func pause() throws {
        guard var session = state.session else { throw RideError.noActiveRide }
        try RideStateMachine.transition(&session, to: .paused, at: clock.now()); location.pause(); sensors.pause()
        try sessions.save(session); state.session = session; publish()
    }
    public func resume() throws {
        guard var session = state.session else { throw RideError.noActiveRide }
        try RideStateMachine.transition(&session, to: .active, at: clock.now()); location.resume(); sensors.resume()
        try sessions.save(session); state.session = session; publish()
    }
    public func switchView(_ view: ActiveRideView) { state.activeView = view; publish() }

    public func restore() throws -> RideSession? {
        guard let session = sessions.active(), ![.completed, .aborted].contains(session.state) else { return nil }
        state.session = session; state.selectedRoute = state.routes.first { $0.routeId == session.routeId }
        if let route = state.selectedRoute { navigationEngine.setRoute(route); renderRouteOnMap(route, cameraMode: .fullRoute) }
        if session.state == .active {
            if !location.isRunning { try location.start(sessionId: session.id) }
            if !sensors.isRunning { try sensors.start(sessionId: session.id, profileId: session.deviceProfileId) }
            Task { await progressWorker.startPolling(rideId: session.id) }
        }
        publish(); return session
    }
    public func persistSnapshot() throws { if let session = state.session { try sessions.save(session) } }

    public func sync() async {
        guard let session = state.session, session.state != .completed else { return }
        await telemetryPipeline?.triggerUpload()
        do { let snapshot = try await progressWorker.sync(rideId: session.id); apply(snapshot); state.connectionState = .online }
        catch { state.connectionState = .offline; publish() }
        await refreshTelemetrySummary()
    }

    public func finish() async throws -> RideSummary {
        guard var session = state.session else { throw RideError.noActiveRide }
        try RideStateMachine.transition(&session, to: .finishing, at: clock.now()); try sessions.save(session); state.session = session; publish()
        await telemetryPipeline?.flush(sessionID: session.id); await refreshTelemetrySummary()
        let snapshot = try await progressWorker.sync(rideId: session.id); apply(snapshot)
        let summary = RideSummary(sessionId: session.id, localDistanceM: session.localDistanceM, validDistanceM: snapshot.ride.validDistance, confirmedBaseDamage: snapshot.boss?.confirmedDamage ?? 0, confirmedDataDamage: 0, isFinal: snapshot.ride.remainingChunks == 0 && snapshot.ride.processingChunks == 0, pendingReward: snapshot.reward.pendingReward, confirmedReward: snapshot.reward.confirmedReward)
        session.validDistanceM = summary.validDistanceM; try RideStateMachine.transition(&session, to: .completed, at: clock.now())
        await progressWorker.stopPolling()
        let evidence = await evidenceRecorder.stopRide()
        navigationEngine.clear(); roadWarningEngine.reset(); state.roadWarning = nil; state.riskLayerSnapshot = nil; state.mapState = .empty; state.latestRideEvidence = evidence; mapRenderer.clearRoute(); await riskLayerWorker.clearRouteContext(); location.stop(); sensors.stop(); try sessions.save(session); state.session = session; publish(); return summary
    }

    private func receive(location value: LocationSnapshot) {
        state.location = value
        state.mapState.currentLocation = value.coordinate
        Task { await evidenceRecorder.recordLocation(value, at: clock.now()) }
        guard var session = state.session, session.state == .active else {
            publish()
            return
        }
        var rejectedGPSJump = false
        if let current = value.coordinate, let navigation = navigationEngine.update(location: current) {
            rejectedGPSJump = navigation.rejectedGPSJump
            state.navigationProgress = navigation; state.selectedRoute = navigation.route; session.routeProgressRatio = navigation.progressRatio
            state.nextInstruction = navigation.nextTurn.map { .init(title: $0.instruction, distanceM: navigation.distanceToNextTurn) }
            if !navigation.isOffRoute, state.routeCorrectionNotice?.status == .offRoute {
                state.routeCorrectionNotice = nil
            }
            if navigation.isOffRoute { requestReroute(from: current, route: navigation.route) }
            let displayedLocation = navigation.matchedCoordinate ?? current
            let camera = MapModelMapper.followingCamera(current: displayedLocation, heading: value.heading, nextTurn: navigation.nextTurn, distanceToTurn: navigation.distanceToNextTurn)
            state.mapState.currentLocation = displayedLocation; state.mapState.camera = camera
            mapRenderer.showCurrentLocation(displayedLocation); mapRenderer.moveCamera(camera)
            if let snapshot = state.riskLayerSnapshot, let warning = roadWarningEngine.evaluate(location: value, navigation: navigation, route: navigation.route, snapshot: snapshot, now: clock.now()) { state.roadWarning = warning; roadWarningOutput.emit(warning) }
        }
        if !rejectedGPSJump, let previous = lastCoordinate, let current = value.coordinate { session.localDistanceM += haversine(previous, current) }
        if !rejectedGPSJump { lastCoordinate = value.coordinate }
        state.session = session
        try? sessions.save(session); publish()
    }

    private func requestReroute(from coordinate: Coordinate, route: Route) {
        guard !state.isRerouting else { return }
        state.isRerouting = true
        state.routeCorrectionNotice = .init(status: .rerouting, message: "경로를 벗어났습니다. 현재 위치 기준으로 새 경로를 안내합니다.", coordinate: coordinate)
        publish()
        Task { [weak self] in
            guard let self else { return }
            do {
                let refreshed = try await routes.refreshRoute(route, from: coordinate)
                navigationEngine.setRoute(refreshed); state.selectedRoute = refreshed; state.navigationProgress = nil; state.nextInstruction = refreshed.turnList.first.map { .init(title: $0.instruction, distanceM: $0.distance) }; renderRouteOnMap(refreshed, cameraMode: .automatic); state.isRerouting = false; state.routeCorrectionNotice = .init(status: .corrected, message: "새 경로로 정정했습니다. 안내를 따라 계속 주행하세요.", coordinate: coordinate); publish(); await syncRiskRoute(refreshed)
            } catch {
                state.isRerouting = false
                state.routeCorrectionNotice = .init(status: .failed, message: "경로 이탈을 감지했지만 새 경로를 가져오지 못했습니다. 안전한 곳에서 경로를 다시 탐색해 주세요.", coordinate: coordinate)
                publish()
            }
        }
    }

    private func renderRouteOnMap(_ route: Route, cameraMode: MapCameraMode) {
        let polyline = MapModelMapper.polyline(from: route), turns = MapModelMapper.turns(from: route)
        let risks = state.riskLayerSnapshot.map { MapModelMapper.risks(from: $0, at: clock.now()) } ?? []
        let camera: MapCameraState?
        if cameraMode == .automatic, let current = state.location.coordinate { camera = MapModelMapper.followingCamera(current: current, heading: state.location.heading, nextTurn: route.turnList.first, distanceToTurn: route.turnList.first?.distance ?? .greatestFiniteMagnitude) }
        else { camera = MapModelMapper.fullRouteCamera(route) }
        state.mapState.route = polyline; state.mapState.turns = turns; state.mapState.riskOverlays = risks; state.mapState.camera = camera
        mapRenderer.renderRoute(polyline, turns: turns); mapRenderer.renderRiskCells(risks); if let camera { mapRenderer.moveCamera(camera) }
    }

    private func receive(chunk: SensorChunk) {
        guard var session = state.session, session.state == .active else { return }
        Task { await evidenceRecorder.processSensorChunk(chunk) }
        if telemetryPipeline == nil { try? queue.enqueue(chunk) }
        session.lastChunkSeq = max(session.lastChunkSeq, chunk.chunkSeq)
        state.queuedChunkCount = telemetryPipeline == nil ? queue.pending(sessionId: session.id).count : state.telemetrySummary.unsentCount; state.session = session
        if chunk.sampleCount > 30, var game = state.game {
            game.estimatedDataDamage += 3
            game.damageFeed.insert(DamageFeedItem(title: "센서 고품질 노면 관측 청크 #\(chunk.chunkSeq) 보너스", damage: 3, isConfirmed: false, type: .unknownDiscovery), at: 0)
            if game.damageFeed.count > 10 { game.damageFeed.removeLast() }
            if var minion = game.currentMinion, !minion.isDefeated {
                minion.remainingHp = max(0, minion.remainingHp - 5)
                game.currentMinion = minion
            }
            game.remainingHp = max(0, game.maxHp - game.estimatedTotalDamage)
            game.processingState = .awaitingServer
            state.game = game
        }
        try? sessions.save(session); publish()
        if let telemetryPipeline { Task { await telemetryPipeline.enqueue(chunk); await self.refreshTelemetrySummary() } }
    }

    public func refreshTelemetrySummary() async { guard let telemetryPipeline else { return }; state.telemetrySummary = await telemetryPipeline.summary(); state.queuedChunkCount = state.telemetrySummary.unsentCount; publish() }

    public func applicationDidBecomeActive() async {
        guard let session = state.session, [.active, .paused, .finishing].contains(session.state) else { return }
        if let snapshot = try? await progressWorker.sync(rideId: session.id) { apply(snapshot) }
        await riskLayerWorker.refreshIfStale()
    }

    private func uploadDidSucceed() async {
        guard let session = state.session, [.active, .paused, .finishing].contains(session.state) else { return }
        if let snapshot = try? await progressWorker.sync(rideId: session.id) { apply(snapshot) }
        await refreshTelemetrySummary()
    }

    private func apply(_ snapshot: ServerProgressSnapshot) {
        let previousRiskVersion = state.riskLayerVersion
        state.rideProgress = snapshot.ride; state.rewardProgress = snapshot.reward
        if var session = state.session { session.validDistanceM = snapshot.ride.validDistance; state.session = session; try? sessions.save(session) }
        if let boss = snapshot.boss, var game = state.game {
            game.remainingHp = boss.bossHP; game.confirmedBaseDamage = boss.confirmedDamage
            game.processingState = boss.processingState == .confirmed ? .confirmed : .awaitingServer; state.game = game
        }
        if snapshot.riskLayerVersion != previousRiskVersion { Task { await riskLayerWorker.syncIfVersionChanged(snapshot.riskLayerVersion); if let value = await riskLayerWorker.cachedSnapshot() { applyRiskLayer(value) } } }
        publish()
    }

    private func applyRiskLayer(_ snapshot: RiskLayerSnapshot) {
        state.riskLayerSnapshot = snapshot; state.riskLayerVersion = snapshot.layerVersion; state.lastRiskLayerUpdate = snapshot.generatedAt
        let overlays = MapModelMapper.risks(from: snapshot, at: clock.now()); state.mapState.riskOverlays = overlays; mapRenderer.renderRiskCells(overlays); publish()
    }
    private func syncRiskRoute(_ route: Route) async { await riskLayerWorker.syncRoute(route); if let snapshot = await riskLayerWorker.cachedSnapshot() { applyRiskLayer(snapshot) } }

}

private func haversine(_ a: Coordinate, _ b: Coordinate) -> Double {
    let radius = 6_371_000.0, lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLat = (b.latitude - a.latitude) * .pi / 180, dLon = (b.longitude - a.longitude) * .pi / 180
    let value = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return radius * 2 * atan2(sqrt(value), sqrt(1 - value))
}
