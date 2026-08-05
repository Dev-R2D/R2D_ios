import Foundation
import R2DCore

public struct DemoReplayConfiguration: Sendable {
    public let playbackSpeed: Double, updateIntervalSec: TimeInterval
    public let injectOffRoute: Bool, injectGPSJump: Bool, loop: Bool
    public init(playbackSpeed: Double = 3, updateIntervalSec: TimeInterval = 1, injectOffRoute: Bool = true, injectGPSJump: Bool = false, loop: Bool = false) {
        self.playbackSpeed = playbackSpeed; self.updateIntervalSec = updateIntervalSec; self.injectOffRoute = injectOffRoute; self.injectGPSJump = injectGPSJump; self.loop = loop
    }
}

public enum DemoNavigatorFixture {
    public static let origin = Coordinate(latitude: 37.5452, longitude: 127.0392)
    public static let destination = Coordinate(latitude: 37.5534, longitude: 127.0488)
    public static let safePolyline: [Coordinate] = [
        origin, .init(latitude: 37.5462, longitude: 127.0400), .init(latitude: 37.5474, longitude: 127.0410), .init(latitude: 37.5483, longitude: 127.0424), .init(latitude: 37.5495, longitude: 127.0434), .init(latitude: 37.5504, longitude: 127.0447), .init(latitude: 37.5514, longitude: 127.0460), .init(latitude: 37.5524, longitude: 127.0471), destination
    ]
    public static let routes: [Route] = [
        makeRoute(id: "demo-fast", polyline: [origin, .init(latitude: 37.5487, longitude: 127.0437), destination], duration: 150, title: "빠른 경로"),
        makeRoute(id: "demo-safe", polyline: safePolyline, duration: 180, title: "안전 경로"),
        makeRoute(id: "demo-bike", polyline: [origin, .init(latitude: 37.5460, longitude: 127.0420), .init(latitude: 37.5490, longitude: 127.0465), destination], duration: 210, title: "자전거 우선")
    ]
    public static let riskSnapshot: RiskLayerSnapshot = {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        func cell(_ id: String, _ coordinate: Coordinate, _ data: DataState, _ risk: RiskState, _ score: Int, _ confidence: Double) -> RoadCell { .init(id: id, geometry: .point(coordinate), dataState: data, riskState: risk, riskScore: score, confidence: confidence, lastObservedAt: now, validUntil: now.addingTimeInterval(86_400 * 30), observationCount: 3, independentDeviceCount: 2, cellVersion: "demo-v1", layerVersion: "demo-navigator-v1") }
        return .init(layerVersion: "demo-navigator-v1", generatedAt: now, expiresAt: now.addingTimeInterval(86_400 * 30), cells: [
            cell("demo-unknown", safePolyline[2], .unknown, .normal, 0, 0),
            cell("demo-stale", safePolyline[3], .stale, .normal, 0, 0.5),
            cell("demo-rough", safePolyline[4], .verified, .rough, 45, 0.9),
            cell("demo-review", safePolyline[5], .review, .suspectedDamage, 65, 0.8),
            cell("demo-confirmed", safePolyline[6], .verified, .confirmedDamage, 92, 0.98)
        ], isSimulated: true)
    }()
    public static let replayCoordinates: [Coordinate] = {
        var result: [Coordinate] = []
        for index in 0..<(safePolyline.count - 1) {
            let a = safePolyline[index], b = safePolyline[index + 1]
            for step in 0..<36 { let ratio = Double(step) / 36; result.append(.init(latitude: a.latitude + (b.latitude - a.latitude) * ratio, longitude: a.longitude + (b.longitude - a.longitude) * ratio)) }
        }
        result.append(destination)
        for index in 132...137 { result[index] = .init(latitude: result[index].latitude + 0.00055, longitude: result[index].longitude - 0.00045) }
        return result
    }()
    private static func makeRoute(id: String, polyline: [Coordinate], duration: TimeInterval, title: String) -> Route {
        let distance = zip(polyline, polyline.dropFirst()).reduce(0) { $0 + demoDistance($1.0, $1.1) }
        let turns = polyline.dropFirst().enumerated().compactMap { index, coordinate in index.isMultiple(of: max(1, polyline.count / 4)) || index == polyline.count - 2 ? Turn(coordinate: coordinate, instruction: index == polyline.count - 2 ? "목적지에 도착합니다" : "(title) · 경로를 따라 진행", distance: distance / Double(max(1, polyline.count - 1))) : nil }
        return .init(id: id, polyline: polyline, totalDistance: distance, totalDuration: duration, turnList: turns, riskCells: [])
    }
}

public actor DemoRouteRepository: IRouteRepository {
    public init() {}
    public func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] { DemoNavigatorFixture.routes }
    public func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route {
        let destination = route.polyline.last ?? DemoNavigatorFixture.destination
        let middle = Coordinate(latitude: (currentLocation.latitude + destination.latitude) / 2, longitude: (currentLocation.longitude + destination.longitude) / 2)
        let distance = demoDistance(currentLocation, middle) + demoDistance(middle, destination)
        return .init(id: "demo-safe-reroute", polyline: [currentLocation, middle, destination], totalDistance: distance, totalDuration: distance / 5, turnList: [.init(coordinate: middle, instruction: "복귀 경로로 우회전", distance: distance / 2), .init(coordinate: destination, instruction: "목적지에 도착합니다", distance: distance / 2)], riskCells: [])
    }
    public func cancelSearch() async {}
}

