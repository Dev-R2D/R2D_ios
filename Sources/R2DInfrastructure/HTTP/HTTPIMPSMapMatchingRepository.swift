import Foundation
import R2DCore

public struct IMPSMapMatchingConfiguration: Sendable {
    public let appKey: String
    public let pathTemplate: String
    public let userID: String

    public init(
        appKey: String,
        pathTemplate: String = "/maps/v3.0/appkeys/{APPKEY}/map-match",
        userID: String = "r2d-mobile"
    ) {
        self.appKey = appKey.trimmingIMPSMapMatchingAppKeySyntax
        self.pathTemplate = pathTemplate
        self.userID = userID
    }
}

public actor HTTPIMPSMapMatchingRepository: IMapMatchingRepository {
    private let client: HTTPClient
    private let configuration: IMPSMapMatchingConfiguration

    public init(client: HTTPClient, configuration: IMPSMapMatchingConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    public func match(_ coordinate: Coordinate, heading: Double?, speedMps: Double?) async throws -> MatchedRoadPoint {
        let point = MapMatchRequestPoint(
            time: Int(Date().timeIntervalSince1970),
            x: coordinate.longitude,
            y: coordinate.latitude,
            speed: speedMps.map { Int(($0 * 3.6).rounded()) } ?? 0,
            angle: heading.map { Int($0.rounded()) } ?? 0
        )
        return try await send(points: [(coordinate, point)]).first ?? {
            throw IMPSRepositoryError.noResult
        }()
    }

    public func matchTrace(_ coordinates: [Coordinate]) async throws -> [MatchedRoadPoint] {
        guard !coordinates.isEmpty else { return [] }
        let start = Int(Date().timeIntervalSince1970)
        let points = coordinates.enumerated().map { index, coordinate in
            (
                coordinate,
                MapMatchRequestPoint(
                    time: start + index,
                    x: coordinate.longitude,
                    y: coordinate.latitude,
                    speed: 0,
                    angle: 0
                )
            )
        }
        return try await send(points: points)
    }

    private func send(points: [(Coordinate, MapMatchRequestPoint)]) async throws -> [MatchedRoadPoint] {
        let body = try JSONEncoder().encode(MapMatchRequestBody(userId: configuration.userID, paths: points.map(\.1)))
        let response = try await client.send(.init(
            path: makePath(),
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body
        ))
        let payload = try decode(response.body)
        let matched = payload.roadMatch.paths
        guard !matched.isEmpty else { throw IMPSRepositoryError.noResult }
        return matched.enumerated().map { index, value in
            let original = points.indices.contains(index) ? points[index].0 : .init(latitude: value.y, longitude: value.x)
            return MatchedRoadPoint(
                original: original,
                matched: .init(latitude: value.y, longitude: value.x),
                roadName: nil,
                confidence: confidence(from: value.errorDistance),
                distanceFromOriginalM: value.errorDistance ?? infrastructureMapMatchDistance(original, .init(latitude: value.y, longitude: value.x))
            )
        }
    }

    private func makePath() -> String {
        configuration.pathTemplate.replacingOccurrences(of: "{APPKEY}", with: configuration.appKey)
    }

    private func decode(_ data: Data) throws -> IMPSMapMatchResponse {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(IMPSMapMatchResponse.self, from: data),
              payload.header.isSuccessful
        else { throw IMPSRepositoryError.invalidResponse }
        return payload
    }

    private func confidence(from errorDistance: Double?) -> Double {
        guard let errorDistance else { return 0.8 }
        return max(0, min(1, 1 - (errorDistance / 50)))
    }
}

private struct MapMatchRequestBody: Encodable {
    let userId: String
    let paths: [MapMatchRequestPoint]
}

private struct MapMatchRequestPoint: Encodable {
    let time: Int
    let x: Double
    let y: Double
    let speed: Int
    let angle: Int
}

private struct IMPSMapMatchResponse: Decodable {
    let header: Header
    let roadMatch: RoadMatch

    struct Header: Decodable {
        let isSuccessful: Bool
        let resultCode: Int?
        let resultMessage: String?
    }

    struct RoadMatch: Decodable {
        let userId: String?
        let tollFee: Int?
        let totalDistance: Int?
        let totalPointCount: Int?
        let safeDrivingScore: Int?
        let paths: [MatchedPath]
        let safeDrivingEvents: SafeDrivingEvents?

        enum CodingKeys: String, CodingKey {
            case userId, paths
            case tollFee
            case totalDistance
            case totalPointCount
            case safeDrivingScore
            case safeDrivingEvents
        }
    }

    struct SafeDrivingEvents: Decodable {
        let accelEvents: [DrivingEvent]?
        let decelEvents: [DrivingEvent]?
        let overspeedEvents: [DrivingEvent]?
    }

    struct DrivingEvent: Decodable {
        let startTimestamp: Int?
        let endTimestamp: Int?
        let eventLevel: Int?
    }

    struct MatchedPath: Decodable {
        let x: Double
        let y: Double
        let errorDistance: Double?
        let angle: Int?
        let roadAttr: Int?
        let roadType: Int?
        let speed: Int?
        let speedLimit: Int?
        let datetime: String?
    }
}

private extension String {
    var trimmingIMPSMapMatchingAppKeySyntax: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "{}").union(.whitespacesAndNewlines))
    }
}

private func infrastructureMapMatchDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
    let dy = (b.latitude - a.latitude) * 111_320
    let dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * .pi / 180)
    return sqrt(dx * dx + dy * dy)
}
