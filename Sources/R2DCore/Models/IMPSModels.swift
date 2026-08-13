import Foundation

public enum IMPSProviderFeature: String, Codable, Equatable, Sendable {
    case geocoding = "GEOCODING"
    case reverseGeocoding = "REVERSE_GEOCODING"
    case routeSearch = "ROUTE_SEARCH"
    case routeOptimization = "ROUTE_OPTIMIZATION"
    case mapMatching = "MAP_MATCHING"
    case staticMap = "STATIC_MAP"
}

public struct PlaceSearchResult: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let address: String
    public let coordinate: Coordinate
    public let source: String

    public init(id: String, title: String, address: String, coordinate: Coordinate, source: String = "mock") {
        self.id = id
        self.title = title
        self.address = address
        self.coordinate = coordinate
        self.source = source
    }
}

public struct MatchedRoadPoint: Codable, Equatable, Sendable {
    public let original: Coordinate
    public let matched: Coordinate
    public let roadName: String?
    public let confidence: Double
    public let distanceFromOriginalM: Double

    public init(original: Coordinate, matched: Coordinate, roadName: String?, confidence: Double, distanceFromOriginalM: Double) {
        self.original = original
        self.matched = matched
        self.roadName = roadName
        self.confidence = confidence
        self.distanceFromOriginalM = distanceFromOriginalM
    }
}

public struct OptimizedRouteStop: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let coordinate: Coordinate
    public let loadWeightKg: Double

    public init(id: String, title: String, coordinate: Coordinate, loadWeightKg: Double = 0) {
        self.id = id
        self.title = title
        self.coordinate = coordinate
        self.loadWeightKg = loadWeightKg
    }
}

public struct RouteOptimizationRequest: Codable, Equatable, Sendable {
    public let origin: Coordinate
    public let stops: [OptimizedRouteStop]
    public let vehicleCapacityKg: Double?
    public let preferSafeRoads: Bool

    public init(origin: Coordinate, stops: [OptimizedRouteStop], vehicleCapacityKg: Double? = nil, preferSafeRoads: Bool = true) {
        self.origin = origin
        self.stops = stops
        self.vehicleCapacityKg = vehicleCapacityKg
        self.preferSafeRoads = preferSafeRoads
    }
}

public struct RouteOptimizationResult: Codable, Equatable, Sendable {
    public let orderedStops: [OptimizedRouteStop]
    public let route: Route
    public let totalLoadWeightKg: Double

    public init(orderedStops: [OptimizedRouteStop], route: Route, totalLoadWeightKg: Double) {
        self.orderedStops = orderedStops
        self.route = route
        self.totalLoadWeightKg = totalLoadWeightKg
    }
}
