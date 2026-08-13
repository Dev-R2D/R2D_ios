import Foundation

/// NOTE: 안전 조건 및 유효성 검증 기준은 교수님 자문 완료 전임에 따라
/// 임시 권장값(Draft/Provisional Defaults)으로 설정되어 있으며, 자문 수립 후 쉽게 조정 가능합니다.
public struct SafetyAndValidationConfig: Codable, Equatable, Sendable {
    /// 안전 조건 임계값 (Draft)
    public var maxSafeSpeedKmh: Double = 25.0         // 초과 시 무효 처리 또는 경고
    public var maxImpactGForce: Double = 2.5          // 위험 주행/충격 유도 감지 임계치
    public var minValidSampleHz: Double = 10.0         // 센서 신뢰도 최소 샘플링 주파수
    
    /// 유효성 검증 임계값 (Draft)
    public var crossValidationRadiusM: Double = 10.0   // 동일 구간 관측 인정 반경
    public var minimumCrossValidationRiders: Int = 3  // 독립 라이더 최소 관측 수
    public var repairMaxDeviationM: Double = 5.0       // 노면 보수 판단 궤적 오차 범위
    public var repairMinimumNoImpactRiders: Int = 3   // 보수 확인 시 정상 통과 라이더 수

    public static let draft = SafetyAndValidationConfig()
}

/// Core algorithm engine for road data cross-validation and scoring.
public struct CrossValidationEngine: Sendable {
    public static let defaultConfig: SafetyAndValidationConfig = .draft

    public static var minionPassRadiusM: Double { 12.0 }
    public static var crossValidationRadiusM: Double { defaultConfig.crossValidationRadiusM }
    public static var minimumCrossValidationRiders: Int { defaultConfig.minimumCrossValidationRiders }
    public static var repairMaxTrajectoryDeviationM: Double { defaultConfig.repairMaxDeviationM }
    public static var repairMinimumNoImpactRiders: Int { defaultConfig.repairMinimumNoImpactRiders }
    
    public static let unscannedCellHp: Int = 500
    public static let refreshCellHp: Int = 300
    public static let activeRiderReference: Double = 50.0
    public static let minimumPopulationScale: Double = 0.25
    public static let maximumPopulationScale: Double = 1.50

    public init() {}

    /// Calculates population-scaled regional coverage workload:
    /// `totalWorkload = Math.round((unscanned * 500 + refresh * 300) * populationScale)`
    public static func calculateRegionalBossHealth(unscannedCells: Int, refreshCells: Int, activeRiders: Int) -> (rawHealth: Int, populationScale: Double, totalHealth: Int) {
        let rawHealth = unscannedCells * unscannedCellHp + refreshCells * refreshCellHp
        let scale = min(maximumPopulationScale, max(minimumPopulationScale, Double(activeRiders) / activeRiderReference))
        let totalHealth = max(1, Int((Double(rawHealth) * scale).rounded()))
        return (rawHealth, scale, totalHealth)
    }

    /// Evaluates 3-rider cross validation logic:
    /// Confirms damaged cell if 3+ independent rider logs detect IMU impact spikes within 10m.
    public static func crossValidate(riderLogs: [(offsetMeters: Double, spikeDetected: Bool)]) -> CrossValidationResult {
        let matchingCount = riderLogs.filter { $0.spikeDetected && $0.offsetMeters <= crossValidationRadiusM }.count
        let isVerified = matchingCount >= minimumCrossValidationRiders
        return CrossValidationResult(matchingRiders: matchingCount, isVerified: isVerified, radiusMeters: crossValidationRadiusM)
    }

    /// Evaluates repair confirmation:
    /// Trajectory deviation <= 5m AND 3+ riders passing with 0 impact spikes confirms road repair.
    public static func isRepairConfirmed(evidence: RepairEvidence) -> Bool {
        return evidence.isRepairConfirmed
    }

    /// Evaluates minion pass proximity and photo verification
    public static func evaluateMinionPass(distanceM: Double, photoVerified: Bool, spikeDetected: Bool, missionActive: Bool) -> (adjacentPass: Bool, cleared: Bool, rewardMileage: Int, reason: String) {
        let adjacentPass = distanceM <= minionPassRadiusM
        let cleared = adjacentPass && photoVerified
        let rewardMileage = (spikeDetected && missionActive) ? 60 : 0
        let reason: String
        if spikeDetected && !missionActive {
            reason = "incidental-spike-no-reward"
        } else if spikeDetected {
            reason = "mission-spike-rewarded"
        } else {
            reason = "no-spike"
        }
        return (adjacentPass, cleared, rewardMileage, reason)
    }
}
