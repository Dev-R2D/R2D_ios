import Foundation
import R2DCore

public enum SensorLogImportError: Error, Equatable, Sendable { case noFiles, unsupportedFile(String), unreadableFile(String), noSensorSamples }

public actor SensorLogImportService: SensorLogImporting {
    private let pipeline: TelemetryPipeline, chunkDuration: TimeInterval
    public init(pipeline: TelemetryPipeline, chunkDuration: TimeInterval = 5) { self.pipeline = pipeline; self.chunkDuration = chunkDuration }

    public func importRecording(from urls: [URL]) async throws -> SensorLogImportResult {
        guard !urls.isEmpty else { throw SensorLogImportError.noFiles }
        var samples: [RoadSurfaceSensorSample] = []
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { throw SensorLogImportError.unreadableFile(url.lastPathComponent) }
            switch url.pathExtension.lowercased() {
            case "json": samples.append(contentsOf: try decodeJSON(data))
            case "csv": samples.append(contentsOf: try SensorLoggerCSVDecoder().decode(data, kind: kind(for: url.lastPathComponent)))
            default: throw SensorLogImportError.unsupportedFile(url.lastPathComponent)
            }
        }
        samples.sort { $0.timestamp < $1.timestamp }
        guard let first = samples.first else { throw SensorLogImportError.noSensorSamples }
        let recordingID = "sensorlogger-\(UUID().uuidString.lowercased())"
        let grouped = Dictionary(grouping: samples) { Int(($0.timestamp - first.timestamp) / chunkDuration) }
        let base = Date()
        for (sequence, key) in grouped.keys.sorted().enumerated() {
            guard let values = grouped[key], let start = values.first, let end = values.last else { continue }
            let payload = try JSONEncoder().encode(values)
            let chunk = SensorChunk(sessionId: recordingID, chunkSeq: sequence + 1, startedAt: base.addingTimeInterval(start.timestamp - first.timestamp), endedAt: base.addingTimeInterval(end.timestamp - first.timestamp), checksum: "sensorlogger-import-\(sequence + 1)-\(values.count)", sampleCount: values.count, clientEventId: "\(recordingID)-\(sequence + 1)", isSimulated: false, payload: payload)
            await pipeline.enqueue(chunk)
        }
        await pipeline.triggerUpload()
        
        let extractedCoordinates = samples.compactMap(\.coordinate)
        let imuSpikeCount = samples.filter { sample in
            if let accel = sample.acceleration {
                let mag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
                return mag > 14.0 || mag < 4.0
            }
            return (sample.vibrationRMS ?? 0) > 2.0
        }.count

        return .init(recordingId: recordingID, fileCount: urls.count, sampleCount: samples.count, chunkCount: grouped.count, extractedCoordinates: extractedCoordinates, imuSpikeCount: imuSpikeCount)
    }

    private func kind(for filename: String) -> SensorLoggerCSVDecoder.SensorKind {
        let name = filename.lowercased()
        if name.contains("gyroscope") { return .gyroscope }
        if name.contains("gravity") { return .gravity }
        if name.contains("location") { return .location }
        if name.contains("accelerometer") { return .accelerometer }
        return .combined
    }

    private func decodeJSON(_ data: Data) throws -> [RoadSurfaceSensorSample] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw SensorLogImportError.noSensorSamples }
        return rows.compactMap { row in
            func number(_ key: String) -> Double? { if let value = row[key] as? NSNumber { return value.doubleValue }; return (row[key] as? String).flatMap(Double.init) }
            guard let sensor = (row["sensor"] ?? row["name"]) as? String else { return nil }
            let timestamp = number("seconds_elapsed") ?? number("time").map { $0 / 1_000_000_000 }
            guard let timestamp else { return nil }
            let name = sensor.lowercased()
            if name.contains("location"), let latitude = number("latitude"), let longitude = number("longitude") { return .init(timestamp: timestamp, source: .sensorLogger, coordinate: .init(latitude: latitude, longitude: longitude), speedMps: number("speed")) }
            guard let x = number("x"), let y = number("y"), let z = number("z") else { return nil }
            let vector = SensorVector3(x: x, y: y, z: z)
            if name.contains("gyro") { return .init(timestamp: timestamp, source: .sensorLogger, rotationRate: vector) }
            if name.contains("gravity") { return .init(timestamp: timestamp, source: .sensorLogger, gravity: vector) }
            if name.contains("acceler") { return .init(timestamp: timestamp, source: .sensorLogger, acceleration: vector) }
            return nil
        }
    }
}
