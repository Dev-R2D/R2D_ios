import Foundation
import R2DCore

public struct TelemetryHTTPUploader: TelemetryUploader {
    private let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }
    public func upload(item: TelemetryQueueItem, payload: Data) async throws -> TelemetryUploadAcknowledgement {
        let body = UploadBody(sessionID: item.sessionID, chunkSequence: item.chunkSequence, startedAt: item.startedAt, endedAt: item.endedAt, checksum: item.checksum, sampleCount: item.sampleCount, isSimulated: item.isSimulated, payloadEncoding: "base64-json", payload: payload.base64EncodedString())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let response = try await client.send(.init(path: "/v1/rides/\(item.sessionID)/telemetry", method: .post, headers: ["Content-Type": "application/json", "Idempotency-Key": item.idempotencyKey, "X-Client-Event-ID": item.clientEventID, "X-Request-ID": UUID().uuidString], body: try encoder.encode(body)))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(UploadResponse.self, from: response.body) else { throw TelemetryUploadError.invalidResponse }
        return .init(queueItemID: item.id, accepted: value.accepted, duplicate: value.duplicate, serverObservationID: value.serverObservationID, acknowledgedAt: value.acknowledgedAt, processingStatus: value.processingStatus)
    }
}
private struct UploadBody: Codable { let sessionID: String, chunkSequence: Int, startedAt: Date, endedAt: Date, checksum: String, sampleCount: Int, isSimulated: Bool, payloadEncoding: String, payload: String; enum CodingKeys: String, CodingKey { case sessionID = "session_id", chunkSequence = "chunk_seq", startedAt = "started_at", endedAt = "ended_at", checksum, sampleCount = "sample_count", isSimulated = "is_simulated", payloadEncoding = "payload_encoding", payload } }
private struct UploadResponse: Codable { let accepted: Bool, duplicate: Bool, serverObservationID: String?, acknowledgedAt: Date, processingStatus: String?; enum CodingKeys: String, CodingKey { case accepted, duplicate, serverObservationID = "server_observation_id", acknowledgedAt = "acknowledged_at", processingStatus = "processing_status" } }

public struct QueueOnlyTelemetryUploader: TelemetryUploader { public init() {}; public func upload(item: TelemetryQueueItem, payload: Data) async throws -> TelemetryUploadAcknowledgement { throw TelemetryUploadError.offline } }
public actor MockTelemetryUploader: TelemetryUploader {
    public private(set) var uploads: [TelemetryQueueItem] = []
    public init() {}
    public func upload(item: TelemetryQueueItem, payload: Data) async throws -> TelemetryUploadAcknowledgement { uploads.append(item); return .init(queueItemID: item.id, accepted: true, duplicate: false, serverObservationID: "mock-\(item.chunkSequence)", acknowledgedAt: Date(), processingStatus: "ACCEPTED") }
}
