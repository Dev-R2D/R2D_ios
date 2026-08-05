import Foundation

public struct AuthTokenSet: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresAt: Date?

    public init(accessToken: String, refreshToken: String, accessTokenExpiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}

public enum AuthenticationState: Equatable, Sendable {
    case signedOut
    case authenticated
}

public enum AuthenticationError: Error, Equatable, Sendable {
    case noRefreshToken
    case refreshFailed
    case secureStorageFailure
    case invalidResponse
}

public protocol TokenProvider: Sendable {
    func accessToken() async throws -> String?
    func refreshAccessToken() async throws -> String
    func logout() async
    func authenticationState() async -> AuthenticationState
}

public protocol SecureTokenStore: Sendable {
    func saveRefreshToken(_ refreshToken: String) async throws
    func loadRefreshToken() async throws -> String?
    func deleteRefreshToken() async throws
}

public protocol AuthRemoteAPI: Sendable {
    func refresh(refreshToken: String) async throws -> AuthTokenSet
}

public actor AuthManager: TokenProvider {
    private struct CachedAccessToken: Sendable {
        let value: String
        let expiresAt: Date?
    }

    private let tokenStore: SecureTokenStore
    private let remoteAPI: AuthRemoteAPI
    private let clock: Clock
    private let expiryLeeway: TimeInterval
    private var cachedAccessToken: CachedAccessToken?
    private var refreshTask: Task<AuthTokenSet, Error>?
    private var state: AuthenticationState = .signedOut

    public init(tokenStore: SecureTokenStore, remoteAPI: AuthRemoteAPI, clock: Clock = SystemClock(), expiryLeeway: TimeInterval = 30) {
        self.tokenStore = tokenStore
        self.remoteAPI = remoteAPI
        self.clock = clock
        self.expiryLeeway = expiryLeeway
    }

    public func install(_ tokens: AuthTokenSet) async throws {
        do {
            try await tokenStore.saveRefreshToken(tokens.refreshToken)
            cachedAccessToken = .init(value: tokens.accessToken, expiresAt: tokens.accessTokenExpiresAt)
            state = .authenticated
        } catch {
            throw AuthenticationError.secureStorageFailure
        }
    }

    public func accessToken() async throws -> String? {
        if let cachedAccessToken, !isExpired(cachedAccessToken) { return cachedAccessToken.value }
        let storedRefreshToken: String?
        do { storedRefreshToken = try await tokenStore.loadRefreshToken() }
        catch { throw AuthenticationError.secureStorageFailure }
        guard storedRefreshToken != nil else {
            cachedAccessToken = nil
            state = .signedOut
            return nil
        }
        return try await refreshAccessToken()
    }

    public func refreshAccessToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }

        let store = tokenStore
        let remote = remoteAPI
        let task = Task<AuthTokenSet, Error> {
            guard let refreshToken = try await store.loadRefreshToken() else { throw AuthenticationError.noRefreshToken }
            return try await remote.refresh(refreshToken: refreshToken)
        }
        refreshTask = task

        do {
            let tokens = try await task.value
            try await tokenStore.saveRefreshToken(tokens.refreshToken)
            cachedAccessToken = .init(value: tokens.accessToken, expiresAt: tokens.accessTokenExpiresAt)
            state = .authenticated
            refreshTask = nil
            return tokens.accessToken
        } catch {
            refreshTask = nil
            cachedAccessToken = nil
            state = .signedOut
            try? await tokenStore.deleteRefreshToken()
            if let authenticationError = error as? AuthenticationError { throw authenticationError }
            throw AuthenticationError.refreshFailed
        }
    }

    public func logout() async {
        refreshTask?.cancel()
        refreshTask = nil
        cachedAccessToken = nil
        state = .signedOut
        try? await tokenStore.deleteRefreshToken()
    }

    public func authenticationState() -> AuthenticationState { state }

    private func isExpired(_ token: CachedAccessToken) -> Bool {
        guard let expiresAt = token.expiresAt else { return false }
        return expiresAt.timeIntervalSince(clock.now()) <= expiryLeeway
    }
}

public actor InMemorySecureTokenStore: SecureTokenStore {
    private var refreshToken: String?
    public init(refreshToken: String? = nil) { self.refreshToken = refreshToken }
    public func saveRefreshToken(_ refreshToken: String) { self.refreshToken = refreshToken }
    public func loadRefreshToken() -> String? { refreshToken }
    public func deleteRefreshToken() { refreshToken = nil }
}

public actor MockAuthProvider: TokenProvider {
    private var token: String?
    private var state: AuthenticationState
    public init(accessToken: String? = "preview-access-token") {
        token = accessToken
        state = accessToken == nil ? .signedOut : .authenticated
    }
    public func accessToken() -> String? { token }
    public func refreshAccessToken() throws -> String {
        guard let token else { throw AuthenticationError.noRefreshToken }
        return token
    }
    public func logout() { token = nil; state = .signedOut }
    public func authenticationState() -> AuthenticationState { state }
}
