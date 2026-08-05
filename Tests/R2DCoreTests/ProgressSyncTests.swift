import Foundation
import Testing
@testable import R2DCore

private actor ProgressRepositorySpy: IRideProgressRepository {
    var ride = RideProgress(validDistance: 120, confirmedDistance: 100, processingChunks: 1, acknowledgedChunks: 2, remainingChunks: 1)
    var boss: BossProgress? = .init(bossHP: 100, confirmedDamage: 0, pendingDamage: 10, processingState: .processing)
    var reward = RewardProgress(pendingReward: 5, confirmedReward: 0)
    var risk: String? = "risk-v2"
    var rideFetches = 0
    var delay: Duration = .zero
    func fetchRideProgress(rideId: String) async throws -> RideProgress { rideFetches += 1; try await Task.sleep(for: delay); return ride }
    func fetchBossProgress(rideId: String) async throws -> BossProgress? { try await Task.sleep(for: delay); return boss }
    func fetchRewardProgress(rideId: String) async throws -> RewardProgress { try await Task.sleep(for: delay); return reward }
    func fetchRiskLayerVersion(rideId: String) async throws -> String? { try await Task.sleep(for: delay); return risk }
    func set(ride: RideProgress? = nil, boss: BossProgress? = nil, reward: RewardProgress? = nil) {
        if let ride { self.ride = ride }; if let boss { self.boss = boss }; if let reward { self.reward = reward }
    }
    func setDelay(_ value: Duration) { delay = value }
    func count() -> Int { rideFetches }
}

private actor AcknowledgingPipeline: TelemetryPipeline {
    var handler: (@Sendable (TelemetryUploadAcknowledgement) async -> Void)?
    var value = TelemetryQueueSummary.empty
    func start() async {}; func stop() async {}; func enqueue(_ chunk: SensorChunk) async {}; func triggerUpload() async {}; func flush(sessionID: String?) async {}
    func summary() async -> TelemetryQueueSummary { value }
    func setUploadAcknowledgementHandler(_ handler: (@Sendable (TelemetryUploadAcknowledgement) async -> Void)?) async { self.handler = handler }
    func acknowledge(duplicate: Bool = false) async {
        let ack = TelemetryUploadAcknowledgement(queueItemID: UUID(), accepted: true, duplicate: duplicate, serverObservationID: "obs", acknowledgedAt: Date(), processingStatus: "ACCEPTED")
        await handler?(ack)
    }
    func setSummary(_ summary: TelemetryQueueSummary) { value = summary }
}

@MainActor private func progressFixture(repository: ProgressRepositorySpy, pipeline: AcknowledgingPipeline = .init()) async throws -> (ActiveRideCoordinator, AcknowledgingPipeline) {
    let coordinator = ActiveRideCoordinator(sessions: MemoryRideSessionRepository(), location: MockLocationTracker(), sensors: MockSensorCollector(), routes: MockRouteRepository(), queue: MemoryTelemetryQueue(), progress: repository, telemetryPipeline: pipeline, progressConfiguration: .init(pollingInterval: .seconds(3600)))
    try await coordinator.loadRoutes(destination: "test"); coordinator.selectRoute(coordinator.getSnapshot().routes[0]); _ = try coordinator.prepare(); _ = try coordinator.start()
    try await Task.sleep(for: .milliseconds(30)); return (coordinator, pipeline)
}

@Test @MainActor func uploadAckTriggersProgressAndDoesNotDirectlyReduceBossHP() async throws {
    let repository = ProgressRepositorySpy(), (coordinator, pipeline) = try await progressFixture(repository: repository)
    #expect(coordinator.getSnapshot().game?.remainingHp == 100)
    await repository.set(boss: .init(bossHP: 91, confirmedDamage: 9, pendingDamage: 0, processingState: .confirmed))
    await pipeline.acknowledge(); #expect(coordinator.getSnapshot().game?.remainingHp == 91)
}

