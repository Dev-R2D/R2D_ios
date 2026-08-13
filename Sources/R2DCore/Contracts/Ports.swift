import Foundation

public typealias Unsubscribe = @Sendable () -> Void

public protocol RideSessionRepository: AnyObject {
    func create(routeId: String, boss: BossContext?) throws -> RideSession
    func active() -> RideSession?
    func save(_ session: RideSession) throws
}
public protocol LocationTracker: AnyObject {
    var snapshot: LocationSnapshot { get }
    var isRunning: Bool { get }
    func start(sessionId: String) throws
    func stop()
    func pause(); func resume()
    func subscribe(_ listener: @escaping @Sendable (LocationSnapshot) -> Void) -> Unsubscribe
    func readiness() -> LocationReadiness
    func requestAuthorization()
}
public protocol SensorCollector: AnyObject {
    var isRunning: Bool { get }
    func start(sessionId: String, profileId: String) throws
    func stop(); func pause(); func resume()
    func subscribe(_ listener: @escaping @Sendable (SensorChunk) -> Void) -> Unsubscribe
    func readiness() -> SensorReadiness
}
public protocol SensorLogImporting: Sendable {
    func importRecording(from urls: [URL]) async throws -> SensorLogImportResult
}
public protocol IRouteRepository: Sendable {
    func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route]
    func searchRoute(origin: Coordinate, destination: Coordinate, option: String?) async throws -> [Route]
    func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route
    func cancelSearch() async
}
public extension IRouteRepository {
    func searchRoute(origin: Coordinate, destination: Coordinate, option: String?) async throws -> [Route] {
        try await searchRoute(origin: origin, destination: destination)
    }
}
public enum RouteRepositoryError: Error, Equatable, Sendable { case unavailable, cancelled, invalidRoute }
public protocol IPlaceSearchRepository: Sendable {
    func geocode(_ query: String, near coordinate: Coordinate?) async throws -> [PlaceSearchResult]
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceSearchResult?
}
public protocol IMapMatchingRepository: Sendable {
    func match(_ coordinate: Coordinate, heading: Double?, speedMps: Double?) async throws -> MatchedRoadPoint
    func matchTrace(_ coordinates: [Coordinate]) async throws -> [MatchedRoadPoint]
}
public protocol IRouteOptimizationRepository: Sendable {
    func optimize(_ request: RouteOptimizationRequest) async throws -> RouteOptimizationResult
}
public enum IMPSRepositoryError: Error, Equatable, Sendable { case unavailable, emptyQuery, noResult, capacityExceeded, invalidResponse }
public protocol IRiskLayerRepository: Sendable {
    func fetchCells(boundingBox: GeoBoundingBox, zoomLevel: Int?, knownLayerVersion: String?) async throws -> RiskLayerSnapshot
    func fetchCells(along route: Route, corridorWidthM: Double, knownLayerVersion: String?) async throws -> RiskLayerSnapshot
    func fetchCell(id: String) async throws -> RoadCell
}
public enum RiskLayerCacheContext: String, Codable, Hashable, Sendable { case route, viewport }
public protocol IRiskLayerCache: Sendable {
    func load(_ context: RiskLayerCacheContext) async throws -> RiskLayerSnapshot?
    func save(_ snapshot: RiskLayerSnapshot, context: RiskLayerCacheContext) async throws
}
public protocol IRiskLayerSyncWorker: Sendable {
    func start() async
    func stop() async
    func syncViewport(_ boundingBox: GeoBoundingBox, zoomLevel: Int?) async
    func syncRoute(_ route: Route) async
    func syncIfVersionChanged(_ layerVersion: String?) async
    func refreshIfStale() async
    func cachedSnapshot() async -> RiskLayerSnapshot?
    func updates() async -> AsyncStream<RiskLayerSnapshot>
    func clearRouteContext() async
}
public enum RiskLayerError: Error, Sendable, Equatable { case offline, timeout, unauthorized, forbidden, rateLimited(retryAfter: TimeInterval?), invalidGeometry, invalidResponse, serverFailure(statusCode: Int), versionConflict, cacheUnavailable }
@MainActor public protocol IRoadWarningOutput: AnyObject { func emit(_ warning: RoadWarning) }
@MainActor public final class NoopRoadWarningOutput: IRoadWarningOutput { public init() {}; public func emit(_ warning: RoadWarning) {} }
public protocol TelemetryQueue: AnyObject {
    func enqueue(_ chunk: SensorChunk) throws
    func pending(sessionId: String) -> [SensorChunk]
    func acknowledge(sessionId: String, through sequence: Int) throws
}
public protocol IRideProgressRepository: Sendable {
    func fetchRideProgress(rideId: String) async throws -> RideProgress
    func fetchBossProgress(rideId: String) async throws -> BossProgress?
    func fetchRewardProgress(rideId: String) async throws -> RewardProgress
    func fetchRiskLayerVersion(rideId: String) async throws -> String?
}
public protocol Clock: Sendable { func now() -> Date }
public protocol IdGenerator: Sendable { func next() -> String }

