import Foundation

public enum RideSessionState: String, Codable, Sendable {
    case created = "CREATED", ready = "READY", active = "ACTIVE", paused = "PAUSED"
    case finishing = "FINISHING", completed = "COMPLETED", aborted = "ABORTED"
}

public enum ActiveRideView: String, Codable, Sendable { case navigator = "NAVIGATOR", game = "GAME" }
public enum DataState: String, Codable, Sendable { case unknown = "UNKNOWN", stale = "STALE", review = "REVIEW", verified = "VERIFIED" }
public enum RiskState: String, Codable, Sendable {
    case normal = "NORMAL", rough = "ROUGH", suspectedDamage = "SUSPECTED_DAMAGE"
    case confirmedDamage = "CONFIRMED_DAMAGE", repairPending = "REPAIR_PENDING", restricted = "RESTRICTED"
}
public enum DataQualityGrade: String, Codable, Sendable { case a = "A", b = "B", c = "C", limited = "LIMITED" }
public enum ConnectionState: String, Codable, Sendable { case online = "ONLINE", delayed = "DELAYED", offline = "OFFLINE" }
public enum ProcessingState: String, Codable, Sendable { case idle = "IDLE", estimating = "ESTIMATING", awaitingServer = "AWAITING_SERVER", confirmed = "CONFIRMED" }
public enum ServerProcessingState: String, Codable, Sendable { case pending = "PENDING", processing = "PROCESSING", confirmed = "CONFIRMED" }
public enum RouteStatus: String, Codable, Sendable { case ready = "READY", active = "ACTIVE", offRoute = "OFF_ROUTE", completed = "COMPLETED", cancelled = "CANCELLED" }

public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double; public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public struct BossContext: Codable, Equatable, Sendable {
    public let bossId: String
    public let districtName: String
    public let bossTitle: String
    public let phase: String
    public let snapshotVersion: String
    public let maxHp: Int
    public let unknownCellCount: Int
    public let staleCellCount: Int
    public init(bossId: String, districtName: String = "화성시 동탄1동", bossTitle: String = "노면 파손의 섀도우 보스", phase: String = "DISCOVER", snapshotVersion: String = "boss-v1", maxHp: Int = 100, unknownCellCount: Int = 40, staleCellCount: Int = 25) {
        self.bossId = bossId; self.districtName = districtName; self.bossTitle = bossTitle; self.phase = phase; self.snapshotVersion = snapshotVersion; self.maxHp = maxHp; self.unknownCellCount = unknownCellCount; self.staleCellCount = staleCellCount
    }
}

public struct RideSession: Codable, Equatable, Sendable {
    public let id: String, userId: String, deviceId: String, deviceProfileId: String
    public var routeId: String?, state: RideSessionState
    public let createdAt: Date
    public var startedAt: Date?, endedAt: Date?
    public var localDistanceM: Double, validDistanceM: Double, routeProgressRatio: Double
    public var dataQualityGrade: DataQualityGrade
    public var bossContext: BossContext?
    public var lastChunkSeq: Int, lastAckSeq: Int

    public init(id: String, userId: String = "demo-user", deviceId: String = "demo-device", deviceProfileId: String = "bike-default", routeId: String?, state: RideSessionState = .created, createdAt: Date = Date(), bossContext: BossContext? = nil) {
        self.id = id; self.userId = userId; self.deviceId = deviceId; self.deviceProfileId = deviceProfileId
        self.routeId = routeId; self.state = state; self.createdAt = createdAt; self.bossContext = bossContext
        startedAt = nil; endedAt = nil; localDistanceM = 0; validDistanceM = 0; routeProgressRatio = 0
        dataQualityGrade = .limited; lastChunkSeq = 0; lastAckSeq = 0
    }
}

public struct Turn: Codable, Equatable, Sendable {
    public let coordinate: Coordinate, instruction: String, distance: Double
    public init(coordinate: Coordinate, instruction: String, distance: Double) { self.coordinate = coordinate; self.instruction = instruction; self.distance = distance }
}

public struct RiskCell: Identifiable, Codable, Equatable, Sendable {
    public let id: String, geometry: String, riskScore: Double, confidence: Double
    public init(id: String, geometry: String, riskScore: Double, confidence: Double) { self.id = id; self.geometry = geometry; self.riskScore = riskScore; self.confidence = confidence }
}

public struct GeoBoundingBox: Codable, Equatable, Sendable {
    public let minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double
    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) { self.minLatitude = minLatitude; self.minLongitude = minLongitude; self.maxLatitude = maxLatitude; self.maxLongitude = maxLongitude }
}

