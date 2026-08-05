import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

private actor RiskTransport: HTTPTransport {
    var requests: [URLRequest] = [], responses: [HTTPResponse]
    init(_ responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResponse { requests.append(request); return responses.removeFirst() }
    func captured() -> [URLRequest] { requests }
}

private let roadCellJSON = #"{"cell_id":"cell-1","geometry":"LINESTRING(127.04 37.55,127.041 37.551)","data_state":"VERIFIED","risk_state":"CONFIRMED_DAMAGE","risk_score":92,"confidence":0.94,"last_observed_at":"2026-08-05T00:00:00Z","valid_until":"2026-08-06T00:00:00Z","observation_count":8,"independent_device_count":3,"cell_version":"c4","layer_version":"layer-2"}"#
private var riskSnapshotJSON: Data { Data("{\"layer_version\":\"layer-2\",\"generated_at\":\"2026-08-05T00:00:00Z\",\"expires_at\":\"2026-08-06T00:00:00Z\",\"cells\":[\(roadCellJSON)],\"not_modified\":false}".utf8) }
private func riskRepository(_ transport: RiskTransport) -> RiskLayerHTTPRepository { .init(client: .init(baseURL: URL(string: "https://risk.test")!, transport: transport)) }

@Test func bboxQueryAndLayerVersionAreEncoded() async throws {
    let transport = RiskTransport([.init(statusCode: 200, headers: [:], body: riskSnapshotJSON)]), repository = riskRepository(transport)
    _ = try await repository.fetchCells(boundingBox: .init(minLatitude: 37.1, minLongitude: 126.9, maxLatitude: 37.9, maxLongitude: 127.2), zoomLevel: 14, knownLayerVersion: "layer-1")
    let url = try #require(await transport.captured().first?.url?.absoluteString)
    #expect(url.contains("min_lat=37.1")); #expect(url.contains("max_lon=127.2")); #expect(url.contains("zoom=14")); #expect(url.contains("layer_version=layer-1"))
}

@Test func routeCorridorUsesPostBodyInsteadOfQueryPolyline() async throws {
    let transport = RiskTransport([.init(statusCode: 200, headers: [:], body: riskSnapshotJSON)]), repository = riskRepository(transport)
    let route = Route(id: "r1", polyline: [.init(latitude: 37.5, longitude: 127), .init(latitude: 37.6, longitude: 127.1)], totalDistance: 100, totalDuration: 20, turnList: [], riskCells: [])
    _ = try await repository.fetchCells(along: route, corridorWidthM: 35, knownLayerVersion: "layer-1")
    let request = try #require(await transport.captured().first); #expect(request.httpMethod == "POST"); #expect(request.url?.query == nil)
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self); #expect(body.contains("corridor_width_m")); #expect(body.contains("layer-1")); #expect(body.contains("coordinates"))
}

@Test func notModified304KeepsKnownVersion() async throws {
    let repository = riskRepository(RiskTransport([.init(statusCode: 304, headers: [:], body: Data())]))
    let value = try await repository.fetchCells(boundingBox: .init(minLatitude: 0, minLongitude: 0, maxLatitude: 1, maxLongitude: 1), zoomLevel: nil, knownLayerVersion: "same")
    #expect(value.notModified); #expect(value.layerVersion == "same"); #expect(value.cells.isEmpty)
}

@Test func roadCellDecodesStatesAndGeometry() async throws {
    let repository = riskRepository(RiskTransport([.init(statusCode: 200, headers: [:], body: Data(roadCellJSON.utf8))]))
    let cell = try await repository.fetchCell(id: "cell-1"); #expect(cell.dataState == .verified); #expect(cell.riskState == .confirmedDamage); #expect(cell.riskScore == 92); #expect(cell.geometry.coordinates.count == 2)
}

@Test func invalidRoadGeometryIsRejected() async {
    let invalid = Data(roadCellJSON.replacingOccurrences(of: "LINESTRING(127.04 37.55,127.041 37.551)", with: "INVALID").utf8)
    let repository = riskRepository(RiskTransport([.init(statusCode: 200, headers: [:], body: invalid)]))
    await #expect(throws: RiskLayerError.invalidGeometry) { try await repository.fetchCell(id: "cell-1") }
}

@Test func riskHTTPClassifiesAuthenticationRateLimitAndServerFailure() async {
    for (response, expected) in [(HTTPResponse(statusCode: 401, headers: [:], body: Data()), RiskLayerError.unauthorized), (HTTPResponse(statusCode: 429, headers: ["Retry-After":"7"], body: Data()), .rateLimited(retryAfter: 7)), (HTTPResponse(statusCode: 500, headers: [:], body: Data()), .serverFailure(statusCode: 500))] {
        let repository = riskRepository(RiskTransport([response]))
        await #expect(throws: expected) { try await repository.fetchCells(boundingBox: .init(minLatitude: 0, minLongitude: 0, maxLatitude: 1, maxLongitude: 1), zoomLevel: nil, knownLayerVersion: nil) }
    }
}

@Test func persistentRiskCacheSavesRestoresAndQuarantinesCorruption() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("risk-cache-\(UUID().uuidString)"), snapshot = try await riskRepository(RiskTransport([.init(statusCode: 200, headers: [:], body: riskSnapshotJSON)])).fetchCells(boundingBox: .init(minLatitude: 0, minLongitude: 0, maxLatitude: 1, maxLongitude: 1), zoomLevel: nil, knownLayerVersion: nil)
    var cache: PersistentRiskLayerCache? = try .init(root: root); try await cache?.save(snapshot, context: .route); cache = nil
    let restored = try PersistentRiskLayerCache(root: root); #expect(try await restored.load(.route) == snapshot); #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("metadata.json").path))
    try Data("broken".utf8).write(to: root.appendingPathComponent("latest-route.json"), options: .atomic); #expect(try await restored.load(.route) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.contains("corrupt") })
}
