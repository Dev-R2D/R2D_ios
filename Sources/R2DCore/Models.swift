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
    public let bossId: String; public let snapshotVersion: String; public let maxHp: Int
    public init(bossId: String, snapshotVersion: String, maxHp: Int) { self.bossId = bossId; self.snapshotVersion = snapshotVersion; self.maxHp = maxHp }
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
    public var remainingDistance: Double, remainingDuration: TimeInterval
    public let turnList: [Turn], riskCells: [RiskCell]
    public var status: RouteStatus
    public init(id: String, polyline: [Coordinate], totalDistance: Double, totalDuration: TimeInterval, remainingDistance: Double? = nil, remainingDuration: TimeInterval? = nil, turnList: [Turn], riskCells: [RiskCell], status: RouteStatus = .ready) {
        self.id = id; self.polyline = polyline; self.totalDistance = totalDistance; self.totalDuration = totalDuration; self.remainingDistance = remainingDistance ?? totalDistance; self.remainingDuration = remainingDuration ?? totalDuration; self.turnList = turnList; self.riskCells = riskCells; self.status = status
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

public struct GameProgress: Equatable, Sendable {
    public let bossId: String, bossSnapshotVersion: String, maxHp: Int
    public var remainingHp: Int, estimatedBaseDamage: Int, confirmedBaseDamage: Int
    public var estimatedDataDamage: Int, confirmedDataDamage: Int, skillGauge: Double
    public var connectionState: ConnectionState, processingState: ProcessingState
    public var estimatedTotalDamage: Int { estimatedBaseDamage + estimatedDataDamage }
    public var confirmedTotalDamage: Int { confirmedBaseDamage + confirmedDataDamage }
    public var skillReady: Bool { skillGauge >= 1 }
    public init(bossId: String, bossSnapshotVersion: String, maxHp: Int, remainingHp: Int, estimatedBaseDamage: Int, confirmedBaseDamage: Int, estimatedDataDamage: Int, confirmedDataDamage: Int, skillGauge: Double, connectionState: ConnectionState, processingState: ProcessingState) {
        self.bossId = bossId; self.bossSnapshotVersion = bossSnapshotVersion; self.maxHp = maxHp; self.remainingHp = remainingHp
        self.estimatedBaseDamage = estimatedBaseDamage; self.confirmedBaseDamage = confirmedBaseDamage; self.estimatedDataDamage = estimatedDataDamage; self.confirmedDataDamage = confirmedDataDamage
        self.skillGauge = skillGauge; self.connectionState = connectionState; self.processingState = processingState
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