public enum RoadGeometry: Codable, Equatable, Sendable {
    case polyline([Coordinate])
    case point(Coordinate)
    public var coordinates: [Coordinate] { switch self { case .polyline(let values): values; case .point(let value): [value] } }
}

public struct Route: Identifiable, Codable, Equatable, Sendable {
    public let id: String, polyline: [Coordinate], totalDistance: Double, totalDuration: TimeInterval
    public let providerOption: String?, tollFee: Int?, taxiFare: Int?, totalTaxiFare: String?, isHighWay: Bool?
    public var remainingDistance: Double, remainingDuration: TimeInterval
    public let turnList: [Turn], riskCells: [RiskCell]
    public var status: RouteStatus
    public init(id: String, polyline: [Coordinate], totalDistance: Double, totalDuration: TimeInterval, providerOption: String? = nil, tollFee: Int? = nil, taxiFare: Int? = nil, totalTaxiFare: String? = nil, isHighWay: Bool? = nil, remainingDistance: Double? = nil, remainingDuration: TimeInterval? = nil, turnList: [Turn], riskCells: [RiskCell], status: RouteStatus = .ready) {
        self.id = id; self.polyline = polyline; self.totalDistance = totalDistance; self.totalDuration = totalDuration; self.providerOption = providerOption; self.tollFee = tollFee; self.taxiFare = taxiFare; self.totalTaxiFare = totalTaxiFare; self.isHighWay = isHighWay; self.remainingDistance = remainingDistance ?? totalDistance; self.remainingDuration = remainingDuration ?? totalDuration; self.turnList = turnList; self.riskCells = riskCells; self.status = status
    }
    public var routeId: String { id }
    public var distanceM: Double { totalDistance }
    public var durationSec: Int { Int(totalDuration.rounded()) }
}

public struct NavigationProgress: Equatable, Sendable {
    public let route: Route, matchedCoordinate: Coordinate?, nextTurn: Turn?, distanceToNextTurn: Double
    public let remainingDistance: Double, remainingDuration: TimeInterval, progressRatio: Double
    public let isOffRoute: Bool, rejectedGPSJump: Bool
    public init(route: Route, matchedCoordinate: Coordinate?, nextTurn: Turn?, distanceToNextTurn: Double, remainingDistance: Double, remainingDuration: TimeInterval, progressRatio: Double, isOffRoute: Bool, rejectedGPSJump: Bool) {
        self.route = route; self.matchedCoordinate = matchedCoordinate; self.nextTurn = nextTurn; self.distanceToNextTurn = distanceToNextTurn; self.remainingDistance = remainingDistance; self.remainingDuration = remainingDuration; self.progressRatio = progressRatio; self.isOffRoute = isOffRoute; self.rejectedGPSJump = rejectedGPSJump
    }
}

public struct RoadCell: Identifiable, Codable, Equatable, Sendable {
    public let id: String, geometry: RoadGeometry, dataState: DataState, riskState: RiskState
    public let riskScore: Int, confidence: Double, lastObservedAt: Date?, validUntil: Date?
    public let observationCount: Int, independentDeviceCount: Int, cellVersion: String, layerVersion: String
    public init(id: String, geometry: RoadGeometry, dataState: DataState, riskState: RiskState, riskScore: Int, confidence: Double, lastObservedAt: Date?, validUntil: Date?, observationCount: Int, independentDeviceCount: Int, cellVersion: String, layerVersion: String) {
        self.id = id; self.geometry = geometry; self.dataState = dataState; self.riskState = riskState; self.riskScore = riskScore; self.confidence = confidence; self.lastObservedAt = lastObservedAt; self.validUntil = validUntil; self.observationCount = observationCount; self.independentDeviceCount = independentDeviceCount; self.cellVersion = cellVersion; self.layerVersion = layerVersion
    }
}