public final class DemoRouteLocationTracker: LocationTracker, DemoReplayControlling, @unchecked Sendable {
    private let lock = NSLock(), configuration: DemoReplayConfiguration, coordinates: [Coordinate]
    private var listeners: [UUID: @Sendable (LocationSnapshot) -> Void] = [:], timer: DispatchSourceTimer?, index = 0, paused = false, currentSnapshot: LocationSnapshot = .empty, running = false
    private var speed: Double
    public var snapshot: LocationSnapshot { lock.withLock { currentSnapshot } }
    public var isRunning: Bool { lock.withLock { running } }
    public var playbackSpeed: Double { lock.withLock { speed } }
    public init(coordinates: [Coordinate] = DemoNavigatorFixture.replayCoordinates, configuration: DemoReplayConfiguration = .init()) { self.coordinates = coordinates; self.configuration = configuration; speed = configuration.playbackSpeed }
    public func start(sessionId: String) throws { lock.withLock { running = true; paused = false }; schedule() }
    public func stop() { lock.withLock { running = false; timer?.cancel(); timer = nil } }
    public func pause() { lock.withLock { paused = true } }
    public func resume() { lock.withLock { paused = false }; schedule() }
    public func restart() { lock.withLock { index = 0; currentSnapshot = .empty; paused = false }; schedule() }
    public func setPlaybackSpeed(_ speed: Double) { lock.withLock { self.speed = max(1, min(5, speed)) }; schedule() }
    public func seek(to target: DemoReplayTarget) {
        let targetIndex = switch target { case .start: 0; case .risk: min(205, coordinates.count - 1); case .reroute: min(130, coordinates.count - 1); case .destination: max(0, coordinates.count - 8) }
        let startIndex = lock.withLock { () -> Int in timer?.cancel(); timer = nil; return min(index, coordinates.count - 1) }
        if startIndex <= targetIndex {
            for value in startIndex...targetIndex { emit(at: value) }
            lock.withLock { index = min(targetIndex + 1, coordinates.count) }
        } else {
            for value in stride(from: startIndex, through: targetIndex, by: -1) { emit(at: value) }
            lock.withLock { index = min(targetIndex + 1, coordinates.count) }
        }
        schedule()
    }
    public func subscribe(_ listener: @escaping @Sendable (LocationSnapshot) -> Void) -> Unsubscribe { let id = UUID(); lock.withLock { listeners[id] = listener }; return { [weak self] in self?.lock.withLock { self?.listeners[id] = nil } } }
    public func readiness() -> LocationReadiness { .init(servicesEnabled: true, authorization: .authorizedWhenInUse, isAccuracySufficient: true) }
    public func requestAuthorization() {}
    private func schedule() {
        lock.withLock {
            timer?.cancel(); timer = nil
            guard running, !paused else { return }
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated)); self.timer = timer
            let interval = configuration.updateIntervalSec / speed
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler { [weak self] in self?.emitNext() }; timer.resume()
        }
    }
    private func emitNext() {
        let output: (LocationSnapshot, [@Sendable (LocationSnapshot) -> Void])? = lock.withLock {
            guard running, !paused, !coordinates.isEmpty else { return nil }
            if index >= coordinates.count { if configuration.loop { index = 0 } else { timer?.cancel(); timer = nil; return nil } }
            let current = coordinates[index], next = coordinates[min(index + 1, coordinates.count - 1)]
            let heading = demoBearing(current, next), value = LocationSnapshot(coordinate: current, speedMps: 5, heading: heading, mapMatchConfidence: 0.96)
            currentSnapshot = value; index += 1; return (value, Array(listeners.values))
        }
        output?.1.forEach { $0(output!.0) }
    }
    private func emit(at value: Int) {
        let output: (LocationSnapshot, [@Sendable (LocationSnapshot) -> Void])? = lock.withLock {
            guard running, !paused, coordinates.indices.contains(value) else { return nil }
            let current = coordinates[value], next = coordinates[min(value + 1, coordinates.count - 1)]
            let snapshot = LocationSnapshot(coordinate: current, speedMps: 5, heading: demoBearing(current, next), mapMatchConfidence: 0.96)
            currentSnapshot = snapshot; return (snapshot, Array(listeners.values))
        }
        output?.1.forEach { $0(output!.0) }
    }
}

private func demoDistance(_ a: Coordinate, _ b: Coordinate) -> Double { let dy = (b.latitude-a.latitude)*111_320, dx = (b.longitude-a.longitude)*111_320*cos(a.latitude * .pi/180); return sqrt(dx*dx+dy*dy) }
private func demoBearing(_ a: Coordinate, _ b: Coordinate) -> Double {
    let delta = (b.longitude - a.longitude) * .pi / 180
    let latitudeA = a.latitude * .pi / 180, latitudeB = b.latitude * .pi / 180
    let y = sin(delta) * cos(latitudeB)
    let x = cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}
