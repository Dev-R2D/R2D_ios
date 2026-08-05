import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("r2d-telemetry-\(UUID().uuidString)") }
private func cipher() -> AESGCMTelemetryCipher { AESGCMTelemetryCipher(keyData: Data(repeating: 7, count: 32)) }
private func chunk(sequence: Int = 1, event: String = "event-1", payload: Data = Data("secret-road-samples".utf8)) -> SensorChunk { .init(sessionId: "ride-1", chunkSeq: sequence, startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 15), checksum: "client-checksum", sampleCount: 500, clientEventId: event, isSimulated: false, payload: payload) }

@Test func aesGCMRoundTripAndPayloadIsNotPlaintextOnDisk() async throws {
    let root = temporaryRoot(), crypto = cipher(), plain = Data("sensitive-payload".utf8)
    #expect(try crypto.decrypt(crypto.encrypt(plain)) == plain)
    let queue = try EncryptedPersistentTelemetryQueue(root: root, cipher: crypto); try await queue.enqueue(chunk: chunk(payload: plain), idempotencyKey: "key-1")
    let file = try #require((try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("chunks"), includingPropertiesForKeys: nil)).first)
    #expect(try Data(contentsOf: file) != plain); #expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("sensitive-payload"))
}

@Test func persistentQueueRestoresAndPreventsAllDuplicateKeys() async throws {
    let root = temporaryRoot(); var queue: EncryptedPersistentTelemetryQueue? = try .init(root: root, cipher: cipher())
    try await queue?.enqueue(chunk: chunk(), idempotencyKey: "key-1"); queue = nil
    let restored = try EncryptedPersistentTelemetryQueue(root: root, cipher: cipher()); #expect(try await restored.summary().pendingCount == 1)
    try await restored.enqueue(chunk: chunk(), idempotencyKey: "different"); try await restored.enqueue(chunk: chunk(sequence: 2), idempotencyKey: "key-1"); try await restored.enqueue(chunk: chunk(sequence: 3, event: "event-1"), idempotencyKey: "key-3")
    #expect(try await restored.summary().pendingCount == 1)
}

@Test func ackControlsDeletionAndInterruptedUploadRestoresPending() async throws {
    let root = temporaryRoot(), queue = try EncryptedPersistentTelemetryQueue(root: root, cipher: cipher()); try await queue.enqueue(chunk: chunk(), idempotencyKey: "key")
    let item = try #require(try await queue.nextUploadBatch(limit: 1, now: Date(), sessionID: nil).first); let payloadURL = root.appendingPathComponent("chunks/\(item.payloadFileName)")
    try await queue.markUploading(itemIDs: [item.id], attemptedAt: Date()); #expect(FileManager.default.fileExists(atPath: payloadURL.path))
    let relaunched = try EncryptedPersistentTelemetryQueue(root: root, cipher: cipher()); try await relaunched.restoreInterruptedUploads(); #expect(try await relaunched.summary().pendingCount == 1)
    try await relaunched.acknowledge(itemID: item.id, acknowledgedAt: Date()); #expect(!FileManager.default.fileExists(atPath: payloadURL.path)); #expect(try await relaunched.summary().pendingCount == 0)
}

@Test func capacityRejectsWithoutDeletingPendingAndOrphanIsQuarantined() async throws {
    let root = temporaryRoot(), config = TelemetryQueueConfiguration(maximumQueueBytes: 80)
    let queue = try EncryptedPersistentTelemetryQueue(root: root, cipher: cipher(), configuration: config)
    await #expect(throws: TelemetryQueueError.storageFull) { try await queue.enqueue(chunk: chunk(payload: Data(repeating: 1, count: 500)), idempotencyKey: "large") }
    let orphan = root.appendingPathComponent("chunks/orphan.bin"); try Data([1, 2, 3]).write(to: orphan)
    let report = try await queue.repairIntegrity(); #expect(report.orphanPayloadCount == 1); #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("quarantine/orphan.bin").path))
}

private actor RecordingTransport: HTTPTransport {
    var request: URLRequest?, response: HTTPResponse
    init(response: HTTPResponse) { self.response = response }
    func send(_ request: URLRequest) async throws -> HTTPResponse { self.request = request; return response }
    func captured() -> URLRequest? { request }
}

@Test func telemetryUploaderSendsIdempotencyHeadersAndParsesDuplicate() async throws {
    let body = Data("{\"accepted\":true,\"duplicate\":true,\"server_observation_id\":\"obs\",\"acknowledged_at\":\"2026-08-05T00:00:00Z\",\"processing_status\":\"ACCEPTED\"}".utf8)
    let transport = RecordingTransport(response: .init(statusCode: 202, headers: [:], body: body)), uploader = TelemetryHTTPUploader(client: HTTPClient(baseURL: URL(string: "https://api.example.test")!, transport: transport))
    let item = TelemetryQueueItem(id: UUID(), sessionID: "ride", chunkSequence: 1, clientEventID: "event", idempotencyKey: "idem", createdAt: Date(), startedAt: Date(), endedAt: Date(), checksum: "sum", payloadFileName: "x", payloadByteCount: 2, sampleCount: 1, isSimulated: false)
    let ack = try await uploader.upload(item: item, payload: Data([1, 2])); #expect(ack.duplicate)
    let request = try #require(await transport.captured()); #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "idem"); #expect(request.value(forHTTPHeaderField: "X-Client-Event-ID") == "event")
}

