import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func httpClientAddsAuthorizationHeader() async throws {
    let provider = MockAuthProvider(accessToken: "access-token")
    let transport = AuthRecordingTransport()
    let client = HTTPClient(baseURL: URL(string: "https://api.example.test")!, transport: transport, tokenProvider: provider)
    _ = try await client.send(.init(path: "/v1/test", method: .get, headers: ["Authorization": "repository-must-not-win"]))
    #expect(await transport.authorizationHeaders == ["Bearer access-token"])
}

@Test func unauthorizedRefreshesAndRetriesExactlyOnce() async throws {
    let store = InMemorySecureTokenStore()
    let remote = InfrastructureAuthRemote(result: .init(accessToken: "new", refreshToken: "rotated"))
    let manager = AuthManager(tokenStore: store, remoteAPI: remote)
    try await manager.install(.init(accessToken: "old", refreshToken: "refresh"))
    let transport = AuthRecordingTransport(rejectToken: "Bearer old")
    let client = HTTPClient(baseURL: URL(string: "https://api.example.test")!, transport: transport, tokenProvider: manager)
    _ = try await client.send(.init(path: "/v1/protected", method: .get))
    #expect(await transport.authorizationHeaders == ["Bearer old", "Bearer new"])
    #expect(await remote.callCount == 1)
}

@Test func simultaneousUnauthorizedRequestsShareRefresh() async throws {
    let store = InMemorySecureTokenStore()
    let remote = InfrastructureAuthRemote(result: .init(accessToken: "new", refreshToken: "rotated"), delay: .milliseconds(50))
    let manager = AuthManager(tokenStore: store, remoteAPI: remote)
    try await manager.install(.init(accessToken: "old", refreshToken: "refresh"))
    let transport = AuthRecordingTransport(rejectToken: "Bearer old")
    let client = HTTPClient(baseURL: URL(string: "https://api.example.test")!, transport: transport, tokenProvider: manager)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<10 { group.addTask { _ = try await client.send(.init(path: "/v1/protected", method: .get)) } }
        try await group.waitForAll()
    }
    #expect(await remote.callCount == 1)
}

@Test func authRefreshAdapterUsesUnauthenticatedRefreshEndpoint() async throws {
    let body = Data(#"{"access_token":"access","refresh_token":"rotated","expires_at":"2030-01-01T00:00:00Z"}"#.utf8)
    let transport = AuthRecordingTransport(body: body)
    let api = AuthHTTPRemoteAPI(client: HTTPClient(baseURL: URL(string: "https://api.example.test")!, transport: transport))
    let tokens = try await api.refresh(refreshToken: "refresh")
    #expect(tokens.accessToken == "access")
    #expect(await transport.paths == ["/v1/auth/refresh"])
    #expect(await transport.authorizationHeaders == [nil])
}

#if canImport(Security)
@Test func keychainRefreshTokenRestoresAcrossStoreInstances() async throws {
    let service = "app.r2d.tests.\(UUID().uuidString)"
    let first = KeychainSecureTokenStore(service: service)
    try await first.saveRefreshToken("keychain-refresh")
    let restored = KeychainSecureTokenStore(service: service)
    #expect(try await restored.loadRefreshToken() == "keychain-refresh")
    try await restored.deleteRefreshToken()
    #expect(try await first.loadRefreshToken() == nil)
}
#endif

private actor InfrastructureAuthRemote: AuthRemoteAPI {
    let result: AuthTokenSet
    let delay: Duration?
    private(set) var callCount = 0
    init(result: AuthTokenSet, delay: Duration? = nil) { self.result = result; self.delay = delay }
    func refresh(refreshToken: String) async throws -> AuthTokenSet {
        callCount += 1
        if let delay { try await Task.sleep(for: delay) }
        return result
    }
}

private actor AuthRecordingTransport: HTTPTransport {
    let rejectToken: String?
    let body: Data
    private(set) var authorizationHeaders: [String?] = []
    private(set) var paths: [String] = []
    init(rejectToken: String? = nil, body: Data = Data()) { self.rejectToken = rejectToken; self.body = body }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        authorizationHeaders.append(authorization)
        paths.append(request.url?.path ?? "")
        return .init(statusCode: rejectToken.map { authorization == $0 } == true ? 401 : 200, headers: [:], body: body)
    }
}
