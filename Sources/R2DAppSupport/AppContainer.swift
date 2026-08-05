import Foundation
import R2DCore
import R2DInfrastructure
import R2DUI

public enum AppEnvironment: String, Sendable { case production, preview, test, demoReplay, demoNavigator }

@MainActor
public final class AppContainer {
    public let environment: AppEnvironment
    public let activeRideCoordinator: ActiveRideCoordinator
    public let viewModel: RideViewModel
    public let lifecycle: AppLifecycleController
    public let telemetryPipeline: TelemetryPipeline
    public let mapRenderer: IMapRenderer
    public let featureFlags: FeatureFlags
    public let demoReplayController: DemoReplayControlling?
    public let demoResourcesAvailable: Bool
    private let tokenProvider: TokenProvider
    public let locationAdapterName: String, sensorAdapterName: String, routeAdapterName: String
    public let mapRendererName: String
    public let telemetryPipelineName: String

    public init(environment: AppEnvironment, sessions: RideSessionRepository, location: LocationTracker, sensors: SensorCollector, routes: IRouteRepository, navigationEngine: NavigationEngine = .init(), mapRenderer: IMapRenderer, riskLayerWorker: IRiskLayerSyncWorker, appConfiguration: AppConfiguration = .init(), queue: TelemetryQueue, progress: IRideProgressRepository, telemetryPipeline: TelemetryPipeline? = nil, progressConfiguration: RideProgressSyncConfiguration = .init(), tokenProvider: TokenProvider = MockAuthProvider(), demoReplayController: DemoReplayControlling? = nil, demoResourcesAvailable: Bool = false) {
        self.environment = environment; self.mapRenderer = mapRenderer; locationAdapterName = String(describing: type(of: location)); sensorAdapterName = String(describing: type(of: sensors)); routeAdapterName = String(describing: type(of: routes)); mapRendererName = String(describing: type(of: mapRenderer))
        self.tokenProvider = tokenProvider; self.featureFlags = appConfiguration.features; self.demoReplayController = demoReplayController; self.demoResourcesAvailable = demoResourcesAvailable
        let pipeline = telemetryPipeline ?? TelemetryUploadWorker(queue: InMemorySecureTelemetryQueue(), uploader: MockTelemetryUploader())
        self.telemetryPipeline = pipeline
        telemetryPipelineName = String(describing: type(of: pipeline))
        activeRideCoordinator = ActiveRideCoordinator(sessions: sessions, location: location, sensors: sensors, routes: routes, navigationEngine: navigationEngine, mapRenderer: mapRenderer, riskLayerWorker: riskLayerWorker, roadWarningEngine: .init(configuration: appConfiguration.roadWarning), queue: queue, progress: progress, telemetryPipeline: pipeline, progressConfiguration: progressConfiguration)
        viewModel = RideViewModel(coordinator: activeRideCoordinator, mapRenderer: mapRenderer, featureFlags: appConfiguration.features, demoReplayController: demoReplayController); lifecycle = AppLifecycleController(coordinator: activeRideCoordinator, telemetryPipeline: pipeline)
    }
    public func authenticationState() async -> AuthenticationState { await tokenProvider.authenticationState() }
    public func logout() async { await tokenProvider.logout() }
    public static func production() -> AppContainer {
        #if os(iOS) && canImport(CoreLocation) && canImport(CoreMotion)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sessions: RideSessionRepository = (try? FileRideSessionRepository(fileURL: support.appendingPathComponent("R2D/active-ride.json"))) ?? MemoryRideSessionRepository()
        let secureQueue: SecureTelemetryQueue
        if let key = try? KeychainSecretKeyStore().loadOrCreateKey(), let queue = try? EncryptedPersistentTelemetryQueue(root: support.appendingPathComponent("R2D/Telemetry"), cipher: AESGCMTelemetryCipher(keyData: key)) { secureQueue = queue } else { secureQueue = InMemorySecureTelemetryQueue() }
        let uploader: TelemetryUploader
        let progress: IRideProgressRepository
        let routes: IRouteRepository
        let riskRepository: IRiskLayerRepository
        let tokenProvider: TokenProvider
        if let raw = Bundle.main.object(forInfoDictionaryKey: "R2DAPIBaseURL") as? String, let url = URL(string: raw), !raw.isEmpty {
            let transport = URLSessionTransport()
            let authAPI = AuthHTTPRemoteAPI(client: HTTPClient(baseURL: url, transport: transport))
            let authManager = AuthManager(tokenStore: KeychainSecureTokenStore(), remoteAPI: authAPI)
            tokenProvider = authManager
            let client = HTTPClient(baseURL: url, transport: transport, tokenProvider: authManager)
            uploader = TelemetryHTTPUploader(client: client); progress = RideProgressHTTPRepository(client: client); routes = HTTPRouteRepository(client: client); riskRepository = RiskLayerHTTPRepository(client: client)
        } else { tokenProvider = MockAuthProvider(accessToken: nil); uploader = QueueOnlyTelemetryUploader(); progress = MockProgressServer(); routes = UnavailableRouteRepository(); riskRepository = UnavailableRiskLayerRepository() }
        let pipeline = TelemetryUploadWorker(queue: secureQueue, uploader: uploader)
        let riskCache: IRiskLayerCache = (try? PersistentRiskLayerCache(root: support.appendingPathComponent("R2D/RiskLayer"))) ?? InMemoryRiskLayerCache()
        let appConfig = AppConfiguration(), riskWorker = RiskLayerSyncWorker(repository: riskRepository, cache: riskCache, configuration: appConfig.riskLayerSync)
        return .init(environment: .production, sessions: sessions, location: CoreLocationTracker(), sensors: CoreMotionSensorCollector(), routes: routes, mapRenderer: AppleMapKitRenderer(), riskLayerWorker: riskWorker, appConfiguration: appConfig, queue: MemoryTelemetryQueue(), progress: progress, telemetryPipeline: pipeline, tokenProvider: tokenProvider)
        #else
        return preview()
        #endif
    }
    public static func preview() -> AppContainer { let config = AppConfiguration(); return .init(environment: .preview, sessions: MemoryRideSessionRepository(), location: MockLocationTracker(), sensors: MockSensorCollector(), routes: MockRouteRepository(), mapRenderer: MockMapRenderer(), riskLayerWorker: RiskLayerSyncWorker(repository: MockRiskLayerRepository(), cache: InMemoryRiskLayerCache(), configuration: config.riskLayerSync), appConfiguration: config, queue: MemoryTelemetryQueue(), progress: MockProgressServer()) }
    public static func testing(sessions: RideSessionRepository = MemoryRideSessionRepository(), location: LocationTracker = MockLocationTracker(), sensors: SensorCollector = MockSensorCollector(), routes: IRouteRepository = MockRouteRepository(), navigationEngine: NavigationEngine = .init(), mapRenderer: IMapRenderer = MockMapRenderer(), riskLayerWorker: IRiskLayerSyncWorker = RiskLayerSyncWorker(repository: MockRiskLayerRepository(), cache: InMemoryRiskLayerCache()), appConfiguration: AppConfiguration = .init(), queue: TelemetryQueue = MemoryTelemetryQueue(), progress: IRideProgressRepository = MockProgressServer(), telemetryPipeline: TelemetryPipeline? = nil, progressConfiguration: RideProgressSyncConfiguration = .init()) -> AppContainer { .init(environment: .test, sessions: sessions, location: location, sensors: sensors, routes: routes, navigationEngine: navigationEngine, mapRenderer: mapRenderer, riskLayerWorker: riskLayerWorker, appConfiguration: appConfiguration, queue: queue, progress: progress, telemetryPipeline: telemetryPipeline, progressConfiguration: progressConfiguration) }
    public static func demoReplay() -> AppContainer {
        demoNavigator(environment: .demoReplay)
    }
    public static func demoNavigator(environment: AppEnvironment = .demoNavigator) -> AppContainer {
        let resourcesAvailable = DemoResourceBundle.containsAllResourcesIncludingPackageFallback()
        if Bundle.main.bundleURL.pathExtension == "app" { precondition(DemoResourceBundle.mainBundleContainsAllResources(), "R2D Navigator Demo resources are missing from Bundle.main") }
        let config = AppConfiguration(roadWarning: .init(maximumWarningDistanceM: 100, cooldownSec: 300), features: .navigatorDemo)
        let location = DemoRouteLocationTracker(), progress = MockProgressServer()
        progress.rideProgress = .init(validDistance: 240, confirmedDistance: 220, processingChunks: 1, acknowledgedChunks: 4, remainingChunks: 1)
        progress.bossProgress = .init(bossHP: 92, confirmedDamage: 8, pendingDamage: 3, processingState: .processing)
        progress.rewardProgress = .init(pendingReward: 0, confirmedReward: 0); progress.riskLayerVersion = DemoNavigatorFixture.riskSnapshot.layerVersion
        let risk = RiskLayerSyncWorker(repository: MockRiskLayerRepository(snapshot: DemoNavigatorFixture.riskSnapshot), cache: InMemoryRiskLayerCache(), configuration: config.riskLayerSync)
        return .init(environment: environment, sessions: MemoryRideSessionRepository(), location: location, sensors: MockSensorCollector(), routes: DemoRouteRepository(), mapRenderer: AppleMapKitRenderer(), riskLayerWorker: risk, appConfiguration: config, queue: MemoryTelemetryQueue(), progress: progress, tokenProvider: MockAuthProvider(), demoReplayController: location, demoResourcesAvailable: resourcesAvailable)
    }
}
