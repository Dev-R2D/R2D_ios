import CryptoKit
import Foundation
import R2DCore
#if canImport(Security)
import Security
#endif

public struct AESGCMTelemetryCipher: TelemetryCipher {
    private let key: SymmetricKey
    public init(keyData: Data) { key = SymmetricKey(data: keyData) }
    public func encrypt(_ data: Data) throws -> Data { try AES.GCM.seal(data, using: key).combined! }
    public func decrypt(_ data: Data) throws -> Data { try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key) }
}

public final class InMemorySecretKeyStore: SecretKeyStore, @unchecked Sendable {
    private let lock = NSLock(); private var key: Data?
    public init(key: Data? = nil) { self.key = key }
    public func loadOrCreateKey() throws -> Data { lock.withLock { if let key { return key }; let value = Data((0..<32).map { UInt8(($0 * 7 + 11) % 255) }); key = value; return value } }
}

#if canImport(Security)
public struct KeychainSecretKeyStore: SecretKeyStore {
    private let service: String, account: String
    public init(service: String = "app.r2d.telemetry", account: String = "aes-gcm-v1") { self.service = service; self.account = account }
    public func loadOrCreateKey() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        guard status == errSecItemNotFound else { throw TelemetryQueueError.encryptionFailure }
        var bytes = [UInt8](repeating: 0, count: 32); guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw TelemetryQueueError.encryptionFailure }
        let data = Data(bytes), add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw TelemetryQueueError.encryptionFailure }; return data
    }
}
#endif
