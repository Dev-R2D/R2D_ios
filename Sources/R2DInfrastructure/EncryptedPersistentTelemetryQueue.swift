import CryptoKit
import Foundation
import R2DCore

public struct TelemetryQueueConfiguration: Sendable {
    public let uploadBatchSize: Int, maximumRetryCount: Int
    public let baseRetryDelaySec: TimeInterval, maximumRetryDelaySec: TimeInterval
    public let maximumQueueBytes: Int64, maximumItemAgeSec: TimeInterval
    public init(uploadBatchSize: Int = 10, maximumRetryCount: Int = 8, baseRetryDelaySec: TimeInterval = 2, maximumRetryDelaySec: TimeInterval = 300, maximumQueueBytes: Int64 = 100 * 1024 * 1024, maximumItemAgeSec: TimeInterval = 30 * 24 * 3600) { self.uploadBatchSize = uploadBatchSize; self.maximumRetryCount = maximumRetryCount; self.baseRetryDelaySec = baseRetryDelaySec; self.maximumRetryDelaySec = maximumRetryDelaySec; self.maximumQueueBytes = maximumQueueBytes; self.maximumItemAgeSec = maximumItemAgeSec }
}

public actor EncryptedPersistentTelemetryQueue: SecureTelemetryQueue {
    private let root: URL, chunks: URL, quarantineDirectory: URL, indexURL: URL
    private let cipher: TelemetryCipher, configuration: TelemetryQueueConfiguration
    private var items: [TelemetryQueueItem]
    public init(root: URL, cipher: TelemetryCipher, configuration: TelemetryQueueConfiguration = .init()) throws {
        self.root = root; chunks = root.appendingPathComponent("chunks", isDirectory: true); quarantineDirectory = root.appendingPathComponent("quarantine", isDirectory: true); indexURL = root.appendingPathComponent("queue-index.json"); self.cipher = cipher; self.configuration = configuration
        try FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
        items = FileManager.default.fileExists(atPath: indexURL.path) ? try JSONDecoder().decode([TelemetryQueueItem].self, from: Data(contentsOf: indexURL)) : []
    }
    public func enqueue(chunk: SensorChunk, idempotencyKey: String) async throws {
        guard !items.contains(where: { ($0.sessionID == chunk.sessionId && $0.chunkSequence == chunk.chunkSeq) || $0.clientEventID == chunk.clientEventId || $0.idempotencyKey == idempotencyKey }) else { return }
        let plain = try JSONEncoder().encode(chunk), checksum = sha256(plain), encrypted = try cipher.encrypt(plain)
        let used = items.reduce(Int64(0)) { $0 + Int64($1.payloadByteCount) }; guard used + Int64(encrypted.count) <= configuration.maximumQueueBytes else { throw TelemetryQueueError.storageFull }
        let id = UUID(), fileName = "\(id.uuidString).bin", fileURL = chunks.appendingPathComponent(fileName)
        do { try encrypted.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen]) } catch { throw TelemetryQueueError.encryptionFailure }
        let item = TelemetryQueueItem(id: id, sessionID: chunk.sessionId, chunkSequence: chunk.chunkSeq, clientEventID: chunk.clientEventId, idempotencyKey: idempotencyKey, createdAt: Date(), startedAt: chunk.startedAt, endedAt: chunk.endedAt, checksum: checksum, payloadFileName: fileName, payloadByteCount: encrypted.count, sampleCount: chunk.sampleCount, isSimulated: chunk.isSimulated)
        items.append(item); do { try persistIndex() } catch { items.removeAll { $0.id == id }; try? FileManager.default.removeItem(at: fileURL); throw error }
    }
    public func nextUploadBatch(limit: Int, now: Date, sessionID: String? = nil) async throws -> [TelemetryQueueItem] { items.filter { $0.state == .pending && ($0.nextRetryAt == nil || $0.nextRetryAt! <= now) && (sessionID == nil || $0.sessionID == sessionID) }.sorted { $0.chunkSequence < $1.chunkSequence }.prefix(limit).map { $0 } }
    public func loadPayload(itemID: UUID) async throws -> Data {
        guard let item = items.first(where: { $0.id == itemID }) else { throw TelemetryQueueError.payloadMissing }
        do { let plain = try cipher.decrypt(Data(contentsOf: chunks.appendingPathComponent(item.payloadFileName))); guard sha256(plain) == item.checksum else { throw TelemetryQueueError.integrityFailure }; return plain } catch let error as TelemetryQueueError { throw error } catch { throw TelemetryQueueError.integrityFailure }
    }
    public func markUploading(itemIDs: [UUID], attemptedAt: Date) async throws { mutate(itemIDs) { $0.state = .uploading; $0.lastAttemptAt = attemptedAt }; try persistIndex() }
    public func acknowledge(itemID: UUID, acknowledgedAt: Date) async throws { guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }; let item = items[index]; items[index].state = .acknowledged; items[index].acknowledgedAt = acknowledgedAt; try persistIndex(); try FileManager.default.removeItem(at: chunks.appendingPathComponent(item.payloadFileName)); items.remove(at: index); try persistIndex() }
    public func markRetry(itemID: UUID, errorCode: String, nextRetryAt: Date) async throws { mutate([itemID]) { $0.state = .pending; $0.retryCount += 1; $0.nextRetryAt = nextRetryAt; $0.lastErrorCode = errorCode }; try persistIndex() }
    public func markFailed(itemID: UUID, errorCode: String) async throws { mutate([itemID]) { $0.state = .failed; $0.lastErrorCode = errorCode }; try persistIndex() }
    public func quarantine(itemID: UUID, reason: String) async throws { guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }; let source = chunks.appendingPathComponent(items[index].payloadFileName), target = quarantineDirectory.appendingPathComponent(items[index].payloadFileName); if FileManager.default.fileExists(atPath: source.path) { try? FileManager.default.moveItem(at: source, to: target) }; items[index].state = .quarantined; items[index].lastErrorCode = reason; try persistIndex() }
    public func restoreInterruptedUploads() async throws { var count = 0; for index in items.indices where items[index].state == .uploading { items[index].state = .pending; count += 1 }; if count > 0 { try persistIndex() } }
    public func repairIntegrity() async throws -> TelemetryIntegrityReport {
        var report = TelemetryIntegrityReport(); try await restoreInterruptedUploads()
        var files = Set((try? FileManager.default.contentsOfDirectory(atPath: chunks.path)) ?? [])
        for item in items.filter({ $0.state == .acknowledged }) { if files.contains(item.payloadFileName) { try? FileManager.default.removeItem(at: chunks.appendingPathComponent(item.payloadFileName)); files.remove(item.payloadFileName) }; items.removeAll { $0.id == item.id } }
        try persistIndex()
        let known = Set(items.map(\.payloadFileName))
        for orphan in files.subtracting(known) { report.orphanPayloadCount += 1; try? FileManager.default.moveItem(at: chunks.appendingPathComponent(orphan), to: quarantineDirectory.appendingPathComponent(orphan)) }
        for item in items { do { _ = try await loadPayload(itemID: item.id); report.validItemCount += 1 } catch { if !files.contains(item.payloadFileName) { report.missingPayloadCount += 1 } else if let queueError = error as? TelemetryQueueError, queueError == .integrityFailure { report.checksumFailureCount += 1 } else { report.decryptionFailureCount += 1 }; try await quarantine(itemID: item.id, reason: "integrity"); report.quarantinedCount += 1 } }
        return report
    }
    public func summary() async throws -> TelemetryQueueSummary { .init(pendingCount: count(.pending), uploadingCount: count(.uploading), acknowledgedCount: count(.acknowledged), failedCount: count(.failed), quarantinedCount: count(.quarantined), totalBytes: items.reduce(0) { $0 + Int64($1.payloadByteCount) }, oldestPendingAt: items.filter { $0.state == .pending }.map(\.createdAt).min(), isStorageFull: items.reduce(Int64(0)) { $0 + Int64($1.payloadByteCount) } >= configuration.maximumQueueBytes, nextRetryAt: items.compactMap(\.nextRetryAt).min()) }
    private func count(_ state: TelemetryQueueItemState) -> Int { items.count { $0.state == state } }
    private func mutate(_ ids: [UUID], _ body: (inout TelemetryQueueItem) -> Void) { for index in items.indices where ids.contains(items[index].id) { body(&items[index]) } }
    private func persistIndex() throws { try JSONEncoder().encode(items).write(to: indexURL, options: [.atomic, .completeFileProtectionUnlessOpen]) }
    private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
