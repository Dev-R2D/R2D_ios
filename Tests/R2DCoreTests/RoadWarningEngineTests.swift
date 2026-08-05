import Foundation
import Testing
@testable import R2DCore

private let warningOrigin = Coordinate(latitude: 37.55, longitude: 127.04)
private let warningRoute = Route(id: "warning-route", polyline: [warningOrigin, .init(latitude: 37.552, longitude: 127.04)], totalDistance: 222, totalDuration: 60, turnList: [], riskCells: [])
private func warningCell(id: String = "cell", metersNorth: Double = 30, metersEast: Double = 0, data: DataState = .verified, risk: RiskState = .confirmedDamage, confidence: Double = 0.95, validUntil: Date? = nil) -> RoadCell {
    .init(id: id, geometry: .point(.init(latitude: warningOrigin.latitude + metersNorth / 111_320, longitude: warningOrigin.longitude + metersEast / (111_320 * cos(warningOrigin.latitude * .pi / 180)))), dataState: data, riskState: risk, riskScore: 90, confidence: confidence, lastObservedAt: Date(timeIntervalSince1970: 900), validUntil: validUntil, observationCount: 5, independentDeviceCount: 3, cellVersion: "c1", layerVersion: "l1")
}
private func warningSnapshot(_ cells: [RoadCell], expiresAt: Date? = Date(timeIntervalSince1970: 2_000)) -> RiskLayerSnapshot { .init(layerVersion: "l1", generatedAt: Date(timeIntervalSince1970: 900), expiresAt: expiresAt, cells: cells) }
private func warningNavigation() -> NavigationProgress { .init(route: warningRoute, matchedCoordinate: warningOrigin, nextTurn: nil, distanceToNextTurn: 200, remainingDistance: 222, remainingDuration: 60, progressRatio: 0, isOffRoute: false, rejectedGPSJump: false) }
private func warningLocation(speed: Double = 6, heading: Double = 0, confidence: Double = 0.95) -> LocationSnapshot { .init(coordinate: warningOrigin, speedMps: speed, heading: heading, mapMatchConfidence: confidence) }

@Test func verifiedConfirmedDamageIsAllowedAndProducesHighWarning() {
    var engine = RoadWarningEngine(); let cell = warningCell()
    let warning = engine.evaluate(location: warningLocation(), navigation: warningNavigation(), route: warningRoute, snapshot: warningSnapshot([cell]), now: Date(timeIntervalSince1970: 1_000))
    #expect(cell.dataState == .verified && cell.riskState == .confirmedDamage); #expect(warning?.severity == .high)
}

@Test func unknownReviewAndNormalDoNotWarn() {
    for cell in [warningCell(data: .unknown), warningCell(data: .review), warningCell(risk: .normal)] { var engine = RoadWarningEngine(); #expect(engine.evaluate(location: warningLocation(), navigation: warningNavigation(), route: warningRoute, snapshot: warningSnapshot([cell]), now: Date(timeIntervalSince1970: 1_000)) == nil) }
}

@Test func staleStateRemainsIndependentFromRiskStateAndRepairPendingRoundTrips() throws {
    let staleDamage = warningCell(data: .stale, risk: .confirmedDamage), repair = warningCell(id: "repair", data: .verified, risk: .repairPending)
    #expect(staleDamage.dataState == .stale); #expect(staleDamage.riskState == .confirmedDamage); #expect(repair.riskState == .repairPending)
    #expect(try JSONDecoder().decode(RoadCell.self, from: JSONEncoder().encode(repair)) == repair)
}

@Test func lowConfidenceDistanceAndRouteCorridorExcludeWarnings() {
    let config = RoadWarningConfiguration(routeCorridorWidthM: 10)
    for cell in [warningCell(confidence: 0.4), warningCell(metersNorth: 100), warningCell(metersNorth: 20, metersEast: 30)] { var engine = RoadWarningEngine(configuration: config); #expect(engine.evaluate(location: warningLocation(), navigation: warningNavigation(), route: warningRoute, snapshot: warningSnapshot([cell]), now: Date(timeIntervalSince1970: 1_000)) == nil) }
}

@Test func oppositeHeadingAndPoorMapMatchExcludeWarning() {
    for location in [warningLocation(heading: 180), warningLocation(confidence: 0.2)] { var engine = RoadWarningEngine(); #expect(engine.evaluate(location: location, navigation: warningNavigation(), route: warningRoute, snapshot: warningSnapshot([warningCell()]), now: Date(timeIntervalSince1970: 1_000)) == nil) }
}

@Test func sameCellAndGPSJitterRespectCooldown() {
    var engine = RoadWarningEngine(configuration: .init(cooldownSec: 60)); let snapshot = warningSnapshot([warningCell()]), navigation = warningNavigation()
    #expect(engine.evaluate(location: warningLocation(), navigation: navigation, route: warningRoute, snapshot: snapshot, now: Date(timeIntervalSince1970: 1_000)) != nil)
    #expect(engine.evaluate(location: .init(coordinate: .init(latitude: warningOrigin.latitude + 0.00001, longitude: warningOrigin.longitude), speedMps: 6, heading: 0, mapMatchConfidence: 0.95), navigation: navigation, route: warningRoute, snapshot: snapshot, now: Date(timeIntervalSince1970: 1_010)) == nil)
    #expect(engine.evaluate(location: warningLocation(), navigation: navigation, route: warningRoute, snapshot: snapshot, now: Date(timeIntervalSince1970: 1_061)) != nil)
}

@Test func speedExpandsWarningDistance() {
    let cell = warningCell(metersNorth: 55), snapshot = warningSnapshot([cell]); var slow = RoadWarningEngine(), fast = RoadWarningEngine()
    #expect(slow.evaluate(location: warningLocation(speed: 2), navigation: warningNavigation(), route: warningRoute, snapshot: snapshot, now: Date(timeIntervalSince1970: 1_000)) == nil)
    #expect(fast.evaluate(location: warningLocation(speed: 10), navigation: warningNavigation(), route: warningRoute, snapshot: snapshot, now: Date(timeIntervalSince1970: 1_000)) != nil)
}

@Test func roughIsCautionSuspectedCanBeInformationalAndRestrictedIsHigh() {
    for (risk, confidence, severity) in [(RiskState.rough, 0.9, RoadWarningSeverity.caution), (.suspectedDamage, 0.8, .informational), (.restricted, 0.9, .high)] { var engine = RoadWarningEngine(); let warning = engine.evaluate(location: warningLocation(), navigation: warningNavigation(), route: warningRoute, snapshot: warningSnapshot([warningCell(risk: risk, confidence: confidence)]), now: Date(timeIntervalSince1970: 1_000)); #expect(warning?.severity == severity) }
}

@Test func overlyStaleCacheSuppressesWarningWithoutMutatingRiskState() {
    let cell = warningCell(); var engine = RoadWarningEngine(configuration: .init(maximumStaleWarningAgeSec: 50))
    let snapshot = RiskLayerSnapshot(layerVersion: "old", generatedAt: Date(timeIntervalSince1970: 800), expiresAt: Date(timeIntervalSince1970: 900), cells: [cell])
    #expect(engine.evaluate(location: warningLocation(), navigation: warningNavigation(), route: warningRoute, snapshot: snapshot, now: Date(timeIntervalSince1970: 1_000)) == nil); #expect(snapshot.cells[0].riskState == .confirmedDamage)
}
