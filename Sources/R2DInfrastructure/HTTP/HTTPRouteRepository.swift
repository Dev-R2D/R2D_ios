import Foundation
import R2DCore

public actor HTTPRouteRepository: IRouteRepository {
    private let client: HTTPClient
    private var searchTask: Task<[Route], Error>?
    private var activeSearchID: UUID?
    public init(client: HTTPClient) { self.client = client }

    public func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] {
        searchTask?.cancel()
        let searchID = UUID(); activeSearchID = searchID
        let client = self.client
        let task = Task<[Route], Error> {
            let body = try JSONEncoder().encode(RouteSearchBody(origin: origin, destination: destination))
            let response = try await client.send(.init(path: "/v1/routes/search", method: .post, headers: ["Content-Type": "application/json"], body: body))
            try Task.checkCancellation()
            do { return try routeDecoder.decode(RouteSearchResponse.self, from: response.body).routes } catch { throw TelemetryUploadError.invalidResponse }
        }
        searchTask = task
        do {
            let routes = try await task.value
            if activeSearchID == searchID { searchTask = nil; activeSearchID = nil }
            return routes
        } catch {
            if activeSearchID == searchID { searchTask = nil; activeSearchID = nil }
            throw error
        }
    }

    public func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route {
        let body = try JSONEncoder().encode(RouteRefreshBody(currentLocation: currentLocation))
        let id = route.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? route.id
        let response = try await client.send(.init(path: "/v1/routes/\(id)/refresh", method: .post, headers: ["Content-Type": "application/json"], body: body))
        do { return try routeDecoder.decode(Route.self, from: response.body) } catch { throw TelemetryUploadError.invalidResponse }
    }

    public func cancelSearch() async { searchTask?.cancel(); searchTask = nil; activeSearchID = nil }
}

private let routeDecoder: JSONDecoder = { let value = JSONDecoder(); value.keyDecodingStrategy = .convertFromSnakeCase; return value }()
private struct RouteSearchBody: Encodable { let origin, destination: Coordinate }
private struct RouteRefreshBody: Encodable { let currentLocation: Coordinate; enum CodingKeys: String, CodingKey { case currentLocation = "current_location" } }
private struct RouteSearchResponse: Decodable { let routes: [Route] }

public struct UnavailableRouteRepository: IRouteRepository {
    public init() {}
    public func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] { throw RouteRepositoryError.unavailable }
    public func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route { throw RouteRepositoryError.unavailable }
    public func cancelSearch() async {}
}