public struct SystemClock: Clock { public init() {}; public func now() -> Date { Date() } }
public struct UUIDGenerator: IdGenerator { public init() {}; public func next() -> String { UUID().uuidString } }

public enum RideError: Error, Equatable { case activeSessionExists, invalidTransition(RideSessionState, RideSessionState), noActiveRide, completedSession, routeNotSelected }
public enum LocationTrackingError: Error, Equatable, Sendable { case serviceUnavailable, authorizationDenied, authorizationRestricted, insufficientAccuracy, alreadyRunning, startFailed }
public enum SensorCollectionError: Error, Equatable, Sendable { case accelerometerUnavailable, gyroscopeUnavailable, motionUnavailable, alreadyRunning, startFailed }

public protocol TelemetryCipher: Sendable { func encrypt(_ data: Data) throws -> Data; func decrypt(_ data: Data) throws -> Data }
public protocol SecretKeyStore: Sendable { func loadOrCreateKey() throws -> Data }
public protocol SecureTelemetryQueue: Sendable {
    func enqueue(chunk: SensorChunk, idempotencyKey: String) async throws
    func nextUploadBatch(limit: Int, now: Date, sessionID: String?) async throws -> [TelemetryQueueItem]
    func loadPayload(itemID: UUID) async throws -> Data
    func markUploading(itemIDs: [UUID], attemptedAt: Date) async throws
    func acknowledge(itemID: UUID, acknowledgedAt: Date) async throws
    func markRetry(itemID: UUID, errorCode: String, nextRetryAt: Date) async throws
    func markFailed(itemID: UUID, errorCode: String) async throws
    func quarantine(itemID: UUID, reason: String) async throws
    func restoreInterruptedUploads() async throws
    func repairIntegrity() async throws -> TelemetryIntegrityReport
    func summary() async throws -> TelemetryQueueSummary
}
public protocol TelemetryUploader: Sendable { func upload(item: TelemetryQueueItem, payload: Data) async throws -> TelemetryUploadAcknowledgement }
public protocol RetryPolicy: Sendable { func nextRetryDate(retryCount: Int, error: TelemetryUploadError, now: Date) -> Date? }
public protocol TelemetryPipeline: Sendable {
    func start() async
    func stop() async
    func enqueue(_ chunk: SensorChunk) async
    func triggerUpload() async
    func flush(sessionID: String?) async
    func summary() async -> TelemetryQueueSummary
    func setUploadAcknowledgementHandler(_ handler: (@Sendable (TelemetryUploadAcknowledgement) async -> Void)?) async
}
public extension TelemetryPipeline { func setUploadAcknowledgementHandler(_ handler: (@Sendable (TelemetryUploadAcknowledgement) async -> Void)?) async {} }
public enum TelemetryQueueError: Error, Equatable, Sendable { case storageFull, payloadMissing, integrityFailure, encryptionFailure }
