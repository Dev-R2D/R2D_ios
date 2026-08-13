import Foundation
import R2DCore

public struct MockPlaceSearchRepository: IPlaceSearchRepository {
    private let places: [PlaceSearchResult]

    public init(places: [PlaceSearchResult] = MockPlaceSearchRepository.defaultPlaces) {
        self.places = places
    }

    public func geocode(_ query: String, near coordinate: Coordinate?) async throws -> [PlaceSearchResult] {
        print("R2D mock geocode used: \(query)")
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { throw IMPSRepositoryError.emptyQuery }

        let matched = places.filter {
            $0.title.lowercased().contains(normalized) || $0.address.lowercased().contains(normalized)
        }
        return matched.isEmpty ? places.prefix(3).map { $0 } : matched
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceSearchResult? {
        places.min {
            infrastructureDistance($0.coordinate, coordinate) < infrastructureDistance($1.coordinate, coordinate)
        }
    }

    public static let defaultPlaces: [PlaceSearchResult] = [
        .init(id: "dongtan-station", title: "동탄역", address: "경기도 화성시 동탄역로", coordinate: .init(latitude: 37.200594, longitude: 127.095858)),
        .init(id: "dongtan-central-park", title: "동탄센트럴파크", address: "경기도 화성시 동탄공원로", coordinate: .init(latitude: 37.205638, longitude: 127.065152)),
        .init(id: "r2d-demo-origin", title: "R2D 데모 출발지", address: "경기도 화성시 동탄대로", coordinate: .init(latitude: 37.235898, longitude: 127.035530))
    ]
}

public struct MockMapMatchingRepository: IMapMatchingRepository {
    public init() {}

    public func match(_ coordinate: Coordinate, heading: Double?, speedMps: Double?) async throws -> MatchedRoadPoint {
        let snapped = Coordinate(
            latitude: (coordinate.latitude * 100_000).rounded() / 100_000,
            longitude: (coordinate.longitude * 100_000).rounded() / 100_000
        )
        return .init(
            original: coordinate,
            matched: snapped,
            roadName: "R2D demo road",
            confidence: 0.92,
            distanceFromOriginalM: infrastructureDistance(coordinate, snapped)
        )
    }

    public func matchTrace(_ coordinates: [Coordinate]) async throws -> [MatchedRoadPoint] {
        try await coordinates.asyncMap { try await match($0, heading: nil, speedMps: nil) }
    }
}

public struct MockRouteOptimizationRepository: IRouteOptimizationRepository {
    public init() {}

    public func optimize(_ request: RouteOptimizationRequest) async throws -> RouteOptimizationResult {
        let totalLoad = request.stops.reduce(0) { $0 + $1.loadWeightKg }
        if let capacity = request.vehicleCapacityKg, totalLoad > capacity {
            throw IMPSRepositoryError.capacityExceeded
        }

        var current = request.origin
        var remaining = request.stops
        var ordered: [OptimizedRouteStop] = []

        while !remaining.isEmpty {
            let nextIndex = remaining.indices.min {
                infrastructureDistance(current, remaining[$0].coordinate) < infrastructureDistance(current, remaining[$1].coordinate)
            }!
            let next = remaining.remove(at: nextIndex)
            ordered.append(next)
            current = next.coordinate
        }

        let coordinates = [request.origin] + ordered.map(\.coordinate)
        let distance = zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + infrastructureDistance($1.0, $1.1) }
        let turns = ordered.enumerated().map { index, stop in
            Turn(coordinate: stop.coordinate, instruction: "\(index + 1)번째 목적지: \(stop.title)", distance: 0)
        }
        let route = Route(
            id: "imps-optimized-demo",
            polyline: coordinates,
            totalDistance: distance,
            totalDuration: max(60, distance / 4.5),
            turnList: turns,
            riskCells: []
        )
        return .init(orderedStops: ordered, route: route, totalLoadWeightKg: totalLoad)
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        for element in self {
            let value = try await transform(element)
            values.append(value)
        }
        return values
    }
}

private func infrastructureDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
    let dy = (b.latitude - a.latitude) * 111_320
    let dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * .pi / 180)
    return sqrt(dx * dx + dy * dy)
}
