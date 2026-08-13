import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func httpIMPSMapMatchingPostsDocumentedBodyAndDecodesMatchedRoadPoints() async throws {
    let body = Data(
        #"""
        {
          "header": {
            "isSuccessful": true,
            "resultCode": 0,
            "resultMessage": "Success"
          },
          "roadMatch": {
            "userId": "r2d-user",
            "tollFee": 1200,
            "totalDistance": 4038,
            "totalPointCount": 2,
            "safeDrivingScore": 71,
            "safeDrivingEvents": {
              "accelEvents": [
                { "startTimestamp": 1669848945, "endTimestamp": 1669848950, "eventLevel": 2 }
              ],
              "decelEvents": [],
              "overspeedEvents": []
            },
            "paths": [
              {
                "x": 127.105399,
                "y": 37.5124518,
                "errorDistance": 5.0,
                "angle": 62,
                "roadAttr": 1,
                "roadType": 5,
                "speed": 73,
                "speedLimit": 30,
                "datetime": "2026-01-01 10:05:22"
              },
              {
                "x": 127.106,
                "y": 37.513,
                "errorDistance": 20.0,
                "angle": 64,
                "roadAttr": 1,
                "roadType": 5,
                "speed": 70,
                "speedLimit": 30,
                "datetime": "2026-01-01 10:05:23"
              }
            ]
          }
        }
        """#.utf8
    )
    let transport = IMPSMapMatchingRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imps.example.test")!, transport: transport)
    let repository = HTTPIMPSMapMatchingRepository(
        client: client,
        configuration: .init(appKey: "{test-key }", userID: "r2d-user")
    )
    let original = [
        Coordinate(latitude: 37.5124, longitude: 127.1053),
        Coordinate(latitude: 37.5129, longitude: 127.1059)
    ]

    let matched = try await repository.matchTrace(original)

    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/maps/v3.0/appkeys/test-key/map-match")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let json = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
    #expect(json?["userId"] as? String == "r2d-user")
    let paths = try #require(json?["paths"] as? [[String: Any]])
    #expect(paths.count == 2)
    #expect(paths[0]["x"] as? Double == 127.1053)
    #expect(paths[0]["y"] as? Double == 37.5124)
    #expect(paths[0]["speed"] as? Int == 0)
    #expect(paths[0]["angle"] as? Int == 0)

    #expect(matched.count == 2)
    #expect(matched[0].original == original[0])
    #expect(matched[0].matched == .init(latitude: 37.5124518, longitude: 127.105399))
    #expect(matched[0].distanceFromOriginalM == 5)
    #expect(matched[0].confidence == 0.9)
    #expect(matched[1].confidence == 0.6)
}

@Test func httpIMPSMapMatchingSinglePointConvertsMetersPerSecondToKilometersPerHour() async throws {
    let body = Data(
        #"""
        {
          "header": { "isSuccessful": true, "resultCode": 0, "resultMessage": "Success" },
          "roadMatch": {
            "userId": "r2d-user",
            "paths": [
              { "x": 127.105399, "y": 37.5124518, "errorDistance": 0.0 }
            ]
          }
        }
        """#.utf8
    )
    let transport = IMPSMapMatchingRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imps.example.test")!, transport: transport)
    let repository = HTTPIMPSMapMatchingRepository(
        client: client,
        configuration: .init(appKey: "test-key", userID: "r2d-user")
    )

    _ = try await repository.match(.init(latitude: 37.5124, longitude: 127.1053), heading: 62, speedMps: 10)

    let request = try #require(await transport.requests.first)
    let json = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
    let paths = try #require(json?["paths"] as? [[String: Any]])
    #expect(paths[0]["speed"] as? Int == 36)
    #expect(paths[0]["angle"] as? Int == 62)
}

private actor IMPSMapMatchingRecordingTransport: HTTPTransport {
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
