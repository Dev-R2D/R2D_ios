import SwiftUI
import R2DCore
#if canImport(MapKit)
import MapKit
#endif

public struct MapRendererSnapshot: Equatable, Sendable {
    public var route: R2DCore.MapPolyline?, turns: [MapTurnAnnotation] = [], risks: [MapRiskOverlay] = [], camera: MapCameraState?, currentLocation: Coordinate?
    public init() {}
}

@MainActor public final class MockMapRenderer: ObservableObject, IMapRenderer {
    @Published public private(set) var snapshot = MapRendererSnapshot()
    public private(set) var clearCount = 0
    public init() {}
    public func renderRoute(_ route: R2DCore.MapPolyline, turns: [MapTurnAnnotation]) { snapshot.route = route; snapshot.turns = turns }
    public func renderRiskCells(_ overlays: [MapRiskOverlay]) { snapshot.risks = overlays }
    public func moveCamera(_ camera: MapCameraState) { snapshot.camera = camera }
    public func showCurrentLocation(_ coordinate: Coordinate) { snapshot.currentLocation = coordinate }
    public func clearRoute() { snapshot = .init(); clearCount += 1 }
}

@MainActor public final class AppleMapKitRenderer: ObservableObject, IMapRenderer {
    @Published public private(set) var snapshot = MapRendererSnapshot()
    public init() {}
    public func renderRoute(_ route: R2DCore.MapPolyline, turns: [MapTurnAnnotation]) { snapshot.route = route; snapshot.turns = turns }
    public func renderRiskCells(_ overlays: [MapRiskOverlay]) { snapshot.risks = overlays }
    public func moveCamera(_ camera: MapCameraState) { snapshot.camera = camera }
    public func showCurrentLocation(_ coordinate: Coordinate) { snapshot.currentLocation = coordinate }
    public func clearRoute() { snapshot = .init() }
}

public struct AppleMapKitRendererView: View {
    @ObservedObject private var renderer: AppleMapKitRenderer
    public init(renderer: AppleMapKitRenderer) { self.renderer = renderer }
    public var body: some View {
        MapSDKView(state: .init(route: renderer.snapshot.route, turns: renderer.snapshot.turns, riskOverlays: renderer.snapshot.risks, currentLocation: renderer.snapshot.currentLocation, camera: renderer.snapshot.camera))
    }
}

#if canImport(MapKit)
public struct MapSDKView: View {
    public let state: MapState
    @State private var position: MapCameraPosition = .automatic
    public init(state: MapState) { self.state = state }
    public var body: some View {
        Map(position: $position) {
            if let route = state.route {
                MapKit.MapPolyline(coordinates: route.coordinates.map(\.clLocationCoordinate)).stroke(.mint, lineWidth: 6)
            }
            ForEach(state.riskOverlays) { overlay in
                if overlay.coordinates.count >= 3 {
                    MapPolygon(coordinates: overlay.coordinates.map(\.clLocationCoordinate)).foregroundStyle(riskColor(overlay).opacity(0.32)).stroke(riskColor(overlay), lineWidth: 2)
                } else if overlay.coordinates.count == 2 {
                    MapKit.MapPolyline(coordinates: overlay.coordinates.map(\.clLocationCoordinate)).stroke(riskColor(overlay), lineWidth: 8)
                } else if let coordinate = overlay.coordinates.first {
                    Annotation("위험", coordinate: coordinate.clLocationCoordinate) { Circle().fill(riskColor(overlay)).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 2)) }
                }
            }
            ForEach(state.turns) { turn in
                Annotation(turn.instruction, coordinate: turn.coordinate.clLocationCoordinate) { Image(systemName: turn.isDestination ? "flag.checkered.circle.fill" : "arrow.turn.up.right.circle.fill").font(.title2).foregroundStyle(turn.isDestination ? .pink : .blue).background(.white, in: Circle()) }
            }
            if let current = state.currentLocation {
                Annotation("현재 위치", coordinate: current.clLocationCoordinate) { Image(systemName: "location.circle.fill").font(.title).foregroundStyle(.blue).background(.white, in: Circle()) }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onAppear { updateCamera(state.camera) }
        .onChange(of: state.camera) { _, camera in updateCamera(camera) }
    }
    private func updateCamera(_ camera: MapCameraState?) {
        guard let camera else { return }
        position = .region(.init(center: camera.center.clLocationCoordinate, span: .init(latitudeDelta: camera.latitudeDelta, longitudeDelta: camera.longitudeDelta)))
    }
    private func riskColor(_ overlay: MapRiskOverlay) -> Color {
        if overlay.dataState == .unknown { return .gray }
        switch overlay.riskState { case .confirmedDamage, .restricted: return .red; case .rough, .repairPending: return .orange; case .suspectedDamage: return .yellow; case .normal: return .green }
    }
}

private extension Coordinate { var clLocationCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) } }
#else
public struct MapSDKView: View {
    public let state: MapState
    public init(state: MapState) { self.state = state }
    public var body: some View { Color.teal.opacity(0.25).overlay { Image(systemName: "map") } }
}
#endif
