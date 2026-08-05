import Foundation

public enum RideStateMachine {
    private static let allowed: [RideSessionState: Set<RideSessionState>] = [
        .created: [.ready, .aborted], .ready: [.active, .aborted],
        .active: [.paused, .finishing, .aborted], .paused: [.active, .finishing, .aborted],
        .finishing: [.completed, .aborted], .completed: [], .aborted: []
    ]

    public static func transition(_ session: inout RideSession, to target: RideSessionState, at date: Date = Date()) throws {
        guard allowed[session.state, default: []].contains(target) else { throw RideError.invalidTransition(session.state, target) }
        session.state = target
        if target == .active, session.startedAt == nil { session.startedAt = date }
        if target == .completed || target == .aborted { session.endedAt = date }
    }
}
