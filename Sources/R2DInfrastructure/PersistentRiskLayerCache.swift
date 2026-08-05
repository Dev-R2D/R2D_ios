import Foundation
import R2DCore

public actor PersistentRiskLayerCache: IRiskLayerCache {
    private let root: URL, encoder: JSONEncoder, decoder: JSONDecoder
    public init(root: URL) throws {
        self.root = root; encoder = JSONEncoder(); decoder = JSONDecoder(); encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    public func load(_ context: RiskLayerCacheContext) async throws -> RiskLayerSnapshot? {
        let url = fileURL(context); guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try decoder.decode(RiskLayerSnapshot.self, from: Data(contentsOf: url)) }
        catch { let quarantine = root.appendingPathComponent("\(url.lastPathComponent).corrupt-\(UUID().uuidString)"); try? FileManager.default.moveItem(at: url, to: quarantine); return nil }
    }
    public func save(_ snapshot: RiskLayerSnapshot, context: RiskLayerCacheContext) async throws {
        do { try encoder.encode(snapshot).write(to: fileURL(context), options: [.atomic])
            let metadata = CacheMetadata(layerVersion: snapshot.layerVersion, generatedAt: snapshot.generatedAt, expiresAt: snapshot.expiresAt); try encoder.encode(metadata).write(to: root.appendingPathComponent("metadata.json"), options: [.atomic])
        } catch { throw RiskLayerError.cacheUnavailable }
    }
    private func fileURL(_ context: RiskLayerCacheContext) -> URL { root.appendingPathComponent(context == .route ? "latest-route.json" : "latest-viewport.json") }
}
private struct CacheMetadata: Codable { let layerVersion: String, generatedAt: Date, expiresAt: Date? }
