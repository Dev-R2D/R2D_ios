import Foundation
import R2DCore

public struct ExponentialRetryPolicy: RetryPolicy {
    public let baseDelay: TimeInterval, maximumDelay: TimeInterval, maximumRetryCount: Int
    public init(baseDelay: TimeInterval = 2, maximumDelay: TimeInterval = 300, maximumRetryCount: Int = 8) { self.baseDelay = baseDelay; self.maximumDelay = maximumDelay; self.maximumRetryCount = maximumRetryCount }
    public func nextRetryDate(retryCount: Int, error: TelemetryUploadError, now: Date) -> Date? {
        guard retryCount < maximumRetryCount else { return nil }
        switch error { case .offline, .timeout, .serverFailure: break; case .rateLimited(let retry): return now.addingTimeInterval(retry ?? baseDelay); default: return nil }
        let delay = min(maximumDelay, baseDelay * pow(2, Double(retryCount))) + Double(retryCount % 5) / 10
        return now.addingTimeInterval(delay)
    }
}

public actor TelemetryUploadWorker: TelemetryPipeline {
    private let queue: SecureTelemetryQueue, uploader: TelemetryUploader, retryPolicy: RetryPolicy, clock: Clock, batchSize: Int
    private var loopTask: Task<Void, Never>?
    private var acknowledgementHandler: (@Sendable (TelemetryUploadAcknowledgement) async -> Void)?
    public init(queue: SecureTelemetryQueue, uploader: TelemetryUploader, retryPolicy: RetryPolicy = ExponentialRetryPolicy(), clock: Clock = SystemClock(), batchSize: Int = 10) { self.queue = queue; self.uploader = uploader; self.retryPolicy = retryPolicy; self.clock = clock; self.batchSize = batchSize }
    public func start() async { guard loopTask == nil else { return }; try? await queue.restoreInterruptedUploads(); _ = try? await queue.repairIntegrity(); loopTask = Task { [weak self] in while !Task.isCancelled { await self?.triggerUpload(); try? await Task.sleep(for: .seconds(15)) } } }
    public func stop() async { loopTask?.cancel(); loopTask = nil; try? await queue.restoreInterruptedUploads() }
    public func enqueue(_ chunk: SensorChunk) async { try? await queue.enqueue(chunk: chunk, idempotencyKey: "\(chunk.sessionId):\(chunk.chunkSeq)"); await triggerUpload() }
    public func triggerUpload() async { await process(sessionID: nil) }
    public func flush(sessionID: String?) async { await process(sessionID: sessionID) }
    public func summary() async -> TelemetryQueueSummary { (try? await queue.summary()) ?? .empty }
    public func setUploadAcknowledgementHandler(_ handler: (@Sendable (TelemetryUploadAcknowledgement) async -> Void)?) async { acknowledgementHandler = handler }
    private func process(sessionID: String?) async {
        guard !Task.isCancelled, let batch = try? await queue.nextUploadBatch(limit: batchSize, now: clock.now(), sessionID: sessionID), !batch.isEmpty else { return }
        for item in batch { guard !Task.isCancelled else { break }; do { try await queue.markUploading(itemIDs: [item.id], attemptedAt: clock.now()); let payload = try await queue.loadPayload(itemID: item.id); let ack = try await uploader.upload(item: item, payload: payload); if ack.accepted || ack.duplicate { try await queue.acknowledge(itemID: item.id, acknowledgedAt: ack.acknowledgedAt); await acknowledgementHandler?(ack) } else { try await queue.markFailed(itemID: item.id, errorCode: "rejected") } } catch let error as TelemetryUploadError { if let next = retryPolicy.nextRetryDate(retryCount: item.retryCount, error: error, now: clock.now()) { try? await queue.markRetry(itemID: item.id, errorCode: String(describing: error), nextRetryAt: next) } else { try? await queue.markFailed(itemID: item.id, errorCode: String(describing: error)) } } catch { try? await queue.quarantine(itemID: item.id, reason: "payload_integrity") } }
    }
}
