import Foundation
import Testing
@testable import R2DCore

private let navOrigin = Coordinate(latitude: 37.5500, longitude: 127.0400)
private let navMiddle = Coordinate(latitude: 37.5510, longitude: 127.0400)
private let navDestination = Coordinate(latitude: 37.5520, longitude: 127.0400)

private func navRoute(id: String = "route-test") -> Route {
    .init(id: id, polyline: [navOrigin, navMiddle, navDestination], totalDistance: 222.4, totalDuration: 200, turnList: [.init(coordinate: navMiddle, instruction: "우회전", distance: 111.2), .init(coordinate: navDestination, instruction: "도착", distance: 111.2)], riskCells: [.init(id: "risk", geometry: "POINT", riskScore: 0.4, confidence: 0.9)])
}

private actor FakeRouteRepository: IRouteRepository {
    var route = navRoute(id: "fake-route"), searchCount = 0, refreshCount = 0, cancelCount = 0
    func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] { searchCount += 1; return [route] }
    func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route { refreshCount += 1; var refreshed = self.route; refreshed = .init(id: "rerouted", polyline: [currentLocation, navDestination], totalDistance: 120, totalDuration: 60, turnList: [.init(coordinate: navDestination, instruction: "새 경로", distance: 120)], riskCells: []); return refreshed }
    func cancelSearch() async { cancelCount += 1 }
    func counts() -> (Int, Int, Int) { (searchCount, refreshCount, cancelCount) }
}

@Test func routeSearchReturnsDomainRoute() async throws {
    let repository = FakeRouteRepository(), routes = try await repository.searchRoute(origin: navOrigin, destination: navDestination)
    #expect(routes.first?.polyline.count == 3); #expect(routes.first?.turnList.first?.instruction == "우회전")
}

@Test func routeRefreshStartsAtCurrentLocation() async throws {
    let repository = FakeRouteRepository(), current = Coordinate(latitude: 37.5505, longitude: 127.041)
    let refreshed = try await repository.refreshRoute(navRoute(), from: current)
    #expect(refreshed.id == "rerouted"); #expect(refreshed.polyline.first == current); #expect(await repository.counts().1 == 1)
}

@Test func routeSearchCanBeCancelledThroughPort() async {
    let repository = FakeRouteRepository(); await repository.cancelSearch(); #expect(await repository.counts().2 == 1)
}

@Test func locationMatchesPolylineWithinTolerance() {
    let engine = NavigationEngine(); engine.setRoute(navRoute())
    let result = engine.update(location: .init(latitude: 37.5505, longitude: 127.04005))
    #expect(result?.matchedCoordinate != nil); #expect(result?.isOffRoute == false); #expect((result?.progressRatio ?? 0) > 0.2)
}

@Test func turnProgressAdvancesToNextTurn() {
    let engine = NavigationEngine(); engine.setRoute(navRoute())
    #expect(engine.update(location: navOrigin)?.nextTurn?.instruction == "우회전")
    #expect(engine.update(location: .init(latitude: 37.5512, longitude: 127.04))?.nextTurn?.instruction == "도착")
}

@Test func etaScalesWithRemainingRoute() {
    let engine = NavigationEngine(); engine.setRoute(navRoute())
    let result = engine.update(location: navMiddle)
    #expect(abs((result?.remainingDuration ?? 0) - 100) < 2)
}

@Test func remainingDistanceUsesMatchedRouteProgress() {
    let engine = NavigationEngine(); engine.setRoute(navRoute())
    let result = engine.update(location: navMiddle)
    #expect(abs((result?.remainingDistance ?? 0) - 111.2) < 2)
}

@Test func repeatedDistantSamplesDetectOffRoute() {
    let engine = NavigationEngine(configuration: .init(matchingToleranceM: 30, offRouteDistanceM: 60, maximumGPSJumpM: 500, offRouteConfirmations: 2)); engine.setRoute(navRoute())
    _ = engine.update(location: navOrigin)
    let off = Coordinate(latitude: 37.5505, longitude: 127.0411)
    #expect(engine.update(location: off)?.isOffRoute == false); #expect(engine.update(location: off)?.isOffRoute == true)
}

