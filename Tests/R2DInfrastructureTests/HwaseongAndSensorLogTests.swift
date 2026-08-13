import Foundation
import Testing
@testable import R2DCore
@testable import R2DInfrastructure

private final class ChunkBox: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [SensorChunk] = []
    func append(_ chunk: SensorChunk) { lock.withLock { storage.append(chunk) } }
    var values: [SensorChunk] { lock.withLock { storage } }
}

@Test func loadsHwaseongBikeRoadCatalog() throws {
    let catalog = try HwaseongBikeRoadCatalog.loadBundled()
    #expect(catalog.roads.count == 121)
    #expect(catalog.preferredDemoRoad?.name.contains("동탄원천로 1L") == true)
    #expect(catalog.preferredDemoRoad?.geometryQuality == .endpointsOnly)
    #expect(DemoNavigatorFixture.origin.latitude < 38)
}

@Test func importsSensorLoggerCSVIntoCanonicalPayload() throws {
    let csv = "timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,vibration_rms,latitude,longitude\n0.0,0.1,0.2,1.1,0.01,0.02,0.03,0.08,37.2,127.0\n"
    let samples = try SensorLoggerCSVDecoder().decode(Data(csv.utf8))
    #expect(samples.count == 1)
    #expect(samples[0].source == .sensorLogger)
    #expect(samples[0].acceleration?.z == 1.1)
    #expect(samples[0].coordinate == .init(latitude: 37.2, longitude: 127.0))
}

@Test func importsActualSensorLoggerAccelerometerColumnsAndNanoseconds() throws {
    let csv = "time,seconds_elapsed,x,y,z\n1698501144401773000,0.21677294921875,0.061,-0.001,-0.104\n"
    let sample = try #require(SensorLoggerCSVDecoder().decode(Data(csv.utf8)).first)
    #expect(sample.timestamp == 0.21677294921875)
    #expect(sample.acceleration?.x == 0.061)
}

@Test func sensorReplayChunksAreAlwaysMarkedSimulated() throws {
    let collector = SensorLogReplayCollector(samples: SensorLogEmulator.samples(profile: .rough, duration: 6, sampleRateHz: 10))
    let box = ChunkBox()
    let unsubscribe = collector.subscribe { box.append($0) }
    try collector.start(sessionId: "ride-hwaseong", profileId: "replay")
    collector.emitAll()
    unsubscribe()
    let result = box.values
    #expect(!result.isEmpty)
    #expect(result.allSatisfy { $0.isSimulated })
}
