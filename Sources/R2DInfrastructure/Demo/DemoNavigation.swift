import Foundation
import R2DCore

public struct DemoReplayConfiguration: Sendable {
    public let playbackSpeed: Double, updateIntervalSec: TimeInterval
    public let injectOffRoute: Bool, injectGPSJump: Bool, loop: Bool
    public init(playbackSpeed: Double = 1.0, updateIntervalSec: TimeInterval = 1.0, injectOffRoute: Bool = false, injectGPSJump: Bool = false, loop: Bool = false) {
        self.playbackSpeed = playbackSpeed; self.updateIntervalSec = updateIntervalSec; self.injectOffRoute = injectOffRoute; self.injectGPSJump = injectGPSJump; self.loop = loop
    }
}

public enum DemoNavigatorFixture {
    static let sensorSamples = SensorLoggerDemoRoute.loadSamples()
    public static let sensorRoute = SensorLoggerDemoRoute.load()
    public static let sourceRoad = try? HwaseongBikeRoadCatalog.loadBundled().preferredDemoRoad
    public static let origin = sensorRoute?.polyline.first ?? sourceRoad?.start ?? Coordinate(latitude: 37.2358981701, longitude: 127.035530669)
    public static let destination = sensorRoute?.polyline.last ?? sourceRoad?.end ?? Coordinate(latitude: 37.2188446551, longitude: 127.0564212205)
    public static let dongtanWoncheonPolyline: [Coordinate] = (0...8).map { step in
        let ratio = Double(step) / 8
        let start = Coordinate(latitude: 37.235898, longitude: 127.035530)
        let end = Coordinate(latitude: 37.218844, longitude: 127.056421)
        let curve = sin(ratio * .pi) * 0.0018
        return .init(latitude: start.latitude + (end.latitude - start.latitude) * ratio + curve, longitude: start.longitude + (end.longitude - start.longitude) * ratio - curve)
    }

    public static let byeongjeomJungangPolyline: [Coordinate] = (0...6).map { step in
        let ratio = Double(step) / 6
        let start = Coordinate(latitude: 37.219265, longitude: 127.038338)
        let end = Coordinate(latitude: 37.203703, longitude: 127.036575)
        let curve = -sin(ratio * .pi) * 0.0025
        return .init(latitude: start.latitude + (end.latitude - start.latitude) * ratio, longitude: start.longitude + (end.longitude - start.longitude) * ratio + curve)
    }

    public static let osancheonPolyline: [Coordinate] = (0...7).map { step in
        let ratio = Double(step) / 7
        let start = Coordinate(latitude: 37.228500, longitude: 127.072200)
        let end = Coordinate(latitude: 37.198200, longitude: 127.071100)
        let curve = sin(ratio * .pi * 1.5) * 0.0035
        return .init(latitude: start.latitude + (end.latitude - start.latitude) * ratio + curve, longitude: start.longitude + (end.longitude - start.longitude) * ratio + curve)
    }

    public static let safePolyline: [Coordinate] = sensorSamples.count >= 2 ? sensorSamples.map(\.coordinate) : (sensorRoute?.polyline ?? dongtanWoncheonPolyline)

