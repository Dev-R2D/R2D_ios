import R2DCore

public enum AppLifecycleState: Sendable { case active, inactive, background }

@MainActor
public final class AppLifecycleController {
    private let coordinator: ActiveRideCoordinator
    private let telemetryPipeline: TelemetryPipeline
    private var didBootstrap = false
    public init(coordinator: ActiveRideCoordinator, telemetryPipeline: TelemetryPipeline) { self.coordinator = coordinator; self.telemetryPipeline = telemetryPipeline }
    public func bootstrap() { guard !didBootstrap else { return }; didBootstrap = true; _ = try? coordinator.restore(); coordinator.refreshReadiness(); Task { await telemetryPipeline.start(); await coordinator.refreshTelemetrySummary() } }
    public func transition(to state: AppLifecycleState) {
        switch state {
        case .active: _ = try? coordinator.restore(); coordinator.refreshReadiness(); Task { await telemetryPipeline.triggerUpload(); await coordinator.applicationDidBecomeActive(); await coordinator.refreshTelemetrySummary() }
        case .background: try? coordinator.persistSnapshot(); Task { await telemetryPipeline.flush(sessionID: coordinator.getSnapshot().session?.id); await coordinator.refreshTelemetrySummary() }
        case .inactive: break
        }
    }
}