@Test func gpsJumpIsRejectedWithoutAdvancingProgress() {
    let engine = NavigationEngine(configuration: .init(maximumGPSJumpM: 100)); engine.setRoute(navRoute())
    let initial = engine.update(location: navOrigin), jump = engine.update(location: navDestination)
    #expect(jump?.rejectedGPSJump == true); #expect(jump?.progressRatio == initial?.progressRatio)
}

@Test func mockRouteRepositoryProvidesUsableNavigationDomain() async throws {
    let route = try #require(try await MockRouteRepository().searchRoute(origin: navOrigin, destination: navDestination).first)
    #expect(route.id == "route-fast"); #expect(route.polyline.count >= 2); #expect(!route.turnList.isEmpty)
}

@Test @MainActor func fakeRouteCanBeInjectedIntoCoordinator() async throws {
    let repository = FakeRouteRepository()
    let coordinator = ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: MockLocationTracker(), sensors: MockSensorCollector(), routes: repository, queue: MemoryTelemetryQueue(), progress: MockProgressServer())
    try await coordinator.searchRoutes(origin: navOrigin, destination: navDestination)
    #expect(coordinator.getSnapshot().routes.first?.id == "fake-route"); #expect(await repository.counts().0 == 1)
}

@Test @MainActor func offRouteTriggersCoordinatorReroute() async throws {
    let repository = FakeRouteRepository(), location = MockLocationTracker(), sensors = MockSensorCollector()
    let engine = NavigationEngine(configuration: .init(matchingToleranceM: 30, offRouteDistanceM: 50, maximumGPSJumpM: 500, offRouteConfirmations: 1))
    let coordinator = ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: location, sensors: sensors, routes: repository, navigationEngine: engine, queue: MemoryTelemetryQueue(), progress: MockProgressServer())
    try await coordinator.searchRoutes(origin: navOrigin, destination: navDestination); coordinator.selectRoute(coordinator.getSnapshot().routes[0]); _ = try coordinator.prepare(); _ = try coordinator.start()
    location.simulate(.init(coordinate: navOrigin, speedMps: 5, heading: 0, mapMatchConfidence: 0.9))
    location.simulate(.init(coordinate: .init(latitude: 37.5505, longitude: 127.041), speedMps: 5, heading: 0, mapMatchConfidence: 0.9))
    try await Task.sleep(for: .milliseconds(40))
    #expect(await repository.counts().1 == 1); #expect(coordinator.getSnapshot().selectedRoute?.id == "rerouted"); #expect(!coordinator.getSnapshot().isRerouting)
}

@Test @MainActor func coordinatorDoesNotAddRejectedGPSJumpToRideDistance() async throws {
    let location = MockLocationTracker(), engine = NavigationEngine(configuration: .init(maximumGPSJumpM: 100))
    let coordinator = ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: location, sensors: MockSensorCollector(), routes: MockRouteRepository(), navigationEngine: engine, queue: MemoryTelemetryQueue(), progress: MockProgressServer())
    try await coordinator.searchRoutes(origin: navOrigin, destination: navDestination); coordinator.selectRoute(navRoute()); _ = try coordinator.prepare(); _ = try coordinator.start()
    location.simulate(.init(coordinate: navOrigin, speedMps: 5, heading: 0, mapMatchConfidence: 0.9)); location.simulate(.init(coordinate: navDestination, speedMps: 5, heading: 0, mapMatchConfidence: 0.9))
    try await Task.sleep(for: .milliseconds(20))
    #expect(coordinator.getSnapshot().navigationProgress?.rejectedGPSJump == true); #expect(coordinator.getSnapshot().session?.localDistanceM == 0)
}
