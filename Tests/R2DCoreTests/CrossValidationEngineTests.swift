import XCTest
@testable import R2DCore

final class CrossValidationEngineTests: XCTestCase {
    func testPopulationScaledCoverageWorkload() {
        let (raw, scale, total) = CrossValidationEngine.calculateRegionalBossHealth(unscannedCells: 96, refreshCells: 37, activeRiders: 12)
        XCTAssertEqual(raw, 96 * 500 + 37 * 300) // 59100
        XCTAssertEqual(scale, 0.25, accuracy: 0.001) // Clamped to minimum scale 0.25
        XCTAssertEqual(total, Int((Double(raw) * 0.25).rounded())) // 14775
    }
    
    func test3RiderCrossValidation() {
        let logs: [(offsetMeters: Double, spikeDetected: Bool)] = [
            (2.4, true),
            (4.1, true),
            (6.8, true),
            (12.0, true) // Beyond 10m radius
        ]
        let result = CrossValidationEngine.crossValidate(riderLogs: logs)
        XCTAssertEqual(result.matchingRiders, 3)
        XCTAssertTrue(result.isVerified)
    }
    
    func testRepairConfirmation() {
        let validEvidence = RepairEvidence(maxTrajectoryDeviationM: 3.2, noImpactRiderCount: 4)
        XCTAssertTrue(validEvidence.isRepairConfirmed)
        
        let invalidEvidence = RepairEvidence(maxTrajectoryDeviationM: 6.5, noImpactRiderCount: 4)
        XCTAssertFalse(invalidEvidence.isRepairConfirmed)
    }
    
}
