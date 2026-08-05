import Foundation
import Testing
@testable import R2DCore

@MainActor private final class FakeMapRenderer: IMapRenderer {
    enum Event: Equatable { case route(String), risks(Int), camera(MapCameraMode), location(Coordinate), clear }
    var events: [Event] = [], route: MapPolyline?, turns: [MapTurnAnnotation] = [], risks: [MapRiskOverlay] = [], camera: MapCameraState?, location: Coordinate?
    func renderRoute(_ route: MapPolyline, turns: [MapTurnAnnotation]) { self.route = route; self.turns = turns; events.append(.route(route.routeID)) }
    func renderRiskCells(_ overlays: [MapRiskOverlay]) { risks = overlays; events.append(.risks(overlays.count)) }
    func moveCamera(_ camera: MapCameraState) { self.camera = camera; events.append(.camera(camera.mode)) }
    func showCurrentLocation(_ coordinate: Coordinate) { location = coordinate; events.append(.location(coordinate)) }
    func clearRoute() { route = nil; turns = []; risks = []; camera = nil; location = nil; events.append(.clear) }
}

private let mapOrigin = Coordinate(latitude: 37.55, longitude: 127.04)
private let mapTurn = Coordinate(latitude: 37.5505, longitude: 127.04)
private let mapDestination = Coordinate(latitude: 37.551, longitude: 127.04)
private func mapRoute(id: String = "map-route", origin: Coordinate = mapOrigin) -> Route {
    .init(id: id, polyline: [origin, mapTurn, mapDestination], totalDistance: 111, totalDuration: 60, turnList: [.init(coordinate: mapTurn, instruction: "우회전", distance: 55), .init(coordinate: mapDestination, instruction: "도착", distance: 56)], riskCells: [.init(id: "risk-point", geometry: "POINT(127.0402 37.5504)", riskScore: 0.8, confidence: 0.9), .init(id: "risk-line", geometry: "LINESTRING(127.04 37.55,127.041 37.551)", riskScore: 0.5, confidence: 0.8)])
}

private actor MapRouteRepository: IRouteRepository {
    let initial = mapRoute()
    func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] { [initial] }
    func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route { mapRoute(id: "rerouted-map", origin: currentLocation) }
    func cancelSearch() async {}
}

@MainActor private func mapFixture(engine: NavigationEngine = .init()) -> (ActiveRideCoordinator, MockLocationTracker, FakeMapRenderer) {
    let location = MockLocationTracker(), renderer = FakeMapRenderer()
    let coordinator = ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: location, sensors: MockSensorCollector(), routes: MapRouteRepository(), navigationEngine: engine, mapRenderer: renderer, queue: MemoryTelemetryQueue(), progress: MockProgressServer())
    return (coordinator, location, renderer)
}

@Test @MainActor func routeRenderingUsesMapPolylineAndTurnAnnotations() {
    let (coordinator, _, renderer) = mapFixture(); coordinator.selectRoute(mapRoute())
    #expect(renderer.route?.coordinates.count == 3); #expect(renderer.turns.count == 2); #expect(renderer.turns.last?.isDestination == true)
}

@Test @MainActor func selectingRouteMovesCameraToFullRoute() {
    let (coordinator, _, renderer) = mapFixture(); coordinator.selectRoute(mapRoute())
    #expect(renderer.camera?.mode == .fullRoute); #expect(coordinator.getSnapshot().mapState.camera == renderer.camera)
}

@Test @MainActor func routeRiskHintsAreNotRenderedAsVerifiedServerLayer() {
    let (coordinator, _, renderer) = mapFixture(); coordinator.selectRoute(mapRoute())
    #expect(renderer.risks.isEmpty); #expect(coordinator.getSnapshot().mapState.riskOverlays.isEmpty)
}

@Test @MainActor func currentLocationIsShownAndAutomaticallyTracked() async throws {
    let (coordinator, location, renderer) = mapFixture(); coordinator.selectRoute(mapRoute()); _ = try coordinator.prepare(); _ = try coordinator.start()
    location.simulate(.init(coordinate: mapOrigin, speedMps: 5, heading: 20, mapMatchConfidence: 0.9)); try await Task.sleep(for: .milliseconds(20))
    #expect(renderer.location == mapOrigin); #expect(renderer.camera?.mode == .nextTurn); #expect(coordinator.getSnapshot().mapState.currentLocation == mapOrigin)
}

@Test @MainActor func turnUpdateChangesCameraTarget() async throws {
    let (coordinator, location, renderer) = mapFixture(); coordinator.selectRoute(mapRoute()); _ = try coordinator.prepare(); _ = try coordinator.start()
    location.simulate(.init(coordinate: mapOrigin, speedMps: 5, heading: 0, mapMatchConfidence: 0.9)); try await Task.sleep(for: .milliseconds(20)); coordinator.focusNextTurn()
    #expect(renderer.camera?.center == mapTurn); #expect(renderer.camera?.mode == .nextTurn)
}

@Test @MainActor func rerouteRendersReplacementLayersAndCamera() async throws {
    let engine = NavigationEngine(configuration: .init(matchingToleranceM: 20, offRouteDistanceM: 30, maximumGPSJumpM: 500, offRouteConfirmations: 1))
    let (coordinator, location, renderer) = mapFixture(engine: engine); coordinator.selectRoute(mapRoute()); _ = try coordinator.prepare(); _ = try coordinator.start()
    location.simulate(.init(coordinate: mapOrigin, speedMps: 5, heading: 0, mapMatchConfidence: 0.9)); location.simulate(.init(coordinate: .init(latitude: 37.5502, longitude: 127.041), speedMps: 5, heading: 0, mapMatchConfidence: 0.9)); try await Task.sleep(for: .milliseconds(40))
    #expect(renderer.route?.routeID == "rerouted-map"); #expect(renderer.events.contains(.route("rerouted-map"))); #expect(coordinator.getSnapshot().mapState.route?.routeID == "rerouted-map")
}

@Test @MainActor func mapStateKeepsRouteRiskTurnLocationAndCameraLayers() async throws {
    let (coordinator, location, _) = mapFixture(); coordinator.selectRoute(mapRoute()); _ = try coordinator.prepare(); _ = try coordinator.start(); location.simulate(.init(coordinate: mapOrigin, speedMps: 5, heading: 0, mapMatchConfidence: 0.9)); try await Task.sleep(for: .milliseconds(20))
    let state = coordinator.getSnapshot().mapState
    #expect(state.route != nil); #expect(state.turns.count == 2); #expect(state.riskOverlays.isEmpty); #expect(state.currentLocation != nil); #expect(state.camera != nil)
}

@Test @MainActor func finishClearsFakeRendererAndMapState() async throws {
    let (coordinator, _, renderer) = mapFixture(); coordinator.selectRoute(mapRoute()); _ = try coordinator.prepare(); _ = try coordinator.start(); _ = try await coordinator.finish()
    #expect(renderer.events.last == .clear); #expect(renderer.route == nil); #expect(coordinator.getSnapshot().mapState == .empty)
}