    public static let routes: [Route] = [
        makeRoute(id: "demo-safe", polyline: dongtanWoncheonPolyline, duration: 540, title: "동탄원천로"),
        makeRoute(id: "demo-fast", polyline: byeongjeomJungangPolyline, duration: 380, title: "병점중앙로"),
        makeRoute(id: "demo-bike", polyline: osancheonPolyline, duration: 620, title: "오산천 수변길")
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
        if sensorSamples.count >= 2 {
            return sensorSamples.map(\.coordinate)
        }
        var result: [Coordinate] = []
        for index in 0..<(safePolyline.count - 1) {
            let a = safePolyline[index], b = safePolyline[index + 1]
            for step in 0..<50 { let ratio = Double(step) / 50; result.append(.init(latitude: a.latitude + (b.latitude - a.latitude) * ratio, longitude: a.longitude + (b.longitude - a.longitude) * ratio)) }
        }
        result.append(safePolyline.last ?? destination)
        return result
    }()
    public static let replaySpeedsMps: [Double] = {
        if sensorSamples.count >= 2 {
            return sensorSamples.map(\.speedMps)
        }
        return Array(repeating: 5, count: replayCoordinates.count)
    }()
    private static func makeRoute(id: String, polyline: [Coordinate], duration: TimeInterval, title: String) -> Route {
        let distance = zip(polyline, polyline.dropFirst()).reduce(0) { $0 + demoDistance($1.0, $1.1) }
        let turns = polyline.dropFirst().enumerated().compactMap { index, coordinate in index.isMultiple(of: max(1, polyline.count / 4)) || index == polyline.count - 2 ? Turn(coordinate: coordinate, instruction: index == polyline.count - 2 ? "목적지에 도착합니다" : "(title) · 경로를 따라 진행", distance: distance / Double(max(1, polyline.count - 1))) : nil }
        return .init(id: id, polyline: polyline, totalDistance: distance, totalDuration: duration, turnList: turns, riskCells: [])
    }
}

public actor DemoRouteRepository: IRouteRepository {
    public init() {}
    public func searchRoute(origin: Coordinate, destination: Coordinate) async throws -> [Route] {
        if let sensorRoute = DemoNavigatorFixture.sensorRoute, isNearSensorRoute(origin, destination, route: sensorRoute) {
            return [sensorRoute] + DemoNavigatorFixture.routes.map { route in
                route.withRiskCells(sensorRoute.riskCells)
            }
        }
        return DemoNavigatorFixture.routes
    }
    public func refreshRoute(_ route: Route, from currentLocation: Coordinate) async throws -> Route {
        let destination = route.polyline.last ?? DemoNavigatorFixture.destination
        let middle = Coordinate(latitude: (currentLocation.latitude + destination.latitude) / 2, longitude: (currentLocation.longitude + destination.longitude) / 2)
        let distance = demoDistance(currentLocation, middle) + demoDistance(middle, destination)
        return .init(id: "demo-safe-reroute", polyline: [currentLocation, middle, destination], totalDistance: distance, totalDuration: distance / 5, turnList: [.init(coordinate: middle, instruction: "복귀 경로로 우회전", distance: distance / 2), .init(coordinate: destination, instruction: "목적지에 도착합니다", distance: distance / 2)], riskCells: [])
    }
    public func cancelSearch() async {}
}

private extension Route {
    func withRiskCells(_ cells: [RiskCell]) -> Route {
        Route(
            id: id,
            polyline: polyline,
            totalDistance: totalDistance,
            totalDuration: totalDuration,
            providerOption: providerOption,
            tollFee: tollFee,
            taxiFare: taxiFare,
            totalTaxiFare: totalTaxiFare,
            isHighWay: isHighWay,
            remainingDistance: remainingDistance,
            remainingDuration: remainingDuration,
            turnList: turnList,
            riskCells: cells,
            status: status
        )
    }
}

