import SwiftUI
import R2DAppSupport
import R2DUI

@main
struct R2DApp: App {
    @State private var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    init() {
        let isDemo = ProcessInfo.processInfo.environment["R2D_ENVIRONMENT"] == "demoNavigator"
        _container = State(initialValue: isDemo ? AppContainer.demoNavigator() : AppContainer.production())
    }
    var body: some Scene {
        WindowGroup { R2DAppView(model: container.viewModel).task { container.lifecycle.bootstrap() } }
            .onChange(of: scenePhase) { _, phase in
                let state: AppLifecycleState = switch phase { case .active: .active; case .inactive: .inactive; case .background: .background; @unknown default: .inactive }
                container.lifecycle.transition(to: state)
            }
    }
}
