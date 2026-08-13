import Foundation
import R2DCore

public struct IMPSGeocodingConfiguration: Sendable {
    public let appKey: String
    public let geocodingPathTemplate: String
    public let reverseGeocodingPathTemplate: String
    public let coordinateType: CoordinateType

    public init(
        appKey: String,
        geocodingPathTemplate: String = "/maps/v3.0/appkeys/{APPKEY}/coordinates",
        reverseGeocodingPathTemplate: String = "/maps/v3.0/appkeys/{APPKEY}/addresses",
        coordinateType: CoordinateType = .wgs84
    ) {
        self.appKey = appKey.trimmingIMPSAppKeySyntax
        self.geocodingPathTemplate = geocodingPathTemplate
        self.reverseGeocodingPathTemplate = reverseGeocodingPathTemplate
        self.coordinateType = coordinateType
    }

    public enum CoordinateType: String, Sendable {
        case tw = "0"
        case wgs84 = "1"
    }
}

public actor HTTPIMPSGeocodingRepository: IPlaceSearchRepository {
    private let client: HTTPClient
    private let configuration: IMPSGeocodingConfiguration

    public init(client: HTTPClient, configuration: IMPSGeocodingConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    public func geocode(_ query: String, near coordinate: Coordinate?) async throws -> [PlaceSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw IMPSRepositoryError.emptyQuery }

        var items: [URLQueryItem] = [
            .init(name: "query", value: normalized),
            .init(name: "coordtype", value: configuration.coordinateType.rawValue),
            .init(name: "startposition", value: "0"),
            .init(name: "reqcount", value: "10"),
            .init(name: "addrext", value: "2")
        ]

        if let coordinate {
            items.append(.init(name: "posX", value: String(coordinate.longitude)))
            items.append(.init(name: "posY", value: String(coordinate.latitude)))
        }

        let path = makePath(template: configuration.geocodingPathTemplate, queryItems: items)
        print("R2D iMPS geocode request: \(redactAppKey(in: path))")
        let response = try await client.send(.init(path: path, method: .get))
        print("R2D iMPS geocode HTTP status: \(response.statusCode)")
        let payload = try decodeGeocoding(response.body)
        let results = payload.address.adm.map(PlaceSearchResult.init(impsAddress:))
        print("R2D iMPS geocode response: query=\(normalized) count=\(results.count)")
        return results
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceSearchResult? {
        let items: [URLQueryItem] = [
            .init(name: "posX", value: String(coordinate.longitude)),
            .init(name: "posY", value: String(coordinate.latitude)),
            .init(name: "coordtype", value: configuration.coordinateType.rawValue)
        ]
        let path = makePath(template: configuration.reverseGeocodingPathTemplate, queryItems: items)
        print("R2D iMPS reverse geocode request: \(redactAppKey(in: path))")
        let response = try await client.send(.init(path: path, method: .get))
        print("R2D iMPS reverse geocode HTTP status: \(response.statusCode)")
        let location = try decodeReverseGeocoding(response.body).location
        guard location.adm != nil || location.admAddress != nil || location.legalAddress != nil else { return nil }
        return PlaceSearchResult(impsLocation: location)
    }

    private func makePath(template: String, queryItems: [URLQueryItem]) -> String {
        let path = template.replacingOccurrences(of: "{APPKEY}", with: configuration.appKey)
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string ?? path
    }

    private func redactAppKey(in path: String) -> String {
        path.replacingOccurrences(of: configuration.appKey, with: "<APPKEY>")
    }

    private func decodeGeocoding(_ data: Data) throws -> IMPSGeocodingResponse {
        let decoder = JSONDecoder()
        do {
            let payload = try decoder.decode(IMPSGeocodingResponse.self, from: data)
            guard payload.header.isSuccessful, payload.address.result else {
                print("R2D iMPS geocode rejected: code=\(payload.header.resultCode.map(String.init) ?? "nil") message=\(payload.header.resultMessage ?? "nil") body=\(bodyPreview(data))")
                throw IMPSRepositoryError.invalidResponse
            }
            return payload
        } catch let error as IMPSRepositoryError {
            throw error
        } catch {
            if let empty = try? decoder.decode(IMPSEmptyResultResponse.self, from: data),
               !empty.header.isSuccessful,
               empty.header.resultCode == 100 {
                print("R2D iMPS geocode no result: message=\(empty.header.resultMessage ?? "nil")")
                return .init(header: empty.header, address: .init(result: false, totalcount: 0, admtotalcount: 0, admcount: 0, adm: []))
            }
            print("R2D iMPS geocode decode failed: \(error) body=\(bodyPreview(data))")
            throw IMPSRepositoryError.invalidResponse
        }
    }

    private func decodeReverseGeocoding(_ data: Data) throws -> IMPSReverseGeocodingResponse {
        let decoder = JSONDecoder()
        do {
            let payload = try decoder.decode(IMPSReverseGeocodingResponse.self, from: data)
            guard payload.header.isSuccessful, payload.location.result else {
                print("R2D iMPS reverse geocode rejected: code=\(payload.header.resultCode.map(String.init) ?? "nil") message=\(payload.header.resultMessage ?? "nil") body=\(bodyPreview(data))")
                throw IMPSRepositoryError.invalidResponse
            }
            return payload
        } catch let error as IMPSRepositoryError {
            throw error
        } catch {
            print("R2D iMPS reverse geocode decode failed: \(error) body=\(bodyPreview(data))")
            throw IMPSRepositoryError.invalidResponse
        }
    }

    private func bodyPreview(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        return String(raw.prefix(1_000))
    }
}

private struct IMPSGeocodingResponse: Decodable {
    let header: Header
    let address: Address

    struct Header: Decodable {
        let isSuccessful: Bool
        let resultCode: Int?
        let resultMessage: String?
    }

    struct Address: Decodable {
        let result: Bool
        let totalcount: Int?
        let admtotalcount: Int?
        let admcount: Int?
        let adm: [AdministrativeAddress]
    }
}

private struct IMPSEmptyResultResponse: Decodable {
    let header: IMPSGeocodingResponse.Header
}

private struct IMPSReverseGeocodingResponse: Decodable {
    let header: IMPSGeocodingResponse.Header
    let location: Location

    struct Location: Decodable {
        let result: Bool
        let hasAdmAddress: Bool?
        let adm: ReverseAddress?
        let admAddress: NestedAddress?
        let legalAddress: NestedAddress?

        enum CodingKeys: String, CodingKey {
            case result, adm
            case hasAdmAddress = "hasAdmAddress"
            case admAddress = "adm_address"
            case legalAddress = "legal_address"
        }
    }
}

private struct ReverseAddress: Decodable {
    let posx: String
    let posy: String
    let address: String?
    let jibun: String?
    let roadname: String?
    let roadjibun: String?
    let admcode: String?
    let postcode: String?
    let bldname: String?
    let bldnum: String?
}

private struct NestedAddress: Decodable {
    let address: String?
    let jibun: String?
    let cutAddress: String?
    let admcode: String?
    let addressCategory1: String?
    let addressCategory2: String?
    let addressCategory3: String?
    let addressCategory4: String?

    enum CodingKeys: String, CodingKey {
        case address, jibun, admcode
        case cutAddress = "cut_address"
        case addressCategory1 = "address_category1"
        case addressCategory2 = "address_category2"
        case addressCategory3 = "address_category3"
        case addressCategory4 = "address_category4"
    }
}

private struct AdministrativeAddress: Decodable {
    let posx: String
    let posy: String
    let admcode: String?
    let address: String?
    let addressSido: String?
    let addressGu: String?
    let addressDong: String?
    let addressHaeng: String?
    let legalcode: String?
    let haengcode: String?
    let jibun: String?
    let roadname: String?
    let roadjibun: String?
    let postcode: String?
    let buildname: String?
    let accuracy: Int?
    let distance: Int?

    enum CodingKeys: String, CodingKey {
        case posx, posy, admcode, address, legalcode, haengcode, jibun, roadname, roadjibun, postcode, buildname, accuracy, distance
        case addressSido = "address_sido"
        case addressGu = "address_gu"
        case addressDong = "address_dong"
        case addressHaeng = "address_haeng"
    }
}

private extension PlaceSearchResult {
    init(impsAddress value: AdministrativeAddress) {
        let latitude = Double(value.posy) ?? 0
        let longitude = Double(value.posx) ?? 0
        let title = value.buildname?.nilIfEmpty
            ?? value.roadname?.nilIfEmpty
            ?? value.address?.nilIfEmpty
            ?? "주소 검색 결과"
        let address = value.address?.nilIfEmpty
            ?? [value.addressSido, value.addressGu, value.addressDong].compactMap { $0?.nilIfEmpty }.joined(separator: " ")
        self.init(
            id: value.admcode?.nilIfEmpty ?? "\(latitude),\(longitude)",
            title: title,
            address: address,
            coordinate: .init(latitude: latitude, longitude: longitude),
            source: "imps-geocoding"
        )
    }

    init(impsLocation value: IMPSReverseGeocodingResponse.Location) {
        let adm = value.adm
        let administrative = value.admAddress
        let legal = value.legalAddress
        let latitude = Double(adm?.posy ?? "") ?? 0
        let longitude = Double(adm?.posx ?? "") ?? 0
        let address = administrative?.address?.nilIfEmpty
            ?? adm?.address?.nilIfEmpty
            ?? legal?.address?.nilIfEmpty
            ?? [administrative?.addressCategory1, administrative?.addressCategory2, administrative?.addressCategory3]
                .compactMap { $0?.nilIfEmpty }
                .joined(separator: " ")
        let title = adm?.bldname?.nilIfEmpty
            ?? adm?.roadname?.nilIfEmpty
            ?? address.nilIfEmpty
            ?? "주소 변환 결과"
        self.init(
            id: adm?.admcode?.nilIfEmpty ?? administrative?.admcode?.nilIfEmpty ?? "\(latitude),\(longitude)",
            title: title,
            address: address,
            coordinate: .init(latitude: latitude, longitude: longitude),
            source: "imps-reverse-geocoding"
        )
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmingIMPSAppKeySyntax: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "{}").union(.whitespacesAndNewlines))
    }
}
