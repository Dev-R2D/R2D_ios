import Foundation
#if canImport(iNaviMaps)
import iNaviMaps
#endif

public struct MapPolyline: Equatable, Sendable {
    public let routeID: String, coordinates: [Coordinate]
    public init(routeID: String, coordinates: [Coordinate]) { self.routeID = routeID; self.coordinates = coordinates }
}

public struct MapTurnAnnotation: Identifiable, Equatable, Sendable {
    public let id: String, coordinate: Coordinate, instruction: String, isDestination: Bool
    public init(id: String, coordinate: Coordinate, instruction: String, isDestination: Bool = false) { self.id = id; self.coordinate = coordinate; self.instruction = instruction; self.isDestination = isDestination }
}

public struct MapRiskOverlay: Identifiable, Equatable, Sendable {
    public let id: String, coordinates: [Coordinate], riskScore: Int, confidence: Double
    public let dataState: DataState, riskState: RiskState, isStale: Bool, layerVersion: String
    public init(id: String, coordinates: [Coordinate], riskScore: Int, confidence: Double, dataState: DataState = .review, riskState: RiskState = .suspectedDamage, isStale: Bool = false, layerVersion: String = "route-preview") { self.id = id; self.coordinates = coordinates; self.riskScore = riskScore; self.confidence = confidence; self.dataState = dataState; self.riskState = riskState; self.isStale = isStale; self.layerVersion = layerVersion }
}

public enum MapCameraMode: String, Equatable, Sendable { case automatic, nextTurn, fullRoute }
public struct MapCameraState: Equatable, Sendable {
    public let center: Coordinate, latitudeDelta: Double, longitudeDelta: Double, heading: Double, mode: MapCameraMode
    public init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double, heading: Double = 0, mode: MapCameraMode) { self.center = center; self.latitudeDelta = latitudeDelta; self.longitudeDelta = longitudeDelta; self.heading = heading; self.mode = mode }
}

public struct MapState: Equatable, Sendable {
    public var route: MapPolyline?, turns: [MapTurnAnnotation], riskOverlays: [MapRiskOverlay]
    public var currentLocation: Coordinate?, camera: MapCameraState?
    public init(route: MapPolyline? = nil, turns: [MapTurnAnnotation] = [], riskOverlays: [MapRiskOverlay] = [], currentLocation: Coordinate? = nil, camera: MapCameraState? = nil) { self.route = route; self.turns = turns; self.riskOverlays = riskOverlays; self.currentLocation = currentLocation; self.camera = camera }
    public static let empty = MapState()
}

@MainActor public protocol IMapRenderer: AnyObject {
    func renderRoute(_ route: MapPolyline, turns: [MapTurnAnnotation])
    func renderRiskCells(_ overlays: [MapRiskOverlay])
    func moveCamera(_ camera: MapCameraState)
    func showCurrentLocation(_ coordinate: Coordinate)
    func clearRoute()
}

@MainActor public final class NoopMapRenderer: IMapRenderer {
    public init() {}
    public func renderRoute(_ route: MapPolyline, turns: [MapTurnAnnotation]) {}
    public func renderRiskCells(_ overlays: [MapRiskOverlay]) {}
    public func moveCamera(_ camera: MapCameraState) {}
    public func showCurrentLocation(_ coordinate: Coordinate) {}
    public func clearRoute() {}
}

public enum MapModelMapper {
    public static func polyline(from route: Route) -> MapPolyline { .init(routeID: route.id, coordinates: route.polyline) }
    public static func turns(from route: Route) -> [MapTurnAnnotation] {
        route.turnList.enumerated().map { index, turn in .init(id: "\(route.id)-turn-\(index)", coordinate: turn.coordinate, instruction: turn.instruction, isDestination: index == route.turnList.count - 1) }
    }
    public static func risks(from snapshot: RiskLayerSnapshot, at date: Date) -> [MapRiskOverlay] { snapshot.cells.map { cell in .init(id: cell.id, coordinates: cell.geometry.coordinates, riskScore: cell.riskScore, confidence: cell.confidence, dataState: cell.dataState, riskState: cell.riskState, isStale: snapshot.isStale(at: date) || cell.validUntil.map { $0 <= date } == true, layerVersion: cell.layerVersion) } }
    public static func fullRouteCamera(_ route: Route) -> MapCameraState? {
        guard let first = route.polyline.first else { return nil }
        let latitudes = route.polyline.map(\.latitude), longitudes = route.polyline.map(\.longitude)
        let minLat = latitudes.min() ?? first.latitude, maxLat = latitudes.max() ?? first.latitude, minLon = longitudes.min() ?? first.longitude, maxLon = longitudes.max() ?? first.longitude
        return .init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2), latitudeDelta: max(0.004, (maxLat - minLat) * 1.35), longitudeDelta: max(0.004, (maxLon - minLon) * 1.35), mode: .fullRoute)
    }
    public static func followingCamera(current: Coordinate, heading: Double, nextTurn: Turn?, distanceToTurn: Double) -> MapCameraState {
        if let nextTurn, distanceToTurn < 150 { return .init(center: nextTurn.coordinate, latitudeDelta: 0.004, longitudeDelta: 0.004, heading: heading, mode: .nextTurn) }
        return .init(center: current, latitudeDelta: 0.006, longitudeDelta: 0.006, heading: heading, mode: .automatic)
    }
}
