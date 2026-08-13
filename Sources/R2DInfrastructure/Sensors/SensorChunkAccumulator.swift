import Foundation
import R2DCore

public struct SensorChunkAccumulator: Sendable {
    public let sessionId: String, durationSec: Double, isSimulated: Bool
    public private(set) var sequence = 0, sampleCount = 0
    public private(set) var startedAt: Date
    public init(sessionId: String, startedAt: Date, durationSec: Double = 5, isSimulated: Bool = false) { self.sessionId = sessionId; self.startedAt = startedAt; self.durationSec = durationSec; self.isSimulated = isSimulated }
    public mutating func append(at date: Date) -> SensorChunk? { sampleCount += 1; guard date.timeIntervalSince(startedAt) >= durationSec else { return nil }; return flush(at: date) }
    public mutating func flush(at date: Date) -> SensorChunk? {
        guard sampleCount > 0 else { startedAt = date; return nil }; sequence += 1
        let chunk = SensorChunk(sessionId: sessionId, chunkSeq: sequence, startedAt: startedAt, endedAt: date, checksum: "samples-\(sequence)-\(sampleCount)", sampleCount: sampleCount, clientEventId: "\(sessionId)-\(sequence)", isSimulated: isSimulated)
        sampleCount = 0; startedAt = date; return chunk
    }
    public func effectiveHz(at date: Date) -> Double { let elapsed = date.timeIntervalSince(startedAt); return elapsed > 0 ? Double(sampleCount) / elapsed : 0 }
}
