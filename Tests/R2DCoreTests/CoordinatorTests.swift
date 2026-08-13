import Foundation
import Testing
@testable import R2DCore

@MainActor private func fixture() -> (ActiveRideCoordinator, MockLocationTracker, MockSensorCollector, MemoryTelemetryQueue) {
    let locations = MockLocationTracker(), sensors = MockSensorCollector(), queue = MemoryTelemetryQueue()
    let coordinator = ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: locations, sensors: sensors, routes: MockRouteRepository(), queue: queue, progress: MockProgressServer())
    return (coordinator, locations, sensors, queue)
}

@Test @MainActor func twentyViewSwitchesKeepRideAndCollectorsAlive() async throws {
    let (coordinator, locations, sensors, _) = fixture()
    try await coordinator.loadRoutes(destination: "test")
    let route = try #require(coordinator.getSnapshot().routes.first)
    coordinator.selectRoute(route); let session = try coordinator.prepare(); try coordinator.start()
    for index in 0..<20 { coordinator.switchView(index.isMultiple(of: 2) ? .game : .navigator) }
    #expect(coordinator.getSnapshot().session?.id == session.id)
    #expect(coordinator.getSnapshot().session?.routeId == session.routeId)
    #expect(locations.isRunning && sensors.isRunning)
}

@Test @MainActor func locationAndSensorContinueAcrossViewChanges() async throws {
    let (coordinator, locations, sensors, queue) = fixture()
    try await coordinator.loadRoutes(destination: "test"); coordinator.selectRoute(coordinator.getSnapshot().routes[0]); _ = try coordinator.prepare(); _ = try coordinator.start(); coordinator.switchView(.game)
    locations.simulate(.init(coordinate: .init(latitude: 37.55, longitude: 127.04), speedMps: 6, heading: 90, mapMatchConfidence: 0.95))
    locations.simulate(.init(coordinate: .init(latitude: 37.551, longitude: 127.04), speedMps: 6, heading: 90, mapMatchConfidence: 0.95))
    let sessionId = try #require(coordinator.getSnapshot().session?.id)
    sensors.simulate(.init(sessionId: sessionId, chunkSeq: 1, startedAt: Date(), endedAt: Date(), checksum: "abc", sampleCount: 50, clientEventId: "event-1", isSimulated: true))
    try await Task.sleep(for: .milliseconds(30))
    #expect((coordinator.getSnapshot().session?.localDistanceM ?? 0) > 100)
    #expect(queue.pending(sessionId: sessionId).count == 1)
}

@Test @MainActor func progressSyncDoesNotPretendLegacyQueueWasServerAcknowledged() async throws {
    let (coordinator, _, sensors, queue) = fixture()
    try await coordinator.loadRoutes(destination: "test"); coordinator.selectRoute(coordinator.getSnapshot().routes[0]); _ = try coordinator.prepare(); _ = try coordinator.start()
    let id = try #require(coordinator.getSnapshot().session?.id)
    for sequence in 1...2 { sensors.simulate(.init(sessionId: id, chunkSeq: sequence, startedAt: Date(), endedAt: Date(), checksum: "\(sequence)", sampleCount: 10, clientEventId: "e\(sequence)", isSimulated: true)) }
    try await Task.sleep(for: .milliseconds(20)); #expect(queue.pending(sessionId: id).count == 2)
    await coordinator.sync(); #expect(queue.pending(sessionId: id).count == 2); #expect(coordinator.getSnapshot().session?.lastAckSeq == 0)
}

private actor RecordingPipeline: TelemetryPipeline {
    var chunks: [SensorChunk] = []; var flushes: [String?] = []
    func start() async {}; func stop() async {}; func enqueue(_ chunk: SensorChunk) async { chunks.append(chunk) }; func triggerUpload() async {}; func flush(sessionID: String?) async { flushes.append(sessionID) }; func summary() async -> TelemetryQueueSummary { .init(pendingCount: chunks.count, uploadingCount: 0, acknowledgedCount: 0, failedCount: 0, quarantinedCount: 0, totalBytes: 0, oldestPendingAt: nil, isStorageFull: false, nextRetryAt: nil) }
    func counts() -> (Int, Int) { (chunks.count, flushes.count) }
}

@Test @MainActor func coordinatorEnqueuesChunkAndFlushesPipelineOnFinish() async throws {
    let locations = MockLocationTracker(), sensors = MockSensorCollector(), pipeline = RecordingPipeline()
    let coordinator = ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: locations, sensors: sensors, routes: MockRouteRepository(), queue: MemoryTelemetryQueue(), progress: MockProgressServer(), telemetryPipeline: pipeline)
    try await coordinator.loadRoutes(destination: "test"); coordinator.selectRoute(coordinator.getSnapshot().routes[0]); _ = try coordinator.prepare(); _ = try coordinator.start()
    let id = try #require(coordinator.getSnapshot().session?.id); sensors.simulate(.init(sessionId: id, chunkSeq: 1, startedAt: Date(), endedAt: Date(), checksum: "x", sampleCount: 1, clientEventId: "e", isSimulated: true)); try await Task.sleep(for: .milliseconds(20))
    #expect(await pipeline.counts().0 == 1); _ = try await coordinator.finish(); #expect(await pipeline.counts().1 == 1); #expect(coordinator.getSnapshot().session?.state == .completed)
}
