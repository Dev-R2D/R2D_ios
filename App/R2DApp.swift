import R2DAppSupport
import R2DUIKit
import UIKit
#if canImport(GoogleMaps)
import GoogleMaps
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private(set) var container: AppContainer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NSLog("R2D AppDelegate didFinishLaunching")
        configureGoogleMapsIfNeeded()
        ensureContainer().lifecycle.bootstrap()
        return true
    }

    @discardableResult
    func ensureContainer() -> AppContainer {
        if let container {
            return container
        }

        let isDemo = ProcessInfo.processInfo.environment["R2D_ENVIRONMENT"] == "demoNavigator"
        let container = isDemo ? AppContainer.demoNavigator() : AppContainer.production()
        NSLog(
            "R2D container env=%@ route=%@ place=%@ mapMatch=%@",
            container.environment.rawValue,
            container.routeAdapterName,
            container.placeSearchAdapterName,
            container.mapMatchingAdapterName
        )
        self.container = container
        return container
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    private func configureGoogleMapsIfNeeded() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "R2DGoogleMapsAPIKey") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            NSLog("R2D Google Maps API key missing")
            return
        }
        #if canImport(GoogleMaps)
        GMSServices.provideAPIKey(key)
        NSLog("R2D Google Maps configured")
        #else
        NSLog("R2D Google Maps SDK not linked yet")
        #endif
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        NSLog("R2D SceneDelegate willConnectTo")
        guard let windowScene = scene as? UIWindowScene else {
            NSLog("R2D SceneDelegate missing UIWindowScene")
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.backgroundColor = .systemBackground
        window.rootViewController = BootstrapViewController()
        window.makeKeyAndVisible()
        self.window = window

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            NSLog("R2D SceneDelegate missing AppDelegate")
            return
        }

        let container = appDelegate.ensureContainer()
        window.rootViewController = R2DRootViewController(model: container.viewModel)
        NSLog("R2D root view controller installed")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        transitionLifecycle(to: .active)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        transitionLifecycle(to: .inactive)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        transitionLifecycle(to: .background)
    }

    private func transitionLifecycle(to state: AppLifecycleState) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.container?.lifecycle.transition(to: state)
    }
}

private final class BootstrapViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.035, green: 0.07, blue: 0.09, alpha: 1)

        let label = UILabel()
        label.text = "R2D loading..."
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
