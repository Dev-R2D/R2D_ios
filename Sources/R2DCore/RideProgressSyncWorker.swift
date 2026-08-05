import Foundation

public struct RideProgressSyncConfiguration: Sendable {
    public let pollingInterval: Duration
    public init(pollingInterval: Duration = .seconds(15)) { self.pollingInterval = pollingInterval }
}

public actor RideProgressSyncWorker {
    private let repository: IRideProgressRepository, configuration: RideProgressSyncConfiguration
    private var pollingTask: Task<Void, Never>?, inFlight: Task<ServerProgressSnapshot, Error>?
    private var continuation: AsyncStream<ServerProgressSnapshot>.Continuation?

    public init(repository: IRideProgressRepository, configuration: RideProgressSyncConfiguration = .init()) {
        self.repository = repository; self.configuration = configuration
    }

    public func updates() -> AsyncStream<ServerProgressSnapshot> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    public func startPolling(rideId: String) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                _ = try? await self?.sync(rideId: rideId)
                try? await Task.sleep(for: self?.configuration.pollingInterval ?? .seconds(15))
            }
        }
    }

    public func stopPolling() { pollingTask?.cancel(); pollingTask = nil }

    @discardableResult public func sync(rideId: String) async throws -> ServerProgressSnapshot {
        if let inFlight { return try await inFlight.value }
        let repository = self.repository
        let task = Task<ServerProgressSnapshot, Error> {
            async let ride = repository.fetchRideProgress(rideId: rideId)
            async let boss = repository.fetchBossProgress(rideId: rideId)
            async let reward = repository.fetchRewardProgress(rideId: rideId)
            async let risk = repository.fetchRiskLayerVersion(rideId: rideId)
            return try await .init(ride: ride, boss: boss, reward: reward, riskLayerVersion: risk)
        }
        inFlight = task
        do { let value = try await task.value; inFlight = nil; continuation?.yield(value); return value }
        catch { inFlight = nil; throw error }
    }
}