public struct RiskLayerSnapshot: Codable, Equatable, Sendable {
    public let layerVersion: String, generatedAt: Date, expiresAt: Date?, cells: [RoadCell], notModified: Bool, isSimulated: Bool
    public init(layerVersion: String, generatedAt: Date, expiresAt: Date?, cells: [RoadCell], notModified: Bool = false, isSimulated: Bool = false) { self.layerVersion = layerVersion; self.generatedAt = generatedAt; self.expiresAt = expiresAt; self.cells = cells; self.notModified = notModified; self.isSimulated = isSimulated }
    public func isStale(at date: Date) -> Bool { expiresAt.map { $0 <= date } ?? false }
    enum CodingKeys: String, CodingKey { case layerVersion, generatedAt, expiresAt, cells, notModified, isSimulated }
    public init(from decoder: Decoder) throws { let values = try decoder.container(keyedBy: CodingKeys.self); layerVersion = try values.decode(String.self, forKey: .layerVersion); generatedAt = try values.decode(Date.self, forKey: .generatedAt); expiresAt = try values.decodeIfPresent(Date.self, forKey: .expiresAt); cells = try values.decode([RoadCell].self, forKey: .cells); notModified = try values.decodeIfPresent(Bool.self, forKey: .notModified) ?? false; isSimulated = try values.decodeIfPresent(Bool.self, forKey: .isSimulated) ?? false }
}

public struct LocationSnapshot: Equatable, Sendable {
    public var coordinate: Coordinate?, speedMps: Double, heading: Double, mapMatchConfidence: Double
    public init(coordinate: Coordinate?, speedMps: Double, heading: Double, mapMatchConfidence: Double) {
        self.coordinate = coordinate; self.speedMps = speedMps; self.heading = heading; self.mapMatchConfidence = mapMatchConfidence
    }
    public static let empty = Self(coordinate: nil, speedMps: 0, heading: 0, mapMatchConfidence: 0)
}

public enum LocationAuthorizationState: String, Equatable, Sendable {
    case notDetermined, denied, restricted, authorizedWhenInUse, authorizedAlways
}
public enum LocationSampleQuality: String, Equatable, Sendable { case valid, implausibleJump }
public struct LocationSample: Equatable, Sendable {
    public let latitude: Double, longitude: Double, altitudeM: Double?, speedMps: Double?, bearingDegrees: Double?
    public let horizontalAccuracyM: Double, timestamp: Date, quality: LocationSampleQuality
    public init(latitude: Double, longitude: Double, altitudeM: Double?, speedMps: Double?, bearingDegrees: Double?, horizontalAccuracyM: Double, timestamp: Date, quality: LocationSampleQuality = .valid) {
        self.latitude = latitude; self.longitude = longitude; self.altitudeM = altitudeM; self.speedMps = speedMps; self.bearingDegrees = bearingDegrees; self.horizontalAccuracyM = horizontalAccuracyM; self.timestamp = timestamp; self.quality = quality
    }
}
public struct LocationReadiness: Equatable, Sendable {
    public let servicesEnabled: Bool, authorization: LocationAuthorizationState, isAccuracySufficient: Bool
    public init(servicesEnabled: Bool, authorization: LocationAuthorizationState, isAccuracySufficient: Bool) { self.servicesEnabled = servicesEnabled; self.authorization = authorization; self.isAccuracySufficient = isAccuracySufficient }
    public var canStart: Bool { servicesEnabled && [.authorizedWhenInUse, .authorizedAlways].contains(authorization) }
}
public struct SensorReadiness: Equatable, Sendable {
    public let accelerometerAvailable: Bool, gyroscopeAvailable: Bool, motionAvailable: Bool
    public let isCollecting: Bool, effectiveHz: Double, sampleCount: Int, droppedSampleRatio: Double, lastSampleAt: Date?
    public init(accelerometerAvailable: Bool, gyroscopeAvailable: Bool, motionAvailable: Bool, isCollecting: Bool = false, effectiveHz: Double = 0, sampleCount: Int = 0, droppedSampleRatio: Double = 0, lastSampleAt: Date? = nil) {
        self.accelerometerAvailable = accelerometerAvailable; self.gyroscopeAvailable = gyroscopeAvailable; self.motionAvailable = motionAvailable; self.isCollecting = isCollecting; self.effectiveHz = effectiveHz; self.sampleCount = sampleCount; self.droppedSampleRatio = droppedSampleRatio; self.lastSampleAt = lastSampleAt
    }
    public var canStart: Bool { accelerometerAvailable || gyroscopeAvailable || motionAvailable }
}

public struct SensorChunk: Codable, Equatable, Sendable {
    public let sessionId: String, chunkSeq: Int, startedAt: Date, endedAt: Date
    public let checksum: String, sampleCount: Int, clientEventId: String, isSimulated: Bool
    public let payload: Data
    public init(sessionId: String, chunkSeq: Int, startedAt: Date, endedAt: Date, checksum: String, sampleCount: Int, clientEventId: String, isSimulated: Bool, payload: Data = Data()) {
        self.sessionId = sessionId; self.chunkSeq = chunkSeq; self.startedAt = startedAt; self.endedAt = endedAt; self.checksum = checksum; self.sampleCount = sampleCount; self.clientEventId = clientEventId; self.isSimulated = isSimulated
        self.payload = payload
    }
}

