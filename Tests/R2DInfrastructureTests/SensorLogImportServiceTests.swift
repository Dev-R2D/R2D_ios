import Foundation
import Testing
@testable import R2DCore
@testable import R2DInfrastructure

private actor ImportPipeline: TelemetryPipeline {
    private var chunks: [SensorChunk] = []; private var triggers = 0
    func start() async {}; func stop() async {}
    func enqueue(_ chunk: SensorChunk) async { chunks.append(chunk) }
    func triggerUpload() async { triggers += 1 }
    func flush(sessionID: String?) async {}
    func summary() async -> TelemetryQueueSummary { .init(pendingCount: chunks.count, uploadingCount: 0, acknowledgedCount: 0, failedCount: 0, quarantinedCount: 0, totalBytes: chunks.reduce(Int64(0)) { $0 + Int64($1.payload.count) }, oldestPendingAt: nil, isStorageFull: false, nextRetryAt: nil) }
    func snapshot() -> ([SensorChunk], Int) { (chunks, triggers) }
}

@Test func importsSensorLoggerJSONAsRealTelemetryAndTriggersUpload() async throws {
    let json = """
    [
      {"sensor":"Accelerometer","time":"1698501144401773000","seconds_elapsed":"0.2","x":"0.1","y":"0.2","z":"9.7"},
      {"sensor":"Gyroscope","time":"1698501144411773000","seconds_elapsed":"0.21","x":"0.01","y":"0.02","z":"0.03"},
      {"sensor":"Location","time":"1698501145514000000","seconds_elapsed":"1.3","latitude":"37.2","longitude":"127.0","speed":"4.2"}
    ]
    """
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("sensorlogger.json"); try Data(json.utf8).write(to: url)
    let pipeline = ImportPipeline(), service = SensorLogImportService(pipeline: pipeline)
    let result = try await service.importRecording(from: [url])
    let snapshot = await pipeline.snapshot()
    #expect(result.sampleCount == 3); #expect(result.chunkCount == 1)
    #expect(snapshot.0.count == 1); #expect(snapshot.0[0].isSimulated == false); #expect(snapshot.1 == 1)
}

@Test func importsMultipleNativeSensorLoggerCSVs() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let accelerometer = directory.appendingPathComponent("Accelerometer.csv")
    let gyroscope = directory.appendingPathComponent("Gyroscope.csv")
    try Data("time,seconds_elapsed,x,y,z\n1698501144401773000,0.2,0.1,0.2,9.7\n".utf8).write(to: accelerometer)
    try Data("time,seconds_elapsed,x,y,z\n1698501144411773000,0.21,0.01,0.02,0.03\n".utf8).write(to: gyroscope)
    let pipeline = ImportPipeline(), service = SensorLogImportService(pipeline: pipeline)
    let result = try await service.importRecording(from: [accelerometer, gyroscope])
    #expect(result.fileCount == 2); #expect(result.sampleCount == 2)
    let payload = try #require(await pipeline.snapshot().0.first?.payload)
    let samples = try JSONDecoder().decode([RoadSurfaceSensorSample].self, from: payload)
    #expect(samples.contains { $0.acceleration != nil }); #expect(samples.contains { $0.rotationRate != nil })
}
