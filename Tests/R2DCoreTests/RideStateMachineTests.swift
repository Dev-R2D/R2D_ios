import Foundation
import Testing
@testable import R2DCore

@Test func happyPathAndInvalidTransition() throws {
    var session = RideSession(id: "ride-1", routeId: "route-1")
    try RideStateMachine.transition(&session, to: .ready)
    try RideStateMachine.transition(&session, to: .active)
    try RideStateMachine.transition(&session, to: .paused)
    try RideStateMachine.transition(&session, to: .active)
    try RideStateMachine.transition(&session, to: .finishing)
    try RideStateMachine.transition(&session, to: .completed)
    #expect(session.state == .completed)
    #expect(throws: RideError.self) { try RideStateMachine.transition(&session, to: .active) }
}

@Test func onlyOneActiveFamilySession() throws {
    let repository = MemoryRideSessionRepository(ids: FixedID())
    _ = try repository.create(routeId: "route-1", boss: nil)
    #expect(throws: RideError.activeSessionExists) { try repository.create(routeId: "route-2", boss: nil) }
}

private struct FixedID: IdGenerator { func next() -> String { "fixed-id" } }

@Test func fileRepositoryRestoresActiveSession() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("r2d-test-\(UUID().uuidString)/ride.json")
    let first = try FileRideSessionRepository(fileURL: url, ids: FixedID()); var ride = try first.create(routeId: "route", boss: nil)
    try RideStateMachine.transition(&ride, to: .ready); try RideStateMachine.transition(&ride, to: .active); try first.save(ride)
    let restored = try FileRideSessionRepository(fileURL: url); #expect(restored.active()?.id == ride.id); #expect(restored.active()?.state == .active)
}