public struct SensorLogImportResult: Equatable, Sendable {
    public let recordingId: String, fileCount: Int, sampleCount: Int, chunkCount: Int
    public let extractedCoordinates: [Coordinate]
    public let imuSpikeCount: Int
    public init(recordingId: String, fileCount: Int, sampleCount: Int, chunkCount: Int, extractedCoordinates: [Coordinate] = [], imuSpikeCount: Int = 0) {
        self.recordingId = recordingId; self.fileCount = fileCount; self.sampleCount = sampleCount; self.chunkCount = chunkCount
        self.extractedCoordinates = extractedCoordinates; self.imuSpikeCount = imuSpikeCount
    }
}

public enum TelemetryQueueItemState: String, Codable, Sendable { case pending, uploading, acknowledged, failed, quarantined }
public struct TelemetryQueueItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID, sessionID: String, chunkSequence: Int, clientEventID: String, idempotencyKey: String
    public let createdAt: Date, startedAt: Date, endedAt: Date, checksum: String, payloadFileName: String
    public let payloadByteCount: Int, sampleCount: Int, isSimulated: Bool
    public var state: TelemetryQueueItemState, retryCount: Int, nextRetryAt: Date?, lastAttemptAt: Date?, acknowledgedAt: Date?, lastErrorCode: String?
    public init(id: UUID, sessionID: String, chunkSequence: Int, clientEventID: String, idempotencyKey: String, createdAt: Date, startedAt: Date, endedAt: Date, checksum: String, payloadFileName: String, payloadByteCount: Int, sampleCount: Int, isSimulated: Bool, state: TelemetryQueueItemState = .pending, retryCount: Int = 0, nextRetryAt: Date? = nil, lastAttemptAt: Date? = nil, acknowledgedAt: Date? = nil, lastErrorCode: String? = nil) {
        self.id = id; self.sessionID = sessionID; self.chunkSequence = chunkSequence; self.clientEventID = clientEventID; self.idempotencyKey = idempotencyKey; self.createdAt = createdAt; self.startedAt = startedAt; self.endedAt = endedAt; self.checksum = checksum; self.payloadFileName = payloadFileName; self.payloadByteCount = payloadByteCount; self.sampleCount = sampleCount; self.isSimulated = isSimulated; self.state = state; self.retryCount = retryCount; self.nextRetryAt = nextRetryAt; self.lastAttemptAt = lastAttemptAt; self.acknowledgedAt = acknowledgedAt; self.lastErrorCode = lastErrorCode
    }
}
public struct TelemetryQueueSummary: Sendable, Equatable {
    public let pendingCount: Int, uploadingCount: Int, acknowledgedCount: Int, failedCount: Int, quarantinedCount: Int
    public let totalBytes: Int64, oldestPendingAt: Date?, isStorageFull: Bool, nextRetryAt: Date?
    public static let empty = Self(pendingCount: 0, uploadingCount: 0, acknowledgedCount: 0, failedCount: 0, quarantinedCount: 0, totalBytes: 0, oldestPendingAt: nil, isStorageFull: false, nextRetryAt: nil)
    public init(pendingCount: Int, uploadingCount: Int, acknowledgedCount: Int, failedCount: Int, quarantinedCount: Int, totalBytes: Int64, oldestPendingAt: Date?, isStorageFull: Bool, nextRetryAt: Date?) { self.pendingCount = pendingCount; self.uploadingCount = uploadingCount; self.acknowledgedCount = acknowledgedCount; self.failedCount = failedCount; self.quarantinedCount = quarantinedCount; self.totalBytes = totalBytes; self.oldestPendingAt = oldestPendingAt; self.isStorageFull = isStorageFull; self.nextRetryAt = nextRetryAt }
    public var unsentCount: Int { pendingCount + uploadingCount + failedCount }
}
public struct TelemetryIntegrityReport: Sendable, Equatable {
    public var validItemCount = 0, restoredUploadingCount = 0, missingPayloadCount = 0, orphanPayloadCount = 0, checksumFailureCount = 0, decryptionFailureCount = 0, quarantinedCount = 0
    public init() {}
}
public struct TelemetryUploadAcknowledgement: Sendable, Codable, Equatable {
    public let queueItemID: UUID, accepted: Bool, duplicate: Bool, serverObservationID: String?, acknowledgedAt: Date, processingStatus: String?
    public init(queueItemID: UUID, accepted: Bool, duplicate: Bool, serverObservationID: String?, acknowledgedAt: Date, processingStatus: String?) { self.queueItemID = queueItemID; self.accepted = accepted; self.duplicate = duplicate; self.serverObservationID = serverObservationID; self.acknowledgedAt = acknowledgedAt; self.processingStatus = processingStatus }
}
public enum TelemetryUploadError: Error, Sendable, Equatable { case offline, timeout, rateLimited(retryAfter: TimeInterval?), unauthorized, forbidden, validationFailed(code: String), serverFailure(statusCode: Int), invalidResponse, permanentRejection(code: String) }

