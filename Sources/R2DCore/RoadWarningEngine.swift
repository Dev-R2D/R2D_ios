import Foundation

public struct RoadWarningConfiguration: Sendable {
    public let minimumWarningDistanceM: Double, warningLookaheadSec: Double, maximumWarningDistanceM: Double
    public let minimumConfidence: Double, suspectedDamageVoiceConfidence: Double, cooldownSec: TimeInterval
    public let headingToleranceDegrees: Double, routeCorridorWidthM: Double, minimumMapMatchConfidence: Double
    public let warningRiskStates: Set<RiskState>, maximumStaleWarningAgeSec: TimeInterval
    public init(minimumWarningDistanceM: Double = 20, warningLookaheadSec: Double = 6, maximumWarningDistanceM: Double = 80, minimumConfidence: Double = 0.75, suspectedDamageVoiceConfidence: Double = 0.9, cooldownSec: TimeInterval = 60, headingToleranceDegrees: Double = 65, routeCorridorWidthM: Double = 35, minimumMapMatchConfidence: Double = 0.7, warningRiskStates: Set<RiskState> = [.rough, .suspectedDamage, .confirmedDamage, .restricted], maximumStaleWarningAgeSec: TimeInterval = 86_400) {
        self.minimumWarningDistanceM = minimumWarningDistanceM; self.warningLookaheadSec = warningLookaheadSec; self.maximumWarningDistanceM = maximumWarningDistanceM; self.minimumConfidence = minimumConfidence; self.suspectedDamageVoiceConfidence = suspectedDamageVoiceConfidence; self.cooldownSec = cooldownSec; self.headingToleranceDegrees = headingToleranceDegrees; self.routeCorridorWidthM = routeCorridorWidthM; self.minimumMapMatchConfidence = minimumMapMatchConfidence; self.warningRiskStates = warningRiskStates; self.maximumStaleWarningAgeSec = maximumStaleWarningAgeSec
    }
}

public struct RoadWarningEngine: Sendable {
    private let configuration: RoadWarningConfiguration
    private var warnedAt: [String: Date] = [:]
    public init(configuration: RoadWarningConfiguration = .init()) { self.configuration = configuration }
    public mutating func reset() { warnedAt.removeAll() }

    public mutating func evaluate(location: LocationSnapshot, navigation: NavigationProgress, route: Route, snapshot: RiskLayerSnapshot, now: Date) -> RoadWarning? {
        guard let current = location.coordinate, location.mapMatchConfidence >= configuration.minimumMapMatchConfidence else { return nil }
        let warningDistance = min(configuration.maximumWarningDistanceM, max(configuration.minimumWarningDistanceM, location.speedMps * configuration.warningLookaheadSec))
        let candidates = snapshot.cells.compactMap { cell -> (RoadCell, Double, Double)? in
            guard cell.dataState != .unknown, cell.dataState != .review, configuration.warningRiskStates.contains(cell.riskState), cell.confidence >= configuration.minimumConfidence else { return nil }
            if snapshot.isStale(at: now), now.timeIntervalSince(snapshot.generatedAt) > configuration.maximumStaleWarningAgeSec { return nil }
            guard let target = cell.geometry.coordinates.min(by: { geoDistance(current, $0) < geoDistance(current, $1) }) else { return nil }
            let distance = geoDistance(current, target); guard distance <= warningDistance else { return nil }
            guard distanceToRoute(target, route.polyline) <= configuration.routeCorridorWidthM else { return nil }
            let targetBearing = bearing(from: current, to: target)
            guard headingDifference(location.heading, targetBearing) <= configuration.headingToleranceDegrees else { return nil }
            let routeBearing = routeHeading(near: current, polyline: route.polyline)
            guard routeBearing.map({ headingDifference($0, targetBearing) <= configuration.headingToleranceDegrees }) ?? true else { return nil }
            let cooldownKey = "\(cell.id):\(cell.riskState.rawValue)"; guard warnedAt[cooldownKey].map({ now.timeIntervalSince($0) >= configuration.cooldownSec }) ?? true else { return nil }
            return (cell, distance, targetBearing)
        }.sorted { $0.1 < $1.1 }
        guard let (cell, distance, _) = candidates.first else { return nil }
        warnedAt["\(cell.id):\(cell.riskState.rawValue)"] = now
        let severity: RoadWarningSeverity = [.confirmedDamage, .restricted].contains(cell.riskState) ? .high : (cell.riskState == .suspectedDamage && cell.confidence < configuration.suspectedDamageVoiceConfidence ? .informational : .caution)
        return .init(id: "\(cell.id):\(cell.riskState.rawValue):\(Int(now.timeIntervalSince1970))", cellID: cell.id, riskState: cell.riskState, severity: severity, distanceM: distance, confidence: cell.confidence, messageKey: messageKey(cell.riskState), triggeredAt: now)
    }
}

private func messageKey(_ state: RiskState) -> String { switch state { case .confirmedDamage: "road.confirmed_damage"; case .restricted: "road.restricted"; case .rough: "road.rough"; case .suspectedDamage: "road.suspected_damage"; case .repairPending: "road.repair_pending"; case .normal: "road.normal" } }
private func geoDistance(_ a: Coordinate, _ b: Coordinate) -> Double { let dy = (b.latitude - a.latitude) * 111_320, dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * .pi / 180); return sqrt(dx * dx + dy * dy) }
private func bearing(from a: Coordinate, to b: Coordinate) -> Double { let y = sin((b.longitude-a.longitude) * .pi/180) * cos(b.latitude * .pi/180), x = cos(a.latitude * .pi/180) * sin(b.latitude * .pi/180) - sin(a.latitude * .pi/180) * cos(b.latitude * .pi/180) * cos((b.longitude-a.longitude) * .pi/180); return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
private func headingDifference(_ a: Double, _ b: Double) -> Double { let value = abs(a-b).truncatingRemainder(dividingBy: 360); return min(value, 360-value) }
private func routeHeading(near point: Coordinate, polyline: [Coordinate]) -> Double? { guard polyline.count > 1 else { return nil }; return (0..<(polyline.count-1)).min(by: { segmentDistance(point, polyline[$0], polyline[$0+1]) < segmentDistance(point, polyline[$1], polyline[$1+1]) }).map { bearing(from: polyline[$0], to: polyline[$0+1]) } }
private func distanceToRoute(_ point: Coordinate, _ polyline: [Coordinate]) -> Double { guard polyline.count > 1 else { return .greatestFiniteMagnitude }; return (0..<(polyline.count-1)).map { segmentDistance(point, polyline[$0], polyline[$0+1]) }.min() ?? .greatestFiniteMagnitude }
private func segmentDistance(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double { let latScale = 111_320.0, lonScale = latScale * cos(p.latitude * .pi/180), px = p.longitude*lonScale, py = p.latitude*latScale, ax = a.longitude*lonScale, ay = a.latitude*latScale, bx = b.longitude*lonScale, by = b.latitude*latScale, dx = bx-ax, dy = by-ay, denominator = dx*dx+dy*dy, t = denominator == 0 ? 0 : min(1,max(0,((px-ax)*dx+(py-ay)*dy)/denominator)); return sqrt(pow(px-(ax+t*dx),2)+pow(py-(ay+t*dy),2)) }
