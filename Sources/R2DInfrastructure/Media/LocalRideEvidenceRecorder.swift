#if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import CoreMedia
import Foundation
import R2DCore
import UIKit

public final class LocalRideEvidenceRecorder: NSObject, RideEvidenceRecording, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private struct AnalysisPayload: Codable {
        let event: RideEvidenceEvent
        let clipStartMS: Int
        let clipEndMS: Int
        let frameFiles: [String]
        let prompt: String
    }

    private struct BufferedVideoSample {
        let elapsedMS: Int
        let sampleBuffer: CMSampleBuffer
    }

    private struct PendingClip {
        let event: RideEvidenceEvent
        let startMS: Int
        let endMS: Int
    }

    private let lock = NSLock()
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let captureQueue = DispatchQueue(label: "app.r2d.ride-evidence.camera")
    private let writerQueue = DispatchQueue(label: "app.r2d.ride-evidence.writer", qos: .utility)
    private let writerGroup = DispatchGroup()
    private let bufferDurationMS = 10_000
    private let preEventMS = 3_000
    private let postEventMS = 2_000

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var rideID = ""
    private var routeID: String?
    private var startedAt = Date()
    private var mediaStartedAt: CFTimeInterval?
    private var latestLocation: LocationSnapshot = .empty
    private var sensorTimestampBase: TimeInterval?
    private var lastAccelerationMagnitude: Double?
    private var lastAccelerationTimestamp: TimeInterval?
    private var lastEventElapsedMS = -10_000
    private var ringBuffer: [BufferedVideoSample] = []
    private var pendingClips: [PendingClip] = []
    private var events: [RideEvidenceEvent] = []
    private var clips: [RideEvidenceClip] = []

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootDirectory = support.appendingPathComponent("R2D/RideEvidence", isDirectory: true)
        super.init()
    }

    public func startRide(rideId: String, routeId: String?, startedAt: Date) async {
        lock.withLock {
            self.rideID = rideId
            self.routeID = routeId
            self.startedAt = startedAt
            self.mediaStartedAt = CACurrentMediaTime()
            self.sensorTimestampBase = nil
            self.lastAccelerationMagnitude = nil
            self.lastAccelerationTimestamp = nil
            self.lastEventElapsedMS = -10_000
            self.ringBuffer = []
            self.pendingClips = []
            self.events = []
            self.clips = []
        }
        try? fileManager.createDirectory(at: directory(for: rideId), withIntermediateDirectories: true)
        guard let session = makeCaptureSession() else { return }
        lock.withLock { captureSession = session }
        session.startRunning()
    }

    public func recordLocation(_ snapshot: LocationSnapshot, at date: Date) async {
        lock.withLock { latestLocation = snapshot }
    }

    public func processSensorChunk(_ chunk: SensorChunk) async {
        guard let samples = try? JSONDecoder().decode([RoadSurfaceSensorSample].self, from: chunk.payload), !samples.isEmpty else { return }
        lock.withLock {
            if rideID.isEmpty {
                rideID = chunk.sessionId
                startedAt = chunk.startedAt
                mediaStartedAt = CACurrentMediaTime()
            }
        }
        let base = lock.withLock { sensorTimestampBase ?? samples[0].timestamp }
        let windows = Dictionary(grouping: samples) { sample in
            Int(((sample.timestamp - base) / 0.5).rounded(.down))
        }
        for key in windows.keys.sorted() {
            guard let window = windows[key] else { continue }
            inspect(window: window, rideID: chunk.sessionId)
        }
    }

    public func stopRide() async -> RideEvidenceSummary? {
        let session = lock.withLock { captureSession }
        session?.stopRunning()

        let remaining = lock.withLock { pendingClips }
        for clip in remaining {
            finishClip(clip)
        }
        await waitForWriters()

        let snapshot = lock.withLock { (rideID, startedAt, events, clips) }
        guard !snapshot.0.isEmpty else { return nil }
        let summary = RideEvidenceSummary(
            rideID: snapshot.0,
            startedAt: snapshot.1,
            endedAt: Date(),
            videoURL: nil,
            events: snapshot.2,
            clips: snapshot.3
        )
        if let data = try? JSONEncoder.pretty.encode(summary) {
            try? data.write(to: directory(for: snapshot.0).appendingPathComponent("ride-evidence-summary.json"), options: [.atomic])
        }
        lock.withLock {
            captureSession = nil
            videoOutput = nil
            pendingClips = []
            ringBuffer = []
        }
        return summary
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let copied = sampleBuffer.copyForBuffering() else { return }
        let elapsedMS = currentMediaElapsedMS()
        var clipsToFinish: [PendingClip] = []
        lock.withLock {
            ringBuffer.append(BufferedVideoSample(elapsedMS: elapsedMS, sampleBuffer: copied))
            ringBuffer.removeAll { elapsedMS - $0.elapsedMS > bufferDurationMS }
            clipsToFinish = pendingClips.filter { elapsedMS >= $0.endMS }
            pendingClips.removeAll { elapsedMS >= $0.endMS }
        }
        clipsToFinish.forEach { finishClip($0) }
    }

    private func makeCaptureSession() -> AVCaptureSession? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera)
        else { return nil }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input) else { session.commitConfiguration(); return nil }
        session.addInput(input)
        configureFrameRate(camera)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else { session.commitConfiguration(); return nil }
        session.addOutput(output)
        output.connection(with: .video)?.videoRotationAngle = 90
        session.commitConfiguration()
        videoOutput = output
        return session
    }

    private func configureFrameRate(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            camera.unlockForConfiguration()
        } catch {
            camera.unlockForConfiguration()
        }
    }

    private func inspect(window: [RoadSurfaceSensorSample], rideID: String) {
        guard let first = window.first else { return }
        lock.withLock {
            if sensorTimestampBase == nil { sensorTimestampBase = first.timestamp }
        }
        let base = lock.withLock { sensorTimestampBase ?? first.timestamp }
        var peak = 0.0
        var maxJerk = 0.0
        var gyroSquares: [Double] = []
        var eventCoordinate: Coordinate?
        var eventSpeed: Double?
        for sample in window {
            if let acceleration = sample.acceleration {
                let magnitude = abs(acceleration.magnitude - 9.80665)
                peak = max(peak, magnitude)
                let previous = lock.withLock { (lastAccelerationMagnitude, lastAccelerationTimestamp) }
                if let previousMagnitude = previous.0, let previousTime = previous.1 {
                    let dt = max(0.001, sample.timestamp - previousTime)
                    maxJerk = max(maxJerk, abs(magnitude - previousMagnitude) / dt)
                }
                lock.withLock {
                    lastAccelerationMagnitude = magnitude
                    lastAccelerationTimestamp = sample.timestamp
                }
            }
            if let jerk = sample.jerk { maxJerk = max(maxJerk, abs(jerk)) }
            if let rotation = sample.rotationRate {
                let magnitude = rotation.magnitude
                gyroSquares.append(magnitude * magnitude)
            }
            eventCoordinate = sample.coordinate ?? eventCoordinate
            eventSpeed = sample.speedMps ?? eventSpeed
        }
        let gyroRMS = sqrt((gyroSquares.reduce(0, +)) / Double(max(1, gyroSquares.count)))
        guard peak >= 1.6 || maxJerk >= 4.0 else { return }
        let elapsedMS = Int(((first.timestamp - base) * 1_000).rounded())
        let shouldAppend = lock.withLock { elapsedMS - lastEventElapsedMS >= 1_500 }
        guard shouldAppend else { return }
        let location = lock.withLock { latestLocation }
        let event = RideEvidenceEvent(
            id: String(format: "EVT-%03d", lock.withLock { events.count + 1 }),
            rideID: rideID,
            elapsedTimeMS: max(0, elapsedMS),
            accelerationPeak: peak,
            jerk: maxJerk,
            gyroscopeRMS: gyroRMS,
            coordinate: eventCoordinate ?? location.coordinate,
            speedMps: eventSpeed ?? location.speedMps
        )
        let pending = PendingClip(event: event, startMS: max(0, event.elapsedTimeMS - preEventMS), endMS: event.elapsedTimeMS + postEventMS)
        lock.withLock {
            lastEventElapsedMS = elapsedMS
            events.append(event)
            pendingClips.append(pending)
        }
    }

    private func finishClip(_ clip: PendingClip) {
        let samples = lock.withLock {
            ringBuffer.filter { clip.startMS <= $0.elapsedMS && $0.elapsedMS <= clip.endMS }
        }
        let ride = lock.withLock { rideID }
        let clipDirectory = directory(for: ride).appendingPathComponent(clip.event.id, isDirectory: true)
        try? fileManager.createDirectory(at: clipDirectory, withIntermediateDirectories: true)
        let outputURL = clipDirectory.appendingPathComponent("\(clip.event.id)-clip.mp4")
        let frameURLs = writeFrames(from: samples, event: clip.event, directory: clipDirectory)
        let analysisURL = writeAnalysisPayload(event: clip.event, clipStartMS: clip.startMS, clipEndMS: clip.endMS, frames: frameURLs, directory: clipDirectory)
        writerGroup.enter()
        writerQueue.async { [weak self] in
            defer { self?.writerGroup.leave() }
            let writtenClip = self?.writeClip(samples: samples, to: outputURL) == true ? outputURL : nil
            let evidenceClip = RideEvidenceClip(
                id: "\(clip.event.id)-clip",
                eventID: clip.event.id,
                clipURL: writtenClip,
                frameURLs: frameURLs,
                analysisRequestURL: analysisURL,
                startsAtMS: clip.startMS,
                endsAtMS: clip.endMS
            )
            self?.lock.withLock { self?.clips.append(evidenceClip) }
        }
    }

    private func waitForWriters() async {
        await withCheckedContinuation { continuation in
            writerGroup.notify(queue: writerQueue) {
                continuation.resume()
            }
        }
    }

    private func writeClip(samples: [BufferedVideoSample], to outputURL: URL) -> Bool {
        try? fileManager.removeItem(at: outputURL)
        guard let first = samples.first,
              let format = CMSampleBufferGetFormatDescription(first.sampleBuffer),
              let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        else { return false }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoExpectedSourceFrameRateKey: 15
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        writer.startWriting()
        let firstPTS = CMSampleBufferGetPresentationTimeStamp(first.sampleBuffer)
        writer.startSession(atSourceTime: firstPTS)
        for sample in samples {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            _ = input.append(sample.sampleBuffer)
        }
        input.markAsFinished()
        let group = DispatchGroup()
        group.enter()
        writer.finishWriting { group.leave() }
        _ = group.wait(timeout: .now() + 6)
        return writer.status == .completed
    }

    private func writeFrames(from samples: [BufferedVideoSample], event: RideEvidenceEvent, directory: URL) -> [URL] {
        let offsets = [-3_000, -2_000, -1_000, -500, 0, 1_000]
        var output: [URL] = []
        for offset in offsets {
            let target = event.elapsedTimeMS + offset
            guard let sample = samples.min(by: { abs($0.elapsedMS - target) < abs($1.elapsedMS - target) }),
                  let image = sample.sampleBuffer.previewImage(),
                  let data = image.jpegData(compressionQuality: 0.82)
            else { continue }
            let name = String(format: "%@-%+dms.jpg", event.id, offset).replacingOccurrences(of: "+", with: "plus")
            let url = directory.appendingPathComponent(name)
            if (try? data.write(to: url, options: [.atomic])) != nil {
                output.append(url)
            }
        }
        return output
    }

    private func writeAnalysisPayload(event: RideEvidenceEvent, clipStartMS: Int, clipEndMS: Int, frames: [URL], directory: URL) -> URL? {
        let payload = AnalysisPayload(
            event: event,
            clipStartMS: clipStartMS,
            clipEndMS: clipEndMS,
            frameFiles: frames.map(\.lastPathComponent),
            prompt: """
            R2D road event candidate. Use the attached frames and sensor metadata to classify the road state as one of: 탈락, 단차, 파손, 포트홀, 마모, 줄눈벌어짐, 융기, 배수시설, 점자블록, 시설물커버, 판단불가. Return JSON with classification, confidence, evidence, false_positive, field_inspection_required.
            """
        )
        let url = directory.appendingPathComponent("ai-analysis-request.json")
        guard let data = try? JSONEncoder.pretty.encode(payload),
              (try? data.write(to: url, options: [.atomic])) != nil
        else { return nil }
        return url
    }

    private func currentMediaElapsedMS() -> Int {
        let start = lock.withLock { mediaStartedAt ?? CACurrentMediaTime() }
        return max(0, Int(((CACurrentMediaTime() - start) * 1_000).rounded()))
    }

    private func directory(for rideID: String) -> URL {
        rootDirectory.appendingPathComponent(rideID.isEmpty ? "pending" : rideID, isDirectory: true)
    }
}

private extension CMSampleBuffer {
    func copyForBuffering() -> CMSampleBuffer? {
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault, sampleBuffer: self, sampleBufferOut: &copy)
        return copy
    }

    func previewImage() -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
#else
import Foundation
import R2DCore

public final class LocalRideEvidenceRecorder: RideEvidenceRecording, @unchecked Sendable {
    public init() {}
    public func startRide(rideId: String, routeId: String?, startedAt: Date) async {}
    public func recordLocation(_ snapshot: LocationSnapshot, at date: Date) async {}
    public func processSensorChunk(_ chunk: SensorChunk) async {}
    public func stopRide() async -> RideEvidenceSummary? { nil }
}
#endif
