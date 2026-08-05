import Foundation
import Testing
import R2DCore
@testable import R2DInfrastructure

@Test func locationFilterRejectsInvalidStaleAndDuplicateSamples() {
    let now = Date(), filter = LocationSampleFilter()
    let invalid = RawLocationSample(latitude: 0, longitude: 0, altitudeM: 0, speedMps: 1, courseDegrees: 1, horizontalAccuracyM: -1, timestamp: now)
    #expect(filter.filter(invalid, now: now, previous: nil) == nil)
    let stale = RawLocationSample(latitude: 0, longitude: 0, altitudeM: 0, speedMps: 1, courseDegrees: 1, horizontalAccuracyM: 5, timestamp: now.addingTimeInterval(-20))
    #expect(filter.filter(stale, now: now, previous: nil) == nil)
    let valid = RawLocationSample(latitude: 37, longitude: 127, altitudeM: 3, speedMps: 4, courseDegrees: 90, horizontalAccuracyM: 5, timestamp: now)
    let accepted = filter.filter(valid, now: now, previous: nil)
    #expect(accepted != nil); #expect(filter.filter(valid, now: now, previous: accepted) == nil)
}

@Test func locationFilterNormalizesNegativeSpeedAndCourseAndFlagsJump() throws {
    let now = Date(), filter = LocationSampleFilter()
    let negative = RawLocationSample(latitude: 37, longitude: 127, altitudeM: 3, speedMps: -1, courseDegrees: -1, horizontalAccuracyM: 5, timestamp: now)
    let normalized = try #require(filter.filter(negative, now: now, previous: nil)); #expect(normalized.speedMps == nil); #expect(normalized.bearingDegrees == nil)
    let jump = RawLocationSample(latitude: 37.1, longitude: 127, altitudeM: 3, speedMps: 45, courseDegrees: 90, horizontalAccuracyM: 5, timestamp: now.addingTimeInterval(1))
    #expect(filter.filter(jump, now: now.addingTimeInterval(1), previous: normalized)?.quality == .implausibleJump)
}

@Test func sensorAccumulatorBuildsFiveSecondMonotonicChunks() throws {
    let start = Date(timeIntervalSince1970: 100), almost = start.addingTimeInterval(4), end = start.addingTimeInterval(5)
    var buffer = SensorChunkAccumulator(sessionId: "ride", startedAt: start)
    #expect(buffer.append(at: almost) == nil); let firstValue = buffer.append(at: end); let first = try #require(firstValue); #expect(first.chunkSeq == 1); #expect(first.sampleCount == 2)
    let secondValue = buffer.append(at: end.addingTimeInterval(5)); let second = try #require(secondValue); #expect(second.chunkSeq == 2)
}
