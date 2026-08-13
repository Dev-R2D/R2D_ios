import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func httpIMPSRouteBuildsDocumentedRouteNormalQueryAndDecodesPathCoordinates() async throws {
    let body = Data(
        #"""
        {
          "header": {
            "isSuccessful": true,
            "resultCode": 0,
            "resultMessage": "Success"
          },
          "route": {
            "data": {
              "option": "recommendation",
              "toll_fee": 3400,
              "taxiFare": 45000,
              "totalTaxiFare": "6500,11500",
              "spend_time": 3720,
              "distance": 72183,
              "isHighWay": true,
              "paths": [
                {
                  "coords": [
                    { "x": 127.110762, "y": 37.402184 },
                    { "x": 127.105399, "y": 37.5124518 }
                  ],
                  "speed": 85,
                  "distance": 120,
                  "spend_time": 2800,
                  "road_code": 1,
                  "traffic_color": "#fb3a76",
                  "point_type": "S"
                },
                {
                  "coords": [
                    { "x": 127.105399, "y": 37.5124518 },
                    { "x": 127.001, "y": 37.566 }
                  ],
                  "point_type": "E"
                }
              ]
            }
          }
        }
        """#.utf8
    )
    let transport = IMPSRouteRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imaps.example.test")!, transport: transport)
    let repository = HTTPIMPSRouteRepository(
        client: client,
        configuration: .init(appKey: "{test-key }")
    )

    let origin = Coordinate(latitude: 37.402184, longitude: 127.110762)
    let destination = Coordinate(latitude: 37.566, longitude: 127.001)
    let route = try #require(try await repository.searchRoute(origin: origin, destination: destination, option: "motorcycle").first)

    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/maps/v3.0/appkeys/test-key/route-normal")
    let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(queryItems.value(named: "option") == "motorcycle")
    #expect(queryItems.value(named: "startX") == "127.110762")
    #expect(queryItems.value(named: "startY") == "37.402184")
    #expect(queryItems.value(named: "endX") == "127.001")
    #expect(queryItems.value(named: "endY") == "37.566")
    #expect(queryItems.value(named: "coordType") == "wgs84")

    #expect(route.totalDistance == 72183)
    #expect(route.totalDuration == 3720)
    #expect(route.providerOption == "recommendation")
    #expect(route.tollFee == 3400)
    #expect(route.taxiFare == 45000)
    #expect(route.totalTaxiFare == "6500,11500")
    #expect(route.isHighWay == true)
    #expect(route.polyline.first == origin)
    #expect(route.polyline.last == destination)
    #expect(route.polyline.count == 4)
    #expect(route.turnList.map(\.instruction) == ["출발", "도착"])
}

@Test func httpIMPSRouteRefreshUsesCurrentLocationAndExistingDestination() async throws {
    let body = Data(
        #"""
        {
          "header": { "isSuccessful": true, "resultCode": 0, "resultMessage": "Success" },
          "route": {
            "data": {
              "option": "time_priority",
              "spend_time": 60,
              "distance": 500,
              "paths": [
                {
                  "coords": [
                    { "x": 127.2, "y": 37.2 },
                    { "x": 127.3, "y": 37.3 }
                  ]
                }
              ]
            }
          }
        }
        """#.utf8
    )
    let transport = IMPSRouteRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imaps.example.test")!, transport: transport)
    let repository = HTTPIMPSRouteRepository(
        client: client,
        configuration: .init(appKey: "test-key", option: .timePriority)
    )
    let current = Coordinate(latitude: 37.2, longitude: 127.2)
    let existing = Route(id: "old", polyline: [.init(latitude: 37.1, longitude: 127.1), .init(latitude: 37.3, longitude: 127.3)], totalDistance: 1000, totalDuration: 100, turnList: [], riskCells: [])

    let refreshed = try await repository.refreshRoute(existing, from: current)

    let request = try #require(await transport.requests.first)
    let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(queryItems.value(named: "option") == "time_priority")
    #expect(queryItems.value(named: "startX") == "127.2")
    #expect(queryItems.value(named: "startY") == "37.2")
    #expect(queryItems.value(named: "endX") == "127.3")
    #expect(queryItems.value(named: "endY") == "37.3")
    #expect(refreshed.totalDistance == 500)
}

@Test func httpIMPSRouteUsesPedestrianEndpointForPMRoutes() async throws {
    let body = Data(
        #"""
        {
          "header": { "isSuccessful": true, "resultCode": 0, "resultMessage": "Success" },
          "route": {
            "data": {
              "option": "recommendation",
              "spend_time": 261,
              "distance": 1100,
              "paths": [
                {
                  "coords": [
                    { "x": 126.981, "y": 37.551 },
                    { "x": 126.989, "y": 37.554 }
                  ],
                  "distance": 1100,
                  "spend_time": 261,
                  "point_type": "S",
                  "walk_type": 3,
                  "bicycle_type": 1
                }
              ]
            }
          }
        }
        """#.utf8
    )
    let transport = IMPSRouteRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imaps.example.test")!, transport: transport)
    let repository = HTTPIMPSRouteRepository(
        client: client,
        configuration: .init(appKey: "test-key")
    )

    let origin = Coordinate(latitude: 37.551, longitude: 126.981)
    let destination = Coordinate(latitude: 37.554, longitude: 126.989)
    let route = try #require(try await repository.searchRoute(origin: origin, destination: destination, option: "pm").first)

    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/maps/v3.0/appkeys/test-key/route-pedestrian")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let requestBody = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(json["option"] as? String == "1")
    #expect(json["startX"] as? String == "126.981")
    #expect(json["startY"] as? String == "37.551")
    #expect(json["endX"] as? String == "126.989")
    #expect(json["endY"] as? String == "37.554")
    #expect(json["type"] as? Int == 0)

    #expect(route.providerOption == "pm")
    #expect(route.totalDistance == 1100)
    #expect(route.totalDuration == 261)
}

private actor IMPSRouteRecordingTransport: HTTPTransport {
    let body: Data
    private(set) var requests: [URLRequest] = []

    init(body: Data) {
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return .init(statusCode: 200, headers: [:], body: body)
    }
}

private extension [URLQueryItem] {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
