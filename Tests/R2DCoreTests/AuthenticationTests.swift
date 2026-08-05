import Foundation
import Testing
@testable import R2DCore

@Test func tokenIsStoredAndRestoredThroughRefreshWithoutPersistingAccessToken() async throws {
    let store = InMemorySecureTokenStore()
    let firstRemote = AuthRemoteStub(result: .success(.init(accessToken: "access-1", refreshToken: "refresh-1")))
    let first = AuthManager(tokenStore: store, remoteAPI: firstRemote)
    try await first.install(.init(accessToken: "memory-only", refreshToken: "refresh-1"))
    #expect(await store.loadRefreshToken() == "refresh-1")

    let restoredRemote = AuthRemoteStub(result: .success(.init(accessToken: "restored-access", refreshToken: "refresh-2")))
    let restored = AuthManager(tokenStore: store, remoteAPI: restoredRemote)
    #expect(try await restored.accessToken() == "restored-access")
    #expect(await store.loadRefreshToken() == "refresh-2")
}

@Test func concurrentRefreshIsCoalesced() async throws {
    let store = InMemorySecureTokenStore(refreshToken: "refresh")
    let remote = AuthRemoteStub(result: .success(.init(accessToken: "new-access", refreshToken: "rotated")), delay: .milliseconds(40))
    let manager = AuthManager(tokenStore: store, remoteAPI: remote)
    let values = try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<12 { group.addTask { try await manager.refreshAccessToken() } }
        return try await group.reduce(into: []) { $0.append($1) }
    }
    #expect(values.allSatisfy { $0 == "new-access" })
    #expect(await remote.callCount == 1)
}

@Test func refreshFailureSignsOutAndDeletesRefreshToken() async throws {
    let store = InMemorySecureTokenStore(refreshToken: "invalid")
    let manager = AuthManager(tokenStore: store, remoteAPI: AuthRemoteStub(result: .failure(AuthenticationError.refreshFailed)))
    await #expect(throws: AuthenticationError.refreshFailed) { try await manager.refreshAccessToken() }
    #expect(await manager.authenticationState() == .signedOut)
    #expect(await store.loadRefreshToken() == nil)
}

@Test func logoutClearsMemoryAndSecureStorage() async throws {
    let store = InMemorySecureTokenStore()
    let manager = AuthManager(tokenStore: store, remoteAPI: AuthRemoteStub(result: .failure(AuthenticationError.refreshFailed)))
    try await manager.install(.init(accessToken: "access", refreshToken: "refresh"))
    await manager.logout()
    #expect(await manager.authenticationState() == .signedOut)
    #expect(try await manager.accessToken() == nil)
    #expect(await store.loadRefreshToken() == nil)
}

private actor AuthRemoteStub: AuthRemoteAPI {
    private let result: Result<AuthTokenSet, Error>
    private let delay: Duration?
    private(set) var callCount = 0
    init(result: Result<AuthTokenSet, Error>, delay: Duration? = nil) { self.result = result; self.delay = delay }
    func refresh(refreshToken: String) async throws -> AuthTokenSet {
        callCount += 1
        if let delay { try await Task.sleep(for: delay) }
        return try result.get()
    }
}