public struct NavigationInstruction: Equatable, Sendable { public let title: String; public let distanceM: Double; public init(title: String, distanceM: Double) { self.title = title; self.distanceM = distanceM } }
public enum RoadWarningSeverity: String, Sendable { case informational, caution, high }
public struct RoadWarning: Identifiable, Equatable, Sendable {
    public let id: String, cellID: String, riskState: RiskState, severity: RoadWarningSeverity
    public let distanceM: Double, confidence: Double, messageKey: String, triggeredAt: Date
    public init(id: String, cellID: String, riskState: RiskState, severity: RoadWarningSeverity, distanceM: Double, confidence: Double, messageKey: String, triggeredAt: Date) { self.id = id; self.cellID = cellID; self.riskState = riskState; self.severity = severity; self.distanceM = distanceM; self.confidence = confidence; self.messageKey = messageKey; self.triggeredAt = triggeredAt }
}

public enum DamageType: String, Codable, Sendable {
    case baseDistance = "BASE_DISTANCE"
    case unknownDiscovery = "UNKNOWN_DISCOVERY"
    case staleRefresh = "STALE_REFRESH"
    case reviewValidation = "REVIEW_VALIDATION"
}

public struct DamageFeedItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let damage: Int
    public let isConfirmed: Bool
    public let type: DamageType
    public let timestamp: Date
    public init(id: UUID = UUID(), title: String, damage: Int, isConfirmed: Bool = false, type: DamageType = .baseDistance, timestamp: Date = Date()) {
        self.id = id; self.title = title; self.damage = damage; self.isConfirmed = isConfirmed; self.type = type; self.timestamp = timestamp
    }
}

public struct GameSkill: Equatable, Sendable {
    public let name: String
    public let description: String
    public let iconName: String
    public var gauge: Double
    public var activeTriggerMessage: String?
    public var isReady: Bool { gauge >= 1.0 }
    public init(name: String = "정밀 탐사 (Precision Probe)", description: String = "신규/갱신 셀 수집 시 데이터 공격력 증폭", iconName: String = "sparkles", gauge: Double = 0.0, activeTriggerMessage: String? = nil) {
        self.name = name; self.description = description; self.iconName = iconName; self.gauge = gauge; self.activeTriggerMessage = activeTriggerMessage
    }
}

public enum DeckCardType: String, Codable, Sendable {
    case pioneer = "PIONEER"        // 개척: 처음 가는 길/미탐사 구간 보너스
    case recon = "RECON"            // 정찰: 오래 갱신되지 않은 구간 보너스
    case finish = "FINISH"          // 완주: 유효 주행거리 기본 피해 & 완주 보상
    case validation = "VALIDATION"  // 검증: 의심/낮은 신뢰도 구간 협동 보너스
    
    // Legacy mapping aliases
    case sprinter = "SPRINTER"
    case scout = "SCOUT"
    case support = "SUPPORT"
    case tracker = "TRACKER"
    case router = "ROUTER"
    
    public var categoryDisplayName: String {
        switch self {
        case .pioneer, .sprinter: return "개척"
        case .recon, .scout, .tracker: return "정찰"
        case .finish, .router: return "완주"
        case .validation, .support: return "검증"
        }
    }
}

public enum CardGrade: String, Codable, Sendable {
    case bronze = "BRONZE"
    case silver = "SILVER"
    case gold = "GOLD"
    case signature = "SIGNATURE"
}

