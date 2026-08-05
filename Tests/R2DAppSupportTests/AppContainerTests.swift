import Foundation
import Testing
import R2DCore
import R2DInfrastructure
import R2DUI
@testable import R2DAppSupport

@Test @MainActor func previewUsesMocksAndProductionUsesAppleAdapters() {
    let preview = AppContainer.preview(); #expect(preview.locationAdapterName == "MockLocationTracker"); #expect(preview.sensorAdapterName == "MockSensorCollector")
    #expect(preview.routeAdapterName == "MockRouteRepository")
    #expect(preview.mapRendererName == "MockMapRenderer")
    #expect(preview.telemetryPipelineName == "TelemetryUploadWorker")
    let production = AppContainer.production()
    #if os(iOS) && canImport(CoreLocation) && canImport(CoreMotion)
    #expect(production.locationAdapterName == "CoreLocationTracker"); #expect(production.sensorAdapterName == "CoreMotionSensorCollector")
    #endif
}

@Test @MainActor func previewMockRendererReceivesRouteRendering() async throws {
    let container = AppContainer.preview(), renderer = try #require(container.mapRenderer as? MockMapRenderer)
    try await container.activeRideCoordinator.searchRoutes(origin: .init(latitude: 37.55, longitude: 127.04), destination: .init(latitude: 37.56, longitude: 127.05))
    let route = try #require(container.activeRideCoordinator.getSnapshot().routes.first); container.activeRideCoordinator.selectRoute(route)
    #expect(renderer.snapshot.route?.routeID == route.id); #expect(renderer.snapshot.turns.count == route.turnList.count); #expect(renderer.snapshot.camera?.mode == .fullRoute)
}

@Test @MainActor func lifecycleRestoresExistingActiveSession() throws {
    let sessions = MemoryRideSessionRepository(), location = MockLocationTracker(), sensors = MockSensorCollector()
    var ride = try sessions.create(routeId: "route-fast", boss: nil); try RideStateMachine.transition(&ride, to: .ready); try RideStateMachine.transition(&ride, to: .active); try sessions.save(ride)
    let container = AppContainer.testing(sessions: sessions, location: location, sensors: sensors); container.lifecycle.bootstrap()
    #expect(container.activeRideCoordinator.getSnapshot().session?.id == ride.id); #expect(location.isRunning); #expect(sensors.isRunning)
    #expect(throws: RideError.activeSessionExists) { try sessions.create(routeId: "another", boss: nil) }
}

@Test @MainActor func navigatorDemoUsesOfflineReplayAndKeepsLimitedGamePreview() async {
    let container = AppContainer.demoNavigator()
    #expect(container.environment == .demoNavigator)
    #expect(container.locationAdapterName == "DemoRouteLocationTracker")
    #expect(container.routeAdapterName == "DemoRouteRepository")
    #expect(container.mapRendererName == "AppleMapKitRenderer")
    #expect(container.featureFlags.replayLocationEnabled)
    #expect(!container.featureFlags.liveServerEnabled)
    #expect(container.featureFlags.gameEnabled)
    #expect(container.featureFlags.gamePreviewOnly)
    #expect(!container.featureFlags.rewardEnabled)
    #expect(container.demoReplayController != nil)
    #expect(container.demoResourcesAvailable)
    #expect(await container.authenticationState() == .authenticated)
    #expect(container.activeRideCoordinator.getSnapshot().activeView == .navigator)
    #expect(container.activeRideCoordinator.getSnapshot().session == nil)
}

@Test @MainActor func navigatorDemoRunsFromHomeThroughReplayRiskAndResult() async throws {
    let container = AppContainer.demoNavigator(), coordinator = container.activeRideCoordinator
    try await coordinator.searchRoutes(origin: DemoNavigatorFixture.origin, destination: DemoNavigatorFixture.destination)
    let safe = try #require(coordinator.getSnapshot().routes.first { $0.id == "demo-safe" })
    coordinator.selectRoute(safe)
    try await Task.sleep(for: .milliseconds(80))
    #expect(!coordinator.getSnapshot().mapState.riskOverlays.isEmpty)
    _ = try coordinator.prepare(); _ = try coordinator.start()
    let firstInstruction = coordinator.getSnapshot().nextInstruction
    coordinator.switchView(.game); #expect(coordinator.getSnapshot().activeView == .game)
    coordinator.switchView(.navigator); #expect(coordinator.getSnapshot().activeView == .navigator)
    let controller = try #require(container.demoReplayController)
    controller.seek(to: .risk)
    try await waitUntil(timeout: 5) { coordinator.getSnapshot().roadWarning?.severity == .high }
    #expect(coordinator.getSnapshot().roadWarning?.severity == .high)
    #expect(coordinator.getSnapshot().nextInstruction != firstInstruction)
    let initialDistance = safe.totalDistance
    controller.seek(to: .destination)
    try await waitUntil(timeout: 5) { container.viewModel.summary != nil }
    #expect(container.viewModel.summary != nil)
    #expect(coordinator.getSnapshot().session?.state == .completed)
    #expect((coordinator.getSnapshot().navigationProgress?.remainingDistance ?? initialDistance) < initialDistance)
}

@Test @MainActor func navigatorDemoOffRouteInstallsRefreshedRoute() async throws {
    let container = AppContainer.demoNavigator(), coordinator = container.activeRideCoordinator
    try await coordinator.searchRoutes(origin: DemoNavigatorFixture.origin, destination: DemoNavigatorFixture.destination)
    let safe = try #require(coordinator.getSnapshot().routes.first { $0.id == "demo-safe" })
    coordinator.selectRoute(safe); _ = try coordinator.prepare(); _ = try coordinator.start()
    let controller = try #require(container.demoReplayController)
    controller.seek(to: .reroute)
    try await waitUntil(timeout: 3) { coordinator.getSnapshot().selectedRoute?.id == "demo-safe-reroute" }
    #expect(coordinator.getSnapshot().selectedRoute?.id == "demo-safe-reroute")
    _ = try? await coordinator.finish()
}

@MainActor private func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    #expect(condition())
}

@Test @MainActor func navigatorDemoLoadsThreeRoutesAndRendersSafeRoute() async throws {
    let container = AppContainer.demoNavigator()
    try await container.activeRideCoordinator.searchRoutes(origin: DemoNavigatorFixture.origin, destination: DemoNavigatorFixture.destination)
    let routes = container.activeRideCoordinator.getSnapshot().routes
    #expect(routes.count == 3)
    let safe = try #require(routes.first { $0.id == "demo-safe" })
    container.activeRideCoordinator.selectRoute(safe)
    #expect(container.activeRideCoordinator.getSnapshot().mapState.route?.routeID == "demo-safe")
    #expect(container.activeRideCoordinator.getSnapshot().mapState.turns.count == safe.turnList.count)
}