@Test func progressHTTPRepositoryUsesOpenAPIPathsAndDecodesModels() async throws {
    actor ProgressTransport: HTTPTransport {
        var paths: [String] = []
        func send(_ request: URLRequest) async throws -> HTTPResponse {
            let path = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: true)?.percentEncodedPath } ?? ""; paths.append(path)
            let body: String
            if path.hasSuffix("/boss") { body = #"{"boss_hp":72,"confirmed_damage":28,"pending_damage":4,"processing_state":"PROCESSING"}"# }
            else if path.hasSuffix("/reward") { body = #"{"pending_reward":6,"confirmed_reward":11}"# }
            else { body = #"{"valid_distance":321.5,"confirmed_distance":300,"processing_chunks":1,"acknowledged_chunks":3,"remaining_chunks":2,"risk_layer_version":"risk-9"}"# }
            return .init(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        func captured() -> [String] { paths }
    }
    let transport = ProgressTransport(), repository = RideProgressHTTPRepository(client: HTTPClient(baseURL: URL(string: "https://api.example.test")!, transport: transport))
    #expect(try await repository.fetchRideProgress(rideId: "ride 1").validDistance == 321.5)
    #expect(try await repository.fetchBossProgress(rideId: "ride 1")?.bossHP == 72)
    #expect(try await repository.fetchRewardProgress(rideId: "ride 1").confirmedReward == 11)
    #expect(try await repository.fetchRiskLayerVersion(rideId: "ride 1") == "risk-9")
    #expect(await transport.captured() == ["/v1/rides/ride%201/progress", "/v1/rides/ride%201/boss", "/v1/rides/ride%201/reward", "/v1/rides/ride%201/progress"])
}

@Test func httpRouteRepositorySearchesAndRefreshesDomainRoutes() async throws {
    actor RouteTransport: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> HTTPResponse {
            requests.append(request)
            let route = #"{"id":"server-route","polyline":[{"latitude":37.55,"longitude":127.04},{"latitude":37.56,"longitude":127.05}],"total_distance":1400,"total_duration":300,"remaining_distance":1400,"remaining_duration":300,"turn_list":[{"coordinate":{"latitude":37.56,"longitude":127.05},"instruction":"도착","distance":1400}],"risk_cells":[],"status":"READY"}"#
            let body = request.url?.path.hasSuffix("/search") == true ? "{\"routes\":[\(route)]}" : route
            return .init(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        func captured() -> [URLRequest] { requests }
    }
    let transport = RouteTransport(), repository = HTTPRouteRepository(client: HTTPClient(baseURL: URL(string: "https://route.test")!, transport: transport))
    let origin = Coordinate(latitude: 37.55, longitude: 127.04), destination = Coordinate(latitude: 37.56, longitude: 127.05)
    let route = try #require(try await repository.searchRoute(origin: origin, destination: destination).first)
    #expect(route.totalDistance == 1400); #expect(try await repository.refreshRoute(route, from: origin).turnList.count == 1)
    let requests = await transport.captured(); #expect(requests.map { $0.url?.path } == ["/v1/routes/search", "/v1/routes/server-route/refresh"])
    #expect(String(decoding: requests[1].httpBody ?? Data(), as: UTF8.self).contains("current_location"))
}

@Test func httpClassifiesRetryAfterAndAuthorization() async throws {
    let rate = RecordingTransport(response: .init(statusCode: 429, headers: ["Retry-After": "12"], body: Data()))
    await #expect(throws: TelemetryUploadError.rateLimited(retryAfter: 12)) { try await HTTPClient(baseURL: URL(string: "https://a.test")!, transport: rate).send(.init(path: "/x", method: .post)) }
    let auth = RecordingTransport(response: .init(statusCode: 401, headers: [:], body: Data()))
    await #expect(throws: TelemetryUploadError.unauthorized) { try await HTTPClient(baseURL: URL(string: "https://a.test")!, transport: auth).send(.init(path: "/x", method: .post)) }
}

private struct FixedClock: Clock { let date: Date; func now() -> Date { date } }
private struct OfflineUploader: TelemetryUploader { func upload(item: TelemetryQueueItem, payload: Data) async throws -> TelemetryUploadAcknowledgement { throw TelemetryUploadError.offline } }

@Test func workerAcknowledgesSuccessAndSchedulesOfflineRetry() async throws {
    let successQueue = InMemorySecureTelemetryQueue(), successWorker = TelemetryUploadWorker(queue: successQueue, uploader: MockTelemetryUploader())
    await successWorker.enqueue(chunk()); #expect(try await successQueue.summary().pendingCount == 0)
    let retryQueue = InMemorySecureTelemetryQueue(), now = Date(timeIntervalSince1970: 100), retryWorker = TelemetryUploadWorker(queue: retryQueue, uploader: OfflineUploader(), retryPolicy: ExponentialRetryPolicy(baseDelay: 2), clock: FixedClock(date: now))
    await retryWorker.enqueue(chunk()); let summary = try await retryQueue.summary(); #expect(summary.pendingCount == 1); #expect(summary.nextRetryAt == now.addingTimeInterval(2))
}
