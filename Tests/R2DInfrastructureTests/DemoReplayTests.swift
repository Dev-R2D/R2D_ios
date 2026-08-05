import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func demoReplayStartPauseResumeAndStopControlEmission() async throws {
    let tracker = DemoRouteLocationTracker(configuration: .init(playbackSpeed: 5, updateIntervalSec: 0.1, injectOffRoute: true, loop: false))
    let counter = LockedReplayCounter()
    let unsubscribe = tracker.subscribe { _ in counter.increment() }
    try tracker.start(sessionId: "demo")
    try await Task.sleep(for: .milliseconds(80))
    #expect(counter.value > 0)
    tracker.pause(); let pausedCount = counter.value
    try await Task.sleep(for: .milliseconds(80))
    #expect(counter.value == pausedCount)
    tracker.resume(); try await Task.sleep(for: .milliseconds(80))
    #expect(counter.value > pausedCount)
    tracker.stop(); let stoppedCount = counter.value
    try await Task.sleep(for: .milliseconds(80))
    #expect(counter.value == stoppedCount)
    unsubscribe()
}

@Test func demoReplaySpeedSeekAndFixtureAreDeterministic() throws {
    let first = DemoRouteLocationTracker(configuration: .init(playbackSpeed: 1, updateIntervalSec: 100))
    let second = DemoRouteLocationTracker(configuration: .init(playbackSpeed: 1, updateIntervalSec: 100))
    try first.start(sessionId: "one"); try second.start(sessionId: "two")
    first.setPlaybackSpeed(3); second.setPlaybackSpeed(3)
    first.seek(to: .risk); second.seek(to: .risk)
    #expect(first.playbackSpeed == 3)
    #expect(first.snapshot.coordinate == second.snapshot.coordinate)
    first.restart(); second.restart()
    #expect(DemoNavigatorFixture.routes.count == 3)
    #expect(DemoNavigatorFixture.routes[1].id == "demo-safe")
    first.stop(); second.stop()
}

@Test func demoJSONResourcesAreReadableAndValid() throws {
    #expect(DemoResourceBundle.containsAllResourcesIncludingPackageFallback())
    for name in DemoResourceBundle.resourceNames {
        let data = try DemoResourceBundle.data(named: name)
        #expect((try JSONSerialization.jsonObject(with: data)) is [String: Any])
    }
}

@Test func demoFixtureInjectsOffRouteAndRepositoryReturnsReroute() async throws {
    let route = DemoNavigatorFixture.routes[1], engine = NavigationEngine()
    engine.setRoute(route)
    var detected = false
    for coordinate in DemoNavigatorFixture.replayCoordinates[132...137] { detected = engine.update(location: coordinate)?.isOffRoute == true || detected }
    #expect(detected)
    let repository = DemoRouteRepository()
    let refreshed = try await repository.refreshRoute(route, from: DemoNavigatorFixture.replayCoordinates[134])
    #expect(refreshed.id == "demo-safe-reroute")
    #expect(refreshed.polyline.last == DemoNavigatorFixture.destination)
}

private final class LockedReplayCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
