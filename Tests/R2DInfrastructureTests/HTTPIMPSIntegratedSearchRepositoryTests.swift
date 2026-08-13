import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func httpIMPSIntegratedSearchBuildsSearchesQueryAndDecodesFlexiblePlaceFields() async throws {
    let body = Data(
        #"""
        {
          "header": {
            "isSuccessful": true,
            "resultCode": 0,
            "resultMessage": "Success"
          },
          "search": {
            "result": true,
            "pois": [
              {
                "poiId": "station-001",
                "name": "신당역",
                "address": "서울특별시 중구 퇴계로",
                "posx": "127.01648",
                "posy": "37.56564"
              }
            ]
          }
        }
        """#.utf8
    )
    let transport = IMPSIntegratedRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imps.example.test")!, transport: transport)
    let repository = HTTPIMPSIntegratedSearchRepository(
        client: client,
        configuration: .init(appKey: "{test-key }")
    )

    let results = try await repository.geocode("신당역", near: .init(latitude: 37.56, longitude: 127.01))

    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/maps/v3.0/appkeys/test-key/searches")
    let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(queryItems.value(named: "query") == "신당역")
    #expect(queryItems.value(named: "coordtype") == "1")
    #expect(queryItems.value(named: "startposition") == "0")
    #expect(queryItems.value(named: "reqcount") == "10")
    #expect(queryItems.value(named: "posX") == "127.01")
    #expect(queryItems.value(named: "posY") == "37.56")

    let result = try #require(results.first)
    #expect(result.title == "신당역")
    #expect(result.address == "서울특별시 중구 퇴계로")
    #expect(result.coordinate == .init(latitude: 37.56564, longitude: 127.01648))
    #expect(result.source == "imps-integrated-search")
}

@Test func compositePlaceSearchFallsBackToGeocodingWhenIntegratedSearchReturnsEmpty() async throws {
    let primary = EmptyPlaceSearchRepository()
    let fallback = FixedPlaceSearchRepository(
        result: .init(
            id: "address-1",
            title: "삼환하이펙스A동",
            address: "경기도 성남시 분당구 삼평동",
            coordinate: .init(latitude: 37.402109, longitude: 127.11065),
            source: "imps-geocoding"
        )
    )
    let repository = CompositePlaceSearchRepository(primary: primary, fallback: fallback)

    let results = try await repository.geocode("경기도 성남시 분당구 판교역로 240", near: nil)

    #expect(results.map(\.source) == ["imps-geocoding"])
}

@Test func compositePlaceSearchUsesGeocodingFirstForAddressLikeQueries() async throws {
    let primary = FixedPlaceSearchRepository(
        result: .init(
            id: "poi-1",
            title: "가로판매",
            address: "서울특별시 종로구 종로3가",
            coordinate: .init(latitude: 37.5701, longitude: 126.9911),
            source: "imps-integrated-search"
        )
    )
    let fallback = FixedPlaceSearchRepository(
        result: .init(
            id: "address-1",
            title: "서울 돈화문로",
            address: "서울특별시 종로구 돈화문로",
            coordinate: .init(latitude: 37.5763, longitude: 126.9916),
            source: "imps-geocoding"
        )
    )
    let repository = CompositePlaceSearchRepository(primary: primary, fallback: fallback)

    let results = try await repository.geocode("서울 종로구 돈화문로 24-3", near: nil)

    #expect(results.map(\.source) == ["imps-geocoding"])
}

private actor IMPSIntegratedRecordingTransport: HTTPTransport {
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

private struct EmptyPlaceSearchRepository: IPlaceSearchRepository {
    func geocode(_ query: String, near coordinate: Coordinate?) async throws -> [PlaceSearchResult] { [] }
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceSearchResult? { nil }
}

private struct FixedPlaceSearchRepository: IPlaceSearchRepository {
    let result: PlaceSearchResult
    func geocode(_ query: String, near coordinate: Coordinate?) async throws -> [PlaceSearchResult] { [result] }
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceSearchResult? { result }
}

private extension [URLQueryItem] {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