public struct DeckCard: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let type: DeckCardType
    public let grade: CardGrade
    public let damageMultiplier: Double
    public let mileageMultiplier: Double
    public let effect: String
    public let glyph: String

    public init(id: String = UUID().uuidString, name: String, type: DeckCardType, grade: CardGrade, damageMultiplier: Double, mileageMultiplier: Double, effect: String, glyph: String) {
        self.id = id; self.name = name; self.type = type; self.grade = grade; self.damageMultiplier = damageMultiplier; self.mileageMultiplier = mileageMultiplier; self.effect = effect; self.glyph = glyph
    }
}

public struct SquadDeck: Codable, Equatable, Sendable {
    public var equippedCards: [DeckCard]
    
    /// Synergy calculation based on PDF rules:
    /// Same category 2 cards -> Category Synergy (+5% bonus)
    /// Same category 3 cards -> Superior Synergy (+15% bonus)
    public var categorySynergyMultiplier: Double {
        let categoryCounts = Dictionary(grouping: equippedCards, by: { $0.type.categoryDisplayName })
        let maxCount = categoryCounts.values.map(\.count).max() ?? 0
        if maxCount >= 3 {
            return 1.15 // 3장 상위 시너지
        } else if maxCount >= 2 {
            return 1.05 // 2장 계열 시너지
        }
        return 1.00
    }
    
    public var synergyDescription: String? {
        let categoryCounts = Dictionary(grouping: equippedCards, by: { $0.type.categoryDisplayName })
        if let (cat, _) = categoryCounts.first(where: { $0.value.count >= 3 }) {
            return "🔥 [\(cat)] 3장 상위 시너지 발동 (DMG +15%)"
        } else if let (cat, _) = categoryCounts.first(where: { $0.value.count >= 2 }) {
            return "⚡️ [\(cat)] 2장 계열 시너지 발동 (DMG +5%)"
        }
        return nil
    }
    
    public var totalDamageMultiplier: Double {
        let base = equippedCards.reduce(1.0) { $0 * $1.damageMultiplier }
        return base * categorySynergyMultiplier
    }
    
    public var totalMileageMultiplier: Double {
        equippedCards.reduce(1.0) { $0 * $1.mileageMultiplier }
    }

    /// PDF Specification 3-Card Deck Starter Setup
    public static let starter = SquadDeck(equippedCards: [
        DeckCard(id: "card-01", name: "개척의 풋프린트", type: .pioneer, grade: .gold, damageMultiplier: 1.15, mileageMultiplier: 1.00, effect: "미탐사 구간 진입 시 보너스 타격", glyph: "map.fill"),
        DeckCard(id: "card-02", name: "정찰의 레이더", type: .recon, grade: .silver, damageMultiplier: 1.08, mileageMultiplier: 1.10, effect: "오래된 구간 재탐사 마일리지 +10%", glyph: "antenna.radiowaves.left.and.right"),
        DeckCard(id: "card-03", name: "완주자의 휠", type: .finish, grade: .bronze, damageMultiplier: 1.05, mileageMultiplier: 1.15, effect: "유효 거리 기본 피해 +5%", glyph: "flag.checkered")
    ])

    public init(equippedCards: [DeckCard]) {
        self.equippedCards = equippedCards
    }
}

public struct CrossValidationResult: Codable, Equatable, Sendable {
    public let matchingRiders: Int
    public let isVerified: Bool
    public let radiusMeters: Double
    public init(matchingRiders: Int, isVerified: Bool, radiusMeters: Double = 10.0) {
        self.matchingRiders = matchingRiders; self.isVerified = isVerified; self.radiusMeters = radiusMeters
    }
}

public struct RepairEvidence: Codable, Equatable, Sendable {
    public let maxTrajectoryDeviationM: Double
    public let noImpactRiderCount: Int
    public var isRepairConfirmed: Bool {
        maxTrajectoryDeviationM <= 5.0 && noImpactRiderCount >= 3
    }
    public init(maxTrajectoryDeviationM: Double, noImpactRiderCount: Int) {
        self.maxTrajectoryDeviationM = maxTrajectoryDeviationM; self.noImpactRiderCount = noImpactRiderCount
    }
}

public struct MinionMonster: Identifiable, Equatable, Sendable {
    public let id: String
    public let cellId: String
    public let title: String
    public let dataState: DataState
    public var remainingHp: Int
    public let maxHp: Int
    public var isDefeated: Bool { remainingHp <= 0 }
    public init(id: String = "minion-01", cellId: String = "cell-review-88", title: String = "REVIEW 포트홀 교차검증 몬스터", dataState: DataState = .review, remainingHp: Int = 30, maxHp: Int = 30) {
        self.id = id; self.cellId = cellId; self.title = title; self.dataState = dataState; self.remainingHp = remainingHp; self.maxHp = maxHp
    }
}

