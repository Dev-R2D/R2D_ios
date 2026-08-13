import Foundation
import R2DCore

public struct IMPSRouteConfiguration: Sendable {
    public let appKey: String
    public let pathTemplate: String
    public let pedestrianPathTemplate: String
    public let option: RouteOption
    public let coordinateType: CoordinateType

    public init(
        appKey: String,
        pathTemplate: String = "/maps/v3.0/appkeys/{APPKEY}/route-normal",
        pedestrianPathTemplate: String = "/maps/v3.0/appkeys/{APPKEY}/route-pedestrian",
        option: RouteOption = .recommendation,
        coordinateType: CoordinateType = .wgs84
    ) {
        self.appKey = appKey.trimmingIMPSRouteAppKeySyntax
        self.pathTemplate = pathTemplate
        self.pedestrianPathTemplate = pedestrianPathTemplate
        self.option = option
        self.coordinateType = coordinateType
    }

    public enum RouteOption: String, Sendable {
        case realTraffic = "real_traffic"
        case realTrafficAlternative = "real_traffic2"
        case realTrafficFreeRoad = "real_traffic_freeroad"
        case shortDistancePriority = "short_distance_priority"
        case timePriority = "time_priority"
        case motorcycle = "motorcycle"
        case pm = "pm"
        case recommendation
        case highwayPriority = "highway_priority"
    }

    public enum PedestrianRouteOption: String, Sendable {
        case shortDistancePriority = "0"
        case recommendation = "1"
        case easyWay = "2"
        case timePriority = "3"
        case mainRoad = "4"

        init?(routeOption: String) {
            switch routeOption {
            case "pm_short_distance_priority": self = .shortDistancePriority
            case "pm", "pm_recommendation": self = .recommendation
            case "pm_easy_way": self = .easyWay
            case "pm_time_priority": self = .timePriority
            case "pm_main_road": self = .mainRoad
            default: return nil
            }
        }
    }

    public enum CoordinateType: String, Sendable {
        case tw
        case wgs84
    }
}

