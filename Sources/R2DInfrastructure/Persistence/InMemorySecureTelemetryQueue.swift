import Foundation
import R2DCore

public actor InMemorySecureTelemetryQueue: SecureTelemetryQueue {
    private var items: [TelemetryQueueItem] = [], payloads: [UUID: Data] = [:]
    public init() {}
    public func enqueue(chunk: SensorChunk, idempotencyKey: String) async throws { guard !items.contains(where: { ($0.sessionID == chunk.sessionId && $0.chunkSequence == chunk.chunkSeq) || $0.clientEventID == chunk.clientEventId || $0.idempotencyKey == idempotencyKey }) else { return }; let id = UUID(), data = try JSONEncoder().encode(chunk); items.append(.init(id: id, sessionID: chunk.sessionId, chunkSequence: chunk.chunkSeq, clientEventID: chunk.clientEventId, idempotencyKey: idempotencyKey, createdAt: Date(), startedAt: chunk.startedAt, endedAt: chunk.endedAt, checksum: chunk.checksum, payloadFileName: "memory", payloadByteCount: data.count, sampleCount: chunk.sampleCount, isSimulated: chunk.isSimulated)); payloads[id] = data }
    public func nextUploadBatch(limit: Int, now: Date, sessionID: String?) async throws -> [TelemetryQueueItem] { items.filter { $0.state == .pending && ($0.nextRetryAt == nil || $0.nextRetryAt! <= now) && (sessionID == nil || $0.sessionID == sessionID) }.prefix(limit).map { $0 } }
    public func loadPayload(itemID: UUID) async throws -> Data { guard let data = payloads[itemID] else { throw TelemetryQueueError.payloadMissing }; return data }
    public func markUploading(itemIDs: [UUID], attemptedAt: Date) async throws { mutate(itemIDs) { $0.state = .uploading; $0.lastAttemptAt = attemptedAt } }
    public func acknowledge(itemID: UUID, acknowledgedAt: Date) async throws { items.removeAll { $0.id == itemID }; payloads[itemID] = nil }
    public func markRetry(itemID: UUID, errorCode: String, nextRetryAt: Date) async throws { mutate([itemID]) { $0.state = .pending; $0.retryCount += 1; $0.nextRetryAt = nextRetryAt; $0.lastErrorCode = errorCode } }
    public func markFailed(itemID: UUID, errorCode: String) async throws { mutate([itemID]) { $0.state = .failed; $0.lastErrorCode = errorCode } }
    public func quarantine(itemID: UUID, reason: String) async throws { mutate([itemID]) { $0.state = .quarantined; $0.lastErrorCode = reason } }
    public func restoreInterruptedUploads() async throws { mutate(items.filter { $0.state == .uploading }.map(\.id)) { $0.state = .pending } }
    public func repairIntegrity() async throws -> TelemetryIntegrityReport { var value = TelemetryIntegrityReport(); value.validItemCount = items.count { payloads[$0.id] != nil }; return value }
    public func summary() async throws -> TelemetryQueueSummary { .init(pendingCount: items.count { $0.state == .pending }, uploadingCount: items.count { $0.state == .uploading }, acknowledgedCount: 0, failedCount: items.count { $0.state == .failed }, quarantinedCount: items.count { $0.state == .quarantined }, totalBytes: items.reduce(0) { $0 + Int64($1.payloadByteCount) }, oldestPendingAt: items.filter { $0.state == .pending }.map(\.createdAt).min(), isStorageFull: false, nextRetryAt: items.compactMap(\.nextRetryAt).min()) }
    private func mutate(_ ids: [UUID], _ body: (inout TelemetryQueueItem) -> Void) { for index in items.indices where ids.contains(items[index].id) { body(&items[index]) } }
}