public struct GameProgress: Equatable, Sendable {
    public let bossId: String
    public let districtName: String
    public let bossTitle: String
    public let phase: String
    public let bossSnapshotVersion: String
    public let maxHp: Int
    public let unknownCellCount: Int
    public let staleCellCount: Int
    public var remainingHp: Int
    public var estimatedBaseDamage: Int
    public var confirmedBaseDamage: Int
    public var estimatedDataDamage: Int
    public var confirmedDataDamage: Int
    public var connectionState: ConnectionState
    public var processingState: ProcessingState
    public var damageFeed: [DamageFeedItem]
    public var skill: GameSkill
    public var currentMinion: MinionMonster?
    public var squadDeck: SquadDeck
    public var crossValidation: CrossValidationResult?

    public var estimatedTotalDamage: Int {
        Int(Double(estimatedBaseDamage + estimatedDataDamage) * squadDeck.totalDamageMultiplier)
    }
    public var confirmedTotalDamage: Int {
        Int(Double(confirmedBaseDamage + confirmedDataDamage) * squadDeck.totalDamageMultiplier)
    }
    public var skillReady: Bool { skill.isReady }

    public init(bossId: String, districtName: String = "화성시 동탄1동", bossTitle: String = "노면 파손의 섀도우 보스", phase: String = "DISCOVER", bossSnapshotVersion: String = "boss-v1", maxHp: Int = 100, unknownCellCount: Int = 40, staleCellCount: Int = 25, remainingHp: Int = 100, estimatedBaseDamage: Int = 0, confirmedBaseDamage: Int = 0, estimatedDataDamage: Int = 0, confirmedDataDamage: Int = 0, connectionState: ConnectionState = .online, processingState: ProcessingState = .idle, damageFeed: [DamageFeedItem] = [], skill: GameSkill = GameSkill(), currentMinion: MinionMonster? = nil, squadDeck: SquadDeck = .starter, crossValidation: CrossValidationResult? = nil) {
        self.bossId = bossId; self.districtName = districtName; self.bossTitle = bossTitle; self.phase = phase
        self.bossSnapshotVersion = bossSnapshotVersion; self.maxHp = maxHp; self.unknownCellCount = unknownCellCount; self.staleCellCount = staleCellCount
        self.remainingHp = remainingHp; self.estimatedBaseDamage = estimatedBaseDamage; self.confirmedBaseDamage = confirmedBaseDamage
        self.estimatedDataDamage = estimatedDataDamage; self.confirmedDataDamage = confirmedDataDamage
        self.connectionState = connectionState; self.processingState = processingState
        self.damageFeed = damageFeed; self.skill = skill; self.currentMinion = currentMinion
        self.squadDeck = squadDeck; self.crossValidation = crossValidation
    }
}

public enum MissionType: String, Codable, Sendable { case explore = "EXPLORE", refresh = "REFRESH", verify = "VERIFY" }

public struct GameMission: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let district: String
    public let type: MissionType
    public let rewardPoints: Int
    public let isVerifierOnly: Bool
    public var isAccepted: Bool
    public init(id: String, title: String, district: String, type: MissionType, rewardPoints: Int, isVerifierOnly: Bool = false, isAccepted: Bool = false) {
        self.id = id; self.title = title; self.district = district; self.type = type; self.rewardPoints = rewardPoints; self.isVerifierOnly = isVerifierOnly; self.isAccepted = isAccepted
    }
}

public enum LedgerType: String, Codable, Sendable {
    case rideBase = "RIDE_BASE"
    case cellDiscovery = "CELL_DISCOVERY"
    case cellRefresh = "CELL_REFRESH"
    case cellValidation = "CELL_VALIDATION"
    case bossDefeat = "BOSS_DEFEAT"
}

public struct RewardLedgerItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let type: LedgerType
    public let title: String
    public let amount: Int
    public let createdAt: Date
    public let isConfirmed: Bool
    public init(id: String = UUID().uuidString, type: LedgerType, title: String, amount: Int, createdAt: Date = Date(), isConfirmed: Bool = true) {
        self.id = id; self.type = type; self.title = title; self.amount = amount; self.createdAt = createdAt; self.isConfirmed = isConfirmed
    }
}

