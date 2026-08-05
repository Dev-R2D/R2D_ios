import Foundation
import R2DCore

public struct RiskLayerHTTPRepository: IRiskLayerRepository {
    private let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }

    public func fetchCells(boundingBox: GeoBoundingBox, zoomLevel: Int?, knownLayerVersion: String?) async throws -> RiskLayerSnapshot {
        var components = URLComponents(); components.path = "/v1/map/cells"; components.queryItems = [
            .init(name: "min_lat", value: String(boundingBox.minLatitude)), .init(name: "min_lon", value: String(boundingBox.minLongitude)), .init(name: "max_lat", value: String(boundingBox.maxLatitude)), .init(name: "max_lon", value: String(boundingBox.maxLongitude))
        ]
        if let zoomLevel { components.queryItems?.append(.init(name: "zoom", value: String(zoomLevel))) }
        if let knownLayerVersion { components.queryItems?.append(.init(name: "layer_version", value: knownLayerVersion)) }
        return try await request(.init(path: components.string ?? "/v1/map/cells", method: .get), knownVersion: knownLayerVersion)
    }

    public func fetchCells(along route: Route, corridorWidthM: Double, knownLayerVersion: String?) async throws -> RiskLayerSnapshot {
        let body = AlongRouteBody(routeID: route.id, coordinates: route.polyline, corridorWidthM: corridorWidthM, layerVersion: knownLayerVersion)
        return try await request(.init(path: "/v1/map/cells/along-route", method: .post, headers: ["Content-Type": "application/json"], body: try encoder.encode(body)), knownVersion: knownLayerVersion)
    }

    public func fetchCell(id: String) async throws -> RoadCell {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        do { let response = try await client.send(.init(path: "/v1/map/cells/\(escaped)", method: .get)); return try decodeCell(response.body) }
        catch { throw normalize(error) }
    }

    private func request(_ request: HTTPRequest, knownVersion: String?) async throws -> RiskLayerSnapshot {
        do {
            let response = try await client.send(request, allowingStatusCodes: [304])
            if response.statusCode == 304 { return .init(layerVersion: knownVersion ?? "", generatedAt: Date(timeIntervalSince1970: 0), expiresAt: nil, cells: [], notModified: true) }
            let dto = try decoder.decode(SnapshotDTO.self, from: response.body)
            return .init(layerVersion: dto.layerVersion, generatedAt: dto.generatedAt, expiresAt: dto.expiresAt, cells: try dto.cells.map(convert), notModified: dto.notModified)
        } catch { throw normalize(error) }
    }
    private func decodeCell(_ data: Data) throws -> RoadCell { try convert(decoder.decode(CellDTO.self, from: data)) }
    private func convert(_ dto: CellDTO) throws -> RoadCell { .init(id: dto.cellId, geometry: try parseWKT(dto.geometry), dataState: dto.dataState, riskState: dto.riskState, riskScore: dto.riskScore, confidence: dto.confidence, lastObservedAt: dto.lastObservedAt, validUntil: dto.validUntil, observationCount: dto.observationCount, independentDeviceCount: dto.independentDeviceCount, cellVersion: dto.cellVersion, layerVersion: dto.layerVersion) }
    private var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; value.keyDecodingStrategy = .convertFromSnakeCase; return value }
    private var encoder: JSONEncoder { let value = JSONEncoder(); value.keyEncodingStrategy = .convertToSnakeCase; return value }
}

private struct AlongRouteBody: Encodable { let routeID: String, coordinates: [Coordinate], corridorWidthM: Double, layerVersion: String? }
private struct SnapshotDTO: Decodable { let layerVersion: String, generatedAt: Date, expiresAt: Date?, cells: [CellDTO], notModified: Bool }
private struct CellDTO: Decodable { let cellId: String, geometry: String, dataState: DataState, riskState: RiskState, riskScore: Int, confidence: Double, lastObservedAt: Date?, validUntil: Date?, observationCount: Int, independentDeviceCount: Int, cellVersion: String, layerVersion: String }

private func parseWKT(_ value: String) throws -> RoadGeometry {
    guard let start = value.firstIndex(of: "("), let end = value.lastIndex(of: ")"), start < end else { throw RiskLayerError.invalidGeometry }
    let coordinates = value[value.index(after: start)..<end].replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").split(separator: ",").compactMap { part -> Coordinate? in
        let values = part.split(whereSeparator: { $0 == " " }).compactMap { Double($0) }; guard values.count >= 2 else { return nil }; return .init(latitude: values[1], longitude: values[0])
    }
    guard !coordinates.isEmpty else { throw RiskLayerError.invalidGeometry }
    if value.uppercased().hasPrefix("POINT"), let first = coordinates.first { return .point(first) }
    if value.uppercased().hasPrefix("LINESTRING") { return .polyline(coordinates) }
    throw RiskLayerError.invalidGeometry
}

private func normalize(_ error: Error) -> RiskLayerError {
    if let value = error as? RiskLayerError { return value }
    guard let value = error as? TelemetryUploadError else { return .invalidResponse }
    switch value { case .offline: return .offline; case .timeout: return .timeout; case .unauthorized: return .unauthorized; case .forbidden: return .forbidden; case .rateLimited(let retry): return .rateLimited(retryAfter: retry); case .serverFailure(let status): return .serverFailure(statusCode: status); default: return .invalidResponse }
}

public struct UnavailableRiskLayerRepository: IRiskLayerRepository {
    public init() {}
    public func fetchCells(boundingBox: GeoBoundingBox, zoomLevel: Int?, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { throw RiskLayerError.offline }
    public func fetchCells(along route: Route, corridorWidthM: Double, knownLayerVersion: String?) async throws -> RiskLayerSnapshot { throw RiskLayerError.offline }
    public func fetchCell(id: String) async throws -> RoadCell { throw RiskLayerError.offline }
}