public actor HTTPIMPSRouteRepository: IRouteRepository {
    private let client: HTTPClient
    private let configuration: IMPSRouteConfiguration
    private var searchTask: Task<[Route], Error>?

    public init(client: HTTPClient, configuration: IMPSRouteConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    public func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] {
        try await searchRoute(origin: origin, destination: destination, option: nil)
    }

    public func searchRoute(origin: Coordinate, destination: Coordinate, option: String?) async throws -> [Route] {
        searchTask?.cancel()
        let task = Task<[Route], Error> {
            let request = try makeRequest(origin: origin, destination: destination, option: option)
            logRequest(request, option: option, origin: origin, destination: destination)
            let response = try await client.send(request)
            logResponse(response, option: option)
            try Task.checkCancellation()
            return [try decode(response.body, origin: origin, destination: destination, requestedOption: option)]
        }
        searchTask = task
        defer { searchTask = nil }
        return try await task.value
    }

    public func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route {
        guard let destination = route.polyline.last else { throw RouteRepositoryError.invalidRoute }
        let request = try makeRequest(origin: currentLocation, destination: destination, option: route.providerOption)
        logRequest(request, option: route.providerOption, origin: currentLocation, destination: destination)
        let response = try await client.send(request)
        logResponse(response, option: route.providerOption)
        return try decode(response.body, origin: currentLocation, destination: destination, requestedOption: route.providerOption)
    }

    public func cancelSearch() async {
        searchTask?.cancel()
        searchTask = nil
    }

    private func makeRequest(origin: Coordinate, destination: Coordinate, option: String? = nil) throws -> HTTPRequest {
        if let option, let pedestrianOption = IMPSRouteConfiguration.PedestrianRouteOption(routeOption: option) {
            let path = configuration.pedestrianPathTemplate.replacingOccurrences(of: "{APPKEY}", with: configuration.appKey)
            let body = PedestrianRouteRequest(
                option: pedestrianOption.rawValue,
                startX: String(origin.longitude),
                startY: String(origin.latitude),
                endX: String(destination.longitude),
                endY: String(destination.latitude),
                type: 0
            )
            let data = try JSONEncoder().encode(body)
            return .init(path: path, method: .post, headers: ["Content-Type": "application/json"], body: data)
        }
        return .init(path: makePath(origin: origin, destination: destination, option: option), method: .get)
    }

    private func makePath(origin: Coordinate, destination: Coordinate, option: String? = nil) -> String {
        let path = configuration.pathTemplate.replacingOccurrences(of: "{APPKEY}", with: configuration.appKey)
        let selectedOption = option.flatMap(IMPSRouteConfiguration.RouteOption.init(rawValue:))?.rawValue ?? configuration.option.rawValue
        var components = URLComponents()
        components.path = path
        components.queryItems = [
            .init(name: "option", value: selectedOption),
            .init(name: "startX", value: String(origin.longitude)),
            .init(name: "startY", value: String(origin.latitude)),
            .init(name: "endX", value: String(destination.longitude)),
            .init(name: "endY", value: String(destination.latitude)),
            .init(name: "coordType", value: configuration.coordinateType.rawValue)
        ]
        return components.string ?? path
    }

    private func decode(_ data: Data, origin: Coordinate, destination: Coordinate, requestedOption: String? = nil) throws -> Route {
        let decoder = JSONDecoder()
        let payload: IMPSRouteResponse
        do {
            payload = try decoder.decode(IMPSRouteResponse.self, from: data)
        } catch {
            NSLog("R2D iMPS route decode failed: option=%@ error=%@ body=%@", requestedOption ?? "default", String(describing: error), String(data: data, encoding: .utf8) ?? "<non-utf8>")
            throw RouteRepositoryError.invalidRoute
        }
        guard payload.header.isSuccessful else {
            NSLog(
                "R2D iMPS route API failed: option=%@ code=%@ message=%@ body=%@",
                requestedOption ?? "default",
                payload.header.resultCode.map(String.init) ?? "nil",
                payload.header.resultMessage ?? "nil",
                String(data: data, encoding: .utf8) ?? "<non-utf8>"
            )
            throw RouteRepositoryError.invalidRoute
        }

        let routeData = payload.route.data
        let pathCoordinates = routeData.paths.flatMap { path in
            path.coords.map { Coordinate(latitude: $0.y, longitude: $0.x) }
        }
        guard !pathCoordinates.isEmpty else { throw RouteRepositoryError.invalidRoute }

        let polyline = normalizedPolyline(pathCoordinates, origin: origin, destination: destination)
        let turns = routeData.paths.compactMap { path -> Turn? in
            guard let pointType = path.pointType, ["S", "V", "E"].contains(pointType),
                  let coordinate = path.coords.first
            else { return nil }
            let instruction = switch pointType {
            case "S": "출발"
            case "V": "경유지"
            case "E": "도착"
            default: "경로 지점"
            }
            return Turn(coordinate: .init(latitude: coordinate.y, longitude: coordinate.x), instruction: instruction, distance: Double(path.distance ?? 0))
        }

        let providerOption = requestedOption.flatMap(IMPSRouteConfiguration.PedestrianRouteOption.init(routeOption:)) == nil
            ? routeData.option
            : requestedOption
        let routeOptionID = providerOption ?? routeData.option
        return Route(
            id: "imps-\(routeOptionID)-\(origin.latitude),\(origin.longitude)-\(destination.latitude),\(destination.longitude)",
            polyline: polyline,
            totalDistance: Double(routeData.distance),
            totalDuration: TimeInterval(routeData.spendTime),
            providerOption: providerOption,
            tollFee: routeData.tollFee,
            taxiFare: routeData.taxiFare,
            totalTaxiFare: routeData.totalTaxiFare,
            isHighWay: routeData.isHighWay,
            turnList: turns,
            riskCells: []
        )
    }

    private func normalizedPolyline(_ coordinates: [Coordinate], origin: Coordinate, destination: Coordinate) -> [Coordinate] {
        var values = coordinates
        if values.first != origin { values.insert(origin, at: 0) }
        if values.last != destination { values.append(destination) }
        return values
    }

    private func logRequest(_ request: HTTPRequest, option: String?, origin: Coordinate, destination: Coordinate) {
        NSLog(
            "R2D iMPS route request: method=%@ path=%@ option=%@ origin=%.5f,%.5f destination=%.5f,%.5f",
            request.method.rawValue,
            request.path,
            option ?? "default",
            origin.latitude,
            origin.longitude,
            destination.latitude,
            destination.longitude
        )
    }

    private func logResponse(_ response: HTTPResponse, option: String?) {
        NSLog(
            "R2D iMPS route HTTP status: %d option=%@",
            response.statusCode,
            option ?? "default"
        )
    }
}

private struct PedestrianRouteRequest: Encodable {
    let option: String
    let startX: String
    let startY: String
    let endX: String
    let endY: String
    let type: Int
}

private struct IMPSRouteResponse: Decodable {
    let header: Header
    let route: RouteContainer

    struct Header: Decodable {
        let isSuccessful: Bool
        let resultCode: Int?
        let resultMessage: String?
    }

    struct RouteContainer: Decodable {
        let data: RouteData
    }

    struct RouteData: Decodable {
        let option: String
        let tollFee: Int?
        let taxiFare: Int?
        let totalTaxiFare: String?
        let spendTime: Int
        let distance: Int
        let isHighWay: Bool?
        let paths: [Path]

        enum CodingKeys: String, CodingKey {
            case option, taxiFare, distance, paths
            case tollFee = "toll_fee"
            case totalTaxiFare
            case spendTime = "spend_time"
            case isHighWay
        }
    }

    struct Path: Decodable {
        let coords: [RouteCoordinate]
        let speed: Int?
        let distance: Int?
        let spendTime: Int?
        let roadCode: Int?
        let trafficColor: String?
        let pointType: String?

        enum CodingKeys: String, CodingKey {
            case coords, speed, distance
            case spendTime = "spend_time"
            case roadCode = "road_code"
            case trafficColor = "traffic_color"
            case pointType = "point_type"
        }
    }

    struct RouteCoordinate: Decodable {
        let x: Double
        let y: Double
    }
}

private extension String {
    var trimmingIMPSRouteAppKeySyntax: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "{}").union(.whitespacesAndNewlines))
    }
}
