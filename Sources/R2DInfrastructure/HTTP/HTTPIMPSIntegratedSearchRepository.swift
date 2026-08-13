import Foundation
import R2DCore

public struct IMPSIntegratedSearchConfiguration: Sendable {
    public let appKey: String
    public let pathTemplate: String
    public let coordinateType: String

    public init(
        appKey: String,
        pathTemplate: String = "/maps/v3.0/appkeys/{APPKEY}/searches",
        coordinateType: String = "1"
    ) {
        self.appKey = appKey.trimmingIMPSAppKeySyntax
        self.pathTemplate = pathTemplate
        self.coordinateType = coordinateType
    }
}

public actor HTTPIMPSIntegratedSearchRepository: IPlaceSearchRepository {
    private let client: HTTPClient
    private let configuration: IMPSIntegratedSearchConfiguration

    public init(client: HTTPClient, configuration: IMPSIntegratedSearchConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    public func geocode(_ query: String, near coordinate: Coordinate?) async throws -> [PlaceSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw IMPSRepositoryError.emptyQuery }

        var items: [URLQueryItem] = [
            .init(name: "query", value: normalized),
            .init(name: "coordtype", value: configuration.coordinateType),
            .init(name: "startposition", value: "0"),
            .init(name: "reqcount", value: "10")
        ]
        if let coordinate {
            items.append(.init(name: "posX", value: String(coordinate.longitude)))
            items.append(.init(name: "posY", value: String(coordinate.latitude)))
        }

        let path = makePath(queryItems: items)
        print("R2D iMPS integrated search request: \(redactAppKey(in: path))")
        let response = try await client.send(.init(path: path, method: .get))
        print("R2D iMPS integrated search HTTP status: \(response.statusCode)")
        let results = try decodeSearchResults(response.body)
        print("R2D iMPS integrated search response: query=\(normalized) count=\(results.count)")
        return results
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceSearchResult? {
        nil
    }

    private func makePath(queryItems: [URLQueryItem]) -> String {
        let path = configuration.pathTemplate.replacingOccurrences(of: "{APPKEY}", with: configuration.appKey)
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string ?? path
    }

    private func decodeSearchResults(_ data: Data) throws -> [PlaceSearchResult] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("R2D iMPS integrated search decode failed: body=\(bodyPreview(data))")
            throw IMPSRepositoryError.invalidResponse
        }

        if let header = root["header"] as? [String: Any],
           header.bool("isSuccessful") == false,
           header.int("resultCode") == 100 {
            return []
        }

        let objects = collectResultObjects(from: root)
        let results = objects.compactMap(makePlaceSearchResult)
        if results.isEmpty {
            print("R2D iMPS integrated search produced no decodable places: body=\(bodyPreview(data))")
        }
        return results
    }

    private func collectResultObjects(from value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            let direct = makePlaceSearchResult(from: dictionary) == nil ? [] : [dictionary]
            return direct + dictionary.values.flatMap(collectResultObjects)
        }
        if let array = value as? [Any] {
            return array.flatMap(collectResultObjects)
        }
        return []
    }

    private func makePlaceSearchResult(from dictionary: [String: Any]) -> PlaceSearchResult? {
        guard let longitude = dictionary.double(firstOf: ["posx", "posX", "x", "lon", "lng", "longitude"]),
              let latitude = dictionary.double(firstOf: ["posy", "posY", "y", "lat", "latitude"])
        else { return nil }

        let title = dictionary.string(firstOf: [
            "name", "title", "poiName", "poiname", "placeName", "placename", "bldname", "buildname", "roadname"
        ]) ?? "통합 검색 결과"
        let address = dictionary.string(firstOf: [
            "address", "roadAddress", "road_address", "jibunAddress", "jibun_address", "newAddress", "fullAddress", "addr"
        ]) ?? title
        let id = dictionary.string(firstOf: ["id", "poiId", "poiid", "admcode", "legalcode"])
            ?? "\(latitude),\(longitude),\(title)"

        return .init(
            id: id,
            title: title,
            address: address,
            coordinate: .init(latitude: latitude, longitude: longitude),
            source: "imps-integrated-search"
        )
    }

    private func redactAppKey(in path: String) -> String {
        path.replacingOccurrences(of: configuration.appKey, with: "<APPKEY>")
    }

    private func bodyPreview(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        return String(raw.prefix(1_000))
    }
}

public actor CompositePlaceSearchRepository: IPlaceSearchRepository {
    private let primary: IPlaceSearchRepository
    private let fallback: IPlaceSearchRepository

    public init(primary: IPlaceSearchRepository, fallback: IPlaceSearchRepository) {
        self.primary = primary
        self.fallback = fallback
    }

    public func geocode(_ query: String, near coordinate: Coordinate?) async throws -> [PlaceSearchResult] {
        if looksLikeAddress(query) {
            let fallbackResults = try await fallback.geocode(query, near: coordinate)
            if !fallbackResults.isEmpty { return fallbackResults }
            return try await primary.geocode(query, near: coordinate)
        }

        let primaryResults = try await primary.geocode(query, near: coordinate)
        if !primaryResults.isEmpty { return primaryResults }
        return try await fallback.geocode(query, near: coordinate)
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceSearchResult? {
        try await fallback.reverseGeocode(coordinate)
    }

    private func looksLikeAddress(_ query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressHints = ["로", "길", "대로", "번길", "동", "구", "시", "군", "읍", "면", "리"]
        let hasAddressHint = addressHints.contains { text.contains($0) }
        let hasDigit = text.contains { $0.isNumber }
        return hasAddressHint && hasDigit
    }
}

private extension [String: Any] {
    func string(firstOf keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = self[key] as? CustomStringConvertible {
                let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    func double(firstOf keys: [String]) -> Double? {
        for key in keys {
            if let value = self[key] as? Double { return value }
            if let value = self[key] as? Int { return Double(value) }
            if let value = self[key] as? String, let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return number
            }
        }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        self[key] as? Bool
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }
}