@Test @MainActor func duplicateUploadAlsoTriggersAuthoritativeProgressFetch() async throws {
    let repository = ProgressRepositorySpy(), (coordinator, pipeline) = try await progressFixture(repository: repository)
    let before = await repository.count(); await pipeline.acknowledge(duplicate: true)
    #expect(await repository.count() == before + 1); #expect(coordinator.getSnapshot().game?.remainingHp == 100)
}

@Test func concurrentPollingIsCoalesced() async throws {
    let repository = ProgressRepositorySpy(); await repository.setDelay(.milliseconds(50)); let worker = RideProgressSyncWorker(repository: repository)
    async let first = worker.sync(rideId: "ride"); async let second = worker.sync(rideId: "ride"); _ = try await (first, second)
    #expect(await repository.count() == 1)
}

@Test @MainActor func finishPerformsLastPollAndBuildsServerSummary() async throws {
    let repository = ProgressRepositorySpy(), (coordinator, _) = try await progressFixture(repository: repository)
    await repository.set(ride: .init(validDistance: 777, confirmedDistance: 777, processingChunks: 0, acknowledgedChunks: 4, remainingChunks: 0), boss: .init(bossHP: 80, confirmedDamage: 20, pendingDamage: 0, processingState: .confirmed), reward: .init(pendingReward: 0, confirmedReward: 12))
    let summary = try await coordinator.finish(); #expect(summary.validDistanceM == 777); #expect(summary.confirmedBaseDamage == 20); #expect(summary.confirmedReward == 12); #expect(summary.isFinal)
}

@Test @MainActor func foregroundReturnPollsProgress() async throws {
    let repository = ProgressRepositorySpy(), (coordinator, _) = try await progressFixture(repository: repository); let before = await repository.count()
    await coordinator.applicationDidBecomeActive(); #expect(await repository.count() == before + 1)
}

@Test @MainActor func pendingProgressTransitionsToConfirmedOnlyFromServer() async throws {
    let repository = ProgressRepositorySpy(), (coordinator, _) = try await progressFixture(repository: repository)
    #expect(coordinator.getSnapshot().game?.processingState == .awaitingServer)
    await repository.set(boss: .init(bossHP: 95, confirmedDamage: 5, pendingDamage: 0, processingState: .confirmed)); await coordinator.sync()
    #expect(coordinator.getSnapshot().game?.processingState == .confirmed)
}

@Test @MainActor func bossHPIsSynchronizedFromBossProgress() async throws {
    let repository = ProgressRepositorySpy(), (coordinator, _) = try await progressFixture(repository: repository)
    await repository.set(boss: .init(bossHP: 73, confirmedDamage: 27, pendingDamage: 3, processingState: .processing)); await coordinator.sync()
    #expect(coordinator.getSnapshot().game?.remainingHp == 73); #expect(coordinator.getSnapshot().game?.confirmedTotalDamage == 27)
}

@Test @MainActor func rewardProgressIsSynchronized() async throws {
    let repository = ProgressRepositorySpy(), (coordinator, _) = try await progressFixture(repository: repository)
    await repository.set(reward: .init(pendingReward: 8, confirmedReward: 21)); await coordinator.sync()
    #expect(coordinator.getSnapshot().rewardProgress == .init(pendingReward: 8, confirmedReward: 21))
}

@Test @MainActor func queueSummarySurvivesProgressRefresh() async throws {
    let repository = ProgressRepositorySpy(), pipeline = AcknowledgingPipeline(); let (coordinator, _) = try await progressFixture(repository: repository, pipeline: pipeline)
    let summary = TelemetryQueueSummary(pendingCount: 3, uploadingCount: 1, acknowledgedCount: 2, failedCount: 0, quarantinedCount: 0, totalBytes: 99, oldestPendingAt: nil, isStorageFull: false, nextRetryAt: nil)
    await pipeline.setSummary(summary); await coordinator.refreshTelemetrySummary(); await coordinator.sync()
    #expect(coordinator.getSnapshot().telemetrySummary == summary); #expect(coordinator.getSnapshot().queuedChunkCount == 4)
}
