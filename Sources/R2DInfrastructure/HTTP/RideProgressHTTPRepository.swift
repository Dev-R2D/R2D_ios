import Foundation
import R2DCore

public struct RideProgressHTTPRepository: IRideProgressRepository {
    private let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }

    public func fetchRideProgress(rideId: String) async throws -> RideProgress {
        let response = try await progressResponse(rideId: rideId); return response.progress
    }
    public func fetchBossProgress(rideId: String) async throws -> BossProgress? {
        let response = try await client.send(.init(path: "/v1/rides/\(escaped(rideId))/boss", method: .get))
        let value = try decoder.decode(BossResponse.self, from: response.body); return value.progress
    }
    public func fetchRewardProgress(rideId: String) async throws -> RewardProgress {
        let response = try await client.send(.init(path: "/v1/rides/\(escaped(rideId))/reward", method: .get))
        let value = try decoder.decode(RewardResponse.self, from: response.body); return value.progress
    }
    public func fetchRiskLayerVersion(rideId: String) async throws -> String? { let response = try await progressResponse(rideId: rideId); return response.riskLayerVersion }

    private func progressResponse(rideId: String) async throws -> ProgressResponse {
        let response = try await client.send(.init(path: "/v1/rides/\(escaped(rideId))/progress", method: .get))
        do { return try decoder.decode(ProgressResponse.self, from: response.body) } catch { throw TelemetryUploadError.invalidResponse }
    }
    private var decoder: JSONDecoder { JSONDecoder() }
    private func escaped(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value }
}

private struct BossResponse: Decodable {
    let bossHP: Int, confirmedDamage: Int, pendingDamage: Int, processingState: ServerProcessingState
    var progress: BossProgress { .init(bossHP: bossHP, confirmedDamage: confirmedDamage, pendingDamage: pendingDamage, processingState: processingState) }
    enum CodingKeys: String, CodingKey { case bossHP = "boss_hp", confirmedDamage = "confirmed_damage", pendingDamage = "pending_damage", processingState = "processing_state" }
}

private struct RewardResponse: Decodable {
    let pendingReward: Int, confirmedReward: Int
    var progress: RewardProgress { .init(pendingReward: pendingReward, confirmedReward: confirmedReward) }
    enum CodingKeys: String, CodingKey { case pendingReward = "pending_reward", confirmedReward = "confirmed_reward" }
}

private struct ProgressResponse: Decodable {
    let progress: RideProgress, riskLayerVersion: String?
    enum CodingKeys: String, CodingKey { case riskLayerVersion = "risk_layer_version"; case validDistance = "valid_distance", confirmedDistance = "confirmed_distance", processingChunks = "processing_chunks", acknowledgedChunks = "acknowledged_chunks", remainingChunks = "remaining_chunks" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        progress = .init(validDistance: try values.decode(Double.self, forKey: .validDistance), confirmedDistance: try values.decode(Double.self, forKey: .confirmedDistance), processingChunks: try values.decode(Int.self, forKey: .processingChunks), acknowledgedChunks: try values.decode(Int.self, forKey: .acknowledgedChunks), remainingChunks: try values.decode(Int.self, forKey: .remainingChunks))
        riskLayerVersion = try values.decodeIfPresent(String.self, forKey: .riskLayerVersion)
    }
}
