import Foundation

public struct NavigationEngineConfiguration: Sendable {
    public let matchingToleranceM: Double, offRouteDistanceM: Double, maximumGPSJumpM: Double, offRouteConfirmations: Int
    public init(matchingToleranceM: Double = 35, offRouteDistanceM: Double = 60, maximumGPSJumpM: Double = 150, offRouteConfirmations: Int = 2) {
        self.matchingToleranceM = matchingToleranceM; self.offRouteDistanceM = offRouteDistanceM; self.maximumGPSJumpM = maximumGPSJumpM; self.offRouteConfirmations = offRouteConfirmations
    }
}

public final class NavigationEngine: @unchecked Sendable {
    private let lock = NSLock(), configuration: NavigationEngineConfiguration
    private var route: Route?, lastAcceptedCoordinate: Coordinate?, offRouteSamples = 0
    public init(configuration: NavigationEngineConfiguration = .init()) { self.configuration = configuration }

    public func setRoute(_ route: Route) { lock.withLock { self.route = route; lastAcceptedCoordinate = nil; offRouteSamples = 0 } }
    public func clear() { lock.withLock { route = nil; lastAcceptedCoordinate = nil; offRouteSamples = 0 } }

    public func update(location: Coordinate) -> NavigationProgress? {
        lock.withLock {
            guard var route, route.polyline.count >= 2 else { return nil }
            if let lastAcceptedCoordinate, geoDistance(lastAcceptedCoordinate, location) > configuration.maximumGPSJumpM {
                return snapshot(route: route, matched: lastAcceptedCoordinate, progressDistance: route.totalDistance - route.remainingDistance, offRoute: false, jump: true)
            }
            let match = closestPoint(to: location, on: route.polyline)
            lastAcceptedCoordinate = location
            if match.distanceFromRoute > configuration.offRouteDistanceM { offRouteSamples += 1 } else { offRouteSamples = 0 }
            let isOffRoute = offRouteSamples >= configuration.offRouteConfirmations
            let progressDistance = match.distanceFromRoute <= configuration.matchingToleranceM ? match.distanceAlongRoute : max(0, route.totalDistance - route.remainingDistance)
            route.remainingDistance = max(0, route.totalDistance - progressDistance)
            route.remainingDuration = route.totalDistance > 0 ? route.totalDuration * route.remainingDistance / route.totalDistance : 0
            route.status = isOffRoute ? .offRoute : (route.remainingDistance < 5 ? .completed : .active)
            self.route = route
            return snapshot(route: route, matched: match.coordinate, progressDistance: progressDistance, offRoute: isOffRoute, jump: false)
        }
    }

    private func snapshot(route: Route, matched: Coordinate?, progressDistance: Double, offRoute: Bool, jump: Bool) -> NavigationProgress {
        let next = route.turnList.map { ($0, distanceAlongPolyline(to: $0.coordinate, polyline: route.polyline)) }.first { $0.1 + 2 >= progressDistance }
        return .init(route: route, matchedCoordinate: matched, nextTurn: next?.0, distanceToNextTurn: max(0, (next?.1 ?? route.totalDistance) - progressDistance), remainingDistance: route.remainingDistance, remainingDuration: route.remainingDuration, progressRatio: route.totalDistance > 0 ? min(1, progressDistance / route.totalDistance) : 1, isOffRoute: offRoute, rejectedGPSJump: jump)
    }
}

private struct PolylineMatch { let coordinate: Coordinate; let distanceFromRoute: Double, distanceAlongRoute: Double }

private func closestPoint(to point: Coordinate, on polyline: [Coordinate]) -> PolylineMatch {
    var best = PolylineMatch(coordinate: polyline[0], distanceFromRoute: .greatestFiniteMagnitude, distanceAlongRoute: 0), cumulative = 0.0
    for index in 0..<(polyline.count - 1) {
        let a = polyline[index], b = polyline[index + 1], segmentLength = geoDistance(a, b)
        let projected = project(point, onto: a, b)
        let distance = geoDistance(point, projected.coordinate)
        if distance < best.distanceFromRoute { best = .init(coordinate: projected.coordinate, distanceFromRoute: distance, distanceAlongRoute: cumulative + segmentLength * projected.fraction) }
        cumulative += segmentLength
    }
    return best
}

private func distanceAlongPolyline(to point: Coordinate, polyline: [Coordinate]) -> Double { closestPoint(to: point, on: polyline).distanceAlongRoute }

private func project(_ point: Coordinate, onto a: Coordinate, _ b: Coordinate) -> (coordinate: Coordinate, fraction: Double) {
    let referenceLat = (a.latitude + b.latitude + point.latitude) / 3 * .pi / 180
    func xy(_ c: Coordinate) -> (Double, Double) { (c.longitude * cos(referenceLat), c.latitude) }
    let p = xy(point), start = xy(a), end = xy(b), dx = end.0 - start.0, dy = end.1 - start.1
    let denominator = dx * dx + dy * dy
    let fraction = denominator == 0 ? 0 : min(1, max(0, ((p.0 - start.0) * dx + (p.1 - start.1) * dy) / denominator))
    return (.init(latitude: a.latitude + (b.latitude - a.latitude) * fraction, longitude: a.longitude + (b.longitude - a.longitude) * fraction), fraction)
}

private func geoDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
    let radius = 6_371_000.0, lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLat = (b.latitude - a.latitude) * .pi / 180, dLon = (b.longitude - a.longitude) * .pi / 180
    let value = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return radius * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
}
