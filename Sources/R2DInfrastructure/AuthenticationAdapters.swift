import Foundation
import R2DCore
#if canImport(Security)
import Security
#endif

public struct AuthHTTPRemoteAPI: AuthRemoteAPI {
    private let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }

    public func refresh(refreshToken: String) async throws -> AuthTokenSet {
        let body = try JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))
        let response = try await client.send(.init(path: "/v1/auth/refresh", method: .post, headers: ["Content-Type": "application/json"], body: body))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let value = try? decoder.decode(RefreshResponse.self, from: response.body) else { throw AuthenticationError.invalidResponse }
        return .init(accessToken: value.accessToken, refreshToken: value.refreshToken, accessTokenExpiresAt: value.expiresAt)
    }
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}
private struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
}

#if canImport(Security)
public actor KeychainSecureTokenStore: SecureTokenStore {
    private let service: String
    private let account: String

    public init(service: String = "app.r2d.authentication", account: String = "refresh-token-v1") {
        self.service = service
        self.account = account
    }

    public func saveRefreshToken(_ refreshToken: String) throws {
        guard let data = refreshToken.data(using: .utf8) else { throw AuthenticationError.secureStorageFailure }
        let query = baseQuery
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AuthenticationError.secureStorageFailure }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw AuthenticationError.secureStorageFailure }
    }

    public func loadRefreshToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw AuthenticationError.secureStorageFailure }
        return token
    }

    public func deleteRefreshToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthenticationError.secureStorageFailure }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
#else
public actor KeychainSecureTokenStore: SecureTokenStore {
    public init(service: String = "app.r2d.authentication", account: String = "refresh-token-v1") {}
    public func saveRefreshToken(_ refreshToken: String) throws { throw AuthenticationError.secureStorageFailure }
    public func loadRefreshToken() throws -> String? { throw AuthenticationError.secureStorageFailure }
    public func deleteRefreshToken() throws { throw AuthenticationError.secureStorageFailure }
}
#endif