public final class DemoRouteLocationTracker: LocationTracker, DemoReplayControlling, @unchecked Sendable {
    private let lock = NSLock(), configuration: DemoReplayConfiguration, coordinates: [Coordinate], speedsMps: [Double]
    private var listeners: [UUID: @Sendable (LocationSnapshot) -> Void] = [:], timer: DispatchSourceTimer?, index = 0, paused = false, currentSnapshot: LocationSnapshot = .empty, running = false
    private var speed: Double
    public var snapshot: LocationSnapshot { lock.withLock { currentSnapshot } }
    public var isRunning: Bool { lock.withLock { running } }
    public var playbackSpeed: Double { lock.withLock { speed } }
    public init(
        coordinates: [Coordinate] = DemoNavigatorFixture.replayCoordinates,
        speedsMps: [Double] = DemoNavigatorFixture.replaySpeedsMps,
        configuration: DemoReplayConfiguration = .init()
    ) {
        self.coordinates = coordinates
        self.speedsMps = speedsMps
        self.configuration = configuration
        speed = configuration.playbackSpeed
    }
    public func start(sessionId: String) throws {
        lock.withLock { running = true; paused = false }
        emit(at: lock.withLock { index })
        schedule()
    }
    public func stop() { lock.withLock { running = false; timer?.cancel(); timer = nil } }
    public func pause() { lock.withLock { paused = true } }
    public func resume() { lock.withLock { paused = false }; schedule() }
    public func restart() { lock.withLock { index = 0; currentSnapshot = .empty; paused = false }; schedule() }
    public func setPlaybackSpeed(_ speed: Double) { lock.withLock { self.speed = max(0.25, min(3, speed)) }; schedule() }
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
        if target == .reroute {
            emitOffRouteSample(near: targetIndex)
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
            let heading = demoBearing(current, next), value = LocationSnapshot(coordinate: current, speedMps: speedMps(at: index), heading: heading, mapMatchConfidence: 0.96)
            currentSnapshot = value; index += 1; return (value, Array(listeners.values))
        }
        output?.1.forEach { $0(output!.0) }
    }
    private func emit(at value: Int) {
        let output: (LocationSnapshot, [@Sendable (LocationSnapshot) -> Void])? = lock.withLock {
            guard running, !paused, coordinates.indices.contains(value) else { return nil }
            let current = coordinates[value], next = coordinates[min(value + 1, coordinates.count - 1)]
            let snapshot = LocationSnapshot(coordinate: current, speedMps: speedMps(at: value), heading: demoBearing(current, next), mapMatchConfidence: 0.96)
            currentSnapshot = snapshot; return (snapshot, Array(listeners.values))
        }
        output?.1.forEach { $0(output!.0) }
    }

    private func emitOffRouteSample(near value: Int) {
        emitOffRouteSample(near: value, offset: 0.00065)
        emitOffRouteSample(near: value, offset: 0.00068)
    }

    private func emitOffRouteSample(near value: Int, offset: Double) {
        let output: (LocationSnapshot, [@Sendable (LocationSnapshot) -> Void])? = lock.withLock {
            guard running, !paused, coordinates.indices.contains(value) else { return nil }
            let base = coordinates[value]
            let offRoute = Coordinate(latitude: base.latitude + offset, longitude: base.longitude + offset)
            let snapshot = LocationSnapshot(coordinate: offRoute, speedMps: speedMps(at: value), heading: 45, mapMatchConfidence: 0.30)
            currentSnapshot = snapshot
            index = min(value + 1, coordinates.count)
            return (snapshot, Array(listeners.values))
        }
        output?.1.forEach { $0(output!.0) }
    }

    private func speedMps(at index: Int) -> Double {
        guard !speedsMps.isEmpty else { return 0 }
        return speedsMps[max(0, min(index, speedsMps.count - 1))]
    }
}

private func isNearSensorRoute(_ origin: Coordinate, _ destination: Coordinate, route: Route) -> Bool {
    guard let first = route.polyline.first, let last = route.polyline.last else { return false }
    return demoDistance(origin, first) <= 80 && demoDistance(destination, last) <= 80
}

private func demoDistance(_ a: Coordinate, _ b: Coordinate) -> Double { let dy = (b.latitude-a.latitude)*111_320, dx = (b.longitude-a.longitude)*111_320*cos(a.latitude * .pi/180); return sqrt(dx*dx+dy*dy) }
private func demoBearing(_ a: Coordinate, _ b: Coordinate) -> Double {
    let delta = (b.longitude - a.longitude) * .pi / 180
    let latitudeA = a.latitude * .pi / 180, latitudeB = b.latitude * .pi / 180
    let y = sin(delta) * cos(latitudeB)
    let x = cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}
