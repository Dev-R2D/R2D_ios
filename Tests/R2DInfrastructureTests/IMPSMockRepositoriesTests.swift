import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func mockPlaceSearchGeocodesAndReverseGeocodes() async throws {
    let repository = MockPlaceSearchRepository()
    let results = try await repository.geocode("동탄역", near: nil)
    #expect(results.first?.id == "dongtan-station")

    let reverse = try await repository.reverseGeocode(.init(latitude: 37.2006, longitude: 127.0959))
    #expect(reverse?.id == "dongtan-station")
}

@Test func mockMapMatchingSnapsCoordinateAndReportsConfidence() async throws {
    let repository = MockMapMatchingRepository()
    let matched = try await repository.match(
        .init(latitude: 37.2358984, longitude: 127.0355304),
        heading: 90,
        speedMps: 5
    )
    #expect(matched.confidence > 0.9)
    #expect(matched.roadName == "R2D demo road")
    #expect(matched.matched.latitude == 37.2359)
}

@Test func mockRouteOptimizationOrdersStopsAndRejectsCapacityOverflow() async throws {
    let repository = MockRouteOptimizationRepository()
    let request = RouteOptimizationRequest(
        origin: .init(latitude: 37.235898, longitude: 127.035530),
        stops: [
            .init(id: "far", title: "먼 목적지", coordinate: .init(latitude: 37.260000, longitude: 127.080000), loadWeightKg: 2),
            .init(id: "near", title: "가까운 목적지", coordinate: .init(latitude: 37.236500, longitude: 127.036200), loadWeightKg: 1)
        ],
        vehicleCapacityKg: 5
    )

    let result = try await repository.optimize(request)
    #expect(result.orderedStops.first?.id == "near")
    #expect(result.route.polyline.count == 3)
    #expect(result.totalLoadWeightKg == 3)

    await #expect(throws: IMPSRepositoryError.capacityExceeded) {
        _ = try await repository.optimize(.init(origin: request.origin, stops: request.stops, vehicleCapacityKg: 2))
    }
}