public struct CouponItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let merchantName: String
    public let title: String
    public let discountText: String
    public let requiredPoints: Int
    public let validUntil: String
    public var isClaimed: Bool
    public var isRedeemed: Bool
    public let qrCode: String
    public init(id: String, merchantName: String, title: String, discountText: String, requiredPoints: Int, validUntil: String, isClaimed: Bool = false, isRedeemed: Bool = false, qrCode: String = "R2D-COUPON-2026") {
        self.id = id; self.merchantName = merchantName; self.title = title; self.discountText = discountText; self.requiredPoints = requiredPoints; self.validUntil = validUntil; self.isClaimed = isClaimed; self.isRedeemed = isRedeemed; self.qrCode = qrCode
    }
}

public struct RideProgress: Codable, Equatable, Sendable {
    public let validDistance: Double, confirmedDistance: Double
    public let processingChunks: Int, acknowledgedChunks: Int, remainingChunks: Int
    public init(validDistance: Double, confirmedDistance: Double, processingChunks: Int, acknowledgedChunks: Int, remainingChunks: Int) {
        self.validDistance = validDistance; self.confirmedDistance = confirmedDistance; self.processingChunks = processingChunks; self.acknowledgedChunks = acknowledgedChunks; self.remainingChunks = remainingChunks
    }
}

public struct BossProgress: Codable, Equatable, Sendable {
    public let bossHP: Int, confirmedDamage: Int, pendingDamage: Int, processingState: ServerProcessingState
    public init(bossHP: Int, confirmedDamage: Int, pendingDamage: Int, processingState: ServerProcessingState) {
        self.bossHP = bossHP; self.confirmedDamage = confirmedDamage; self.pendingDamage = pendingDamage; self.processingState = processingState
    }
}

public struct RewardProgress: Codable, Equatable, Sendable {
    public let pendingReward: Int, confirmedReward: Int
    public init(pendingReward: Int, confirmedReward: Int) { self.pendingReward = pendingReward; self.confirmedReward = confirmedReward }
}

public struct ServerProgressSnapshot: Equatable, Sendable {
    public let ride: RideProgress, boss: BossProgress?, reward: RewardProgress, riskLayerVersion: String?
    public init(ride: RideProgress, boss: BossProgress?, reward: RewardProgress, riskLayerVersion: String?) {
        self.ride = ride; self.boss = boss; self.reward = reward; self.riskLayerVersion = riskLayerVersion
    }
}

public struct ActiveRideState: Equatable, Sendable {
    public var session: RideSession?, activeView: ActiveRideView = .navigator
    public var location: LocationSnapshot = .empty, selectedRoute: Route?
    public var routes: [Route] = [], game: GameProgress?
    public var nextInstruction: NavigationInstruction?, connectionState: ConnectionState = .online
    public var queuedChunkCount = 0, lastRiskLayerUpdate: Date? = nil
    public var locationReadiness = LocationReadiness(servicesEnabled: true, authorization: .authorizedWhenInUse, isAccuracySufficient: true)
    public var sensorReadiness = SensorReadiness(accelerometerAvailable: true, gyroscopeAvailable: true, motionAvailable: true)
    public var presentationError: RidePresentationError? = nil
    public var telemetrySummary = TelemetryQueueSummary.empty
    public var rideProgress: RideProgress? = nil
    public var rewardProgress: RewardProgress? = nil
    public var riskLayerVersion: String? = nil
    public var navigationProgress: NavigationProgress? = nil
    public var isRerouting = false
    public var mapState = MapState.empty
    public var riskLayerSnapshot: RiskLayerSnapshot? = nil
    public var roadWarning: RoadWarning? = nil
    public static let idle = ActiveRideState()
}

public enum RidePresentationError: String, Equatable, Sendable { case locationPermissionRequired, locationUnavailable, sensorUnavailable, collectionStartFailed }

public struct RideSummary: Equatable, Sendable {
    public let sessionId: String, localDistanceM: Double, validDistanceM: Double
    public let confirmedBaseDamage: Int, confirmedDataDamage: Int, isFinal: Bool
    public let pendingReward: Int, confirmedReward: Int
    public init(sessionId: String, localDistanceM: Double, validDistanceM: Double, confirmedBaseDamage: Int, confirmedDataDamage: Int, isFinal: Bool, pendingReward: Int = 0, confirmedReward: Int = 0) {
        self.sessionId = sessionId; self.localDistanceM = localDistanceM; self.validDistanceM = validDistanceM; self.confirmedBaseDamage = confirmedBaseDamage; self.confirmedDataDamage = confirmedDataDamage; self.isFinal = isFinal
        self.pendingReward = pendingReward; self.confirmedReward = confirmedReward
    }
}
