import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func httpIMPSGeocodingBuildsDocumentedQueryAndDecodesAddressFields() async throws {
    let body = Data(
        #"""
        {
          "header": {
            "isSuccessful": true,
            "resultCode": 0,
            "resultMessage": "Success"
          },
          "address": {
            "result": true,
            "totalcount": 1,
            "admtotalcount": 1,
            "admcount": 1,
            "adm": [
              {
                "type": 3,
                "posx": "127.11065",
                "posy": "37.402109",
                "admcode": "4113510900",
                "address": "경기도 성남시 분당구 삼평동",
                "address_sido": "경기도",
                "address_gu": "성남시 분당구",
                "address_dong": "삼평동",
                "address_haeng": "삼평동",
                "legalcode": "4113510900",
                "haengcode": "4113565500",
                "jibun": "678",
                "roadname": "경기도 성남시 분당구 판교역로",
                "roadjibun": "240",
                "postcode": "13493",
                "buildname": "삼환하이펙스A동",
                "accuracy": 0,
                "distance": 12
              }
            ]
          }
        }
        """#.utf8
    )
    let transport = IMPSRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imps.example.test")!, transport: transport)
    let repository = HTTPIMPSGeocodingRepository(
        client: client,
        configuration: .init(appKey: "{test-key }")
    )

    let results = try await repository.geocode(
        "서울 종로구 돈화문로 24-3",
        near: .init(latitude: 37.402159, longitude: 127.11075)
    )

    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/maps/v3.0/appkeys/test-key/coordinates")
    let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(queryItems.value(named: "query") == "서울 종로구 돈화문로 24-3")
    #expect(queryItems.value(named: "coordtype") == "1")
    #expect(queryItems.value(named: "startposition") == "0")
    #expect(queryItems.value(named: "reqcount") == "10")
    #expect(queryItems.value(named: "addrext") == "2")
    #expect(queryItems.value(named: "posX") == "127.11075")
    #expect(queryItems.value(named: "posY") == "37.402159")

    let result = try #require(results.first)
    #expect(result.title == "삼환하이펙스A동")
    #expect(result.address == "경기도 성남시 분당구 삼평동")
    #expect(result.coordinate == .init(latitude: 37.402109, longitude: 127.11065))
    #expect(result.source == "imps-geocoding")
}

@Test func httpIMPSGeocodingRejectsFailedHeader() async throws {
    let body = Data(#"{"header":{"isSuccessful":false,"resultCode":400,"resultMessage":"Failed"},"address":{"result":false,"adm":[]}}"#.utf8)
    let transport = IMPSRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imps.example.test")!, transport: transport)
    let repository = HTTPIMPSGeocodingRepository(
        client: client,
        configuration: .init(appKey: "test-key")
    )

    await #expect(throws: IMPSRepositoryError.invalidResponse) {
        _ = try await repository.geocode("판교역로 240", near: nil)
    }
}

@Test func httpIMPSReverseGeocodingBuildsDocumentedAddressQueryAndDecodesLocationFields() async throws {
    let body = Data(
        #"""
        {
          "header": {
            "isSuccessful": true,
            "resultCode": 0,
            "resultMessage": "Success"
          },
          "location": {
            "result": true,
            "hasAdmAddress": true,
            "adm": {
              "posx": "127.11065",
              "posy": "37.402109",
              "address": "경기도 성남시 분당구 삼평동",
              "jibun": "678",
              "roadname": "경기도 성남시 분당구 판교역로",
              "roadjibun": "240",
              "admcode": "4113510900",
              "postcode": "13493",
              "bldname": "삼환하이펙스A동",
              "bldnum": "102동"
            },
            "adm_address": {
              "address": "경기도 성남시 분당구 삼평동",
              "jibun": "678",
              "cut_address": "경기 성남시 분당구 삼평동",
              "admcode": "4113565500",
              "address_category1": "경기도",
              "address_category2": "성남시 분당구",
              "address_category3": "삼평동",
              "address_category4": ""
            },
            "legal_address": {
              "address": "경기도 성남시 분당구 삼평동",
              "jibun": "678",
              "cut_address": "경기 성남시 분당구 삼평동",
              "admcode": "4113510900",
              "address_category1": "경기도",
              "address_category2": "성남시 분당구",
              "address_category3": "삼평동",
              "address_category4": ""
            }
          }
        }
        """#.utf8
    )
    let transport = IMPSRecordingTransport(body: body)
    let client = HTTPClient(baseURL: URL(string: "https://imps.example.test")!, transport: transport)
    let repository = HTTPIMPSGeocodingRepository(
        client: client,
        configuration: .init(appKey: "{test-key }")
    )

    let result = try #require(await repository.reverseGeocode(.init(latitude: 37.402159, longitude: 127.11075)))

    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/maps/v3.0/appkeys/test-key/addresses")
    let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(queryItems.value(named: "posX") == "127.11075")
    #expect(queryItems.value(named: "posY") == "37.402159")
    #expect(queryItems.value(named: "coordtype") == "1")
    #expect(queryItems.value(named: "query") == nil)
    #expect(queryItems.value(named: "reqcount") == nil)

    #expect(result.title == "삼환하이펙스A동")
    #expect(result.address == "경기도 성남시 분당구 삼평동")
    #expect(result.coordinate == .init(latitude: 37.402109, longitude: 127.11065))
    #expect(result.source == "imps-reverse-geocoding")
}

private actor IMPSRecordingTransport: HTTPTransport {
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
