import AVFoundation
import FocusCore
import Vision

enum CameraStatus: Equatable {
    case off, starting, running, denied, unavailable
}

/// Owns the capture session. Frames are analyzed in memory and dropped; nothing is stored or sent anywhere.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    /// Called on the camera queue with signals and a timestamp (seconds since reference date).
    var onSignals: ((FaceSignals, Double) -> Void)?

    private let queue = DispatchQueue(label: "FocusGuard.camera")
    private var configured = false
    private var lastFrame = 0.0
    /// Set by start(), cleared by stop(); read on the camera queue so a late start (permission prompt,
    /// slow device) never turns the camera on after the study phase ended.
    private var wanted = false

    var isRunning: Bool { session.isRunning }

    func start(_ completion: @escaping (CameraStatus) -> Void) {
        queue.async { self.wanted = true }
        let finish = { (status: CameraStatus) in DispatchQueue.main.async { completion(status) } }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { finish(self.run()) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                granted ? self.queue.async { finish(self.run()) } : finish(.denied)
            }
        default:
            finish(.denied)
        }
    }

    func stop() {
        queue.async {
            self.wanted = false
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func run() -> CameraStatus {
        guard wanted else { return .off }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return .unavailable }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            session.addInput(input)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning { session.startRunning() }
        guard wanted else {
            session.stopRunning()
            return .off
        }
        return session.isRunning ? .running : .unavailable
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastFrame >= 0.1, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        if let signals = FaceAnalyzer.analyze(pixels) { onSignals?(signals, now) }
    }
}

/// Apple Vision's pretrained face models -> eye openness, gaze offset and head pose.
enum FaceAnalyzer {
    /// nil when Vision failed on this frame: skip it rather than report "no face".
    static func analyze(_ pixels: CVPixelBuffer) -> FaceSignals? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        let rectangles = VNDetectFaceRectanglesRequest()
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        do { try handler.perform([rectangles]) } catch { return nil }
        guard let pose = largest(rectangles.results) else { return .noFace }

        // Landmarks only for the face already found: face detection runs once per frame.
        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = [pose]
        do { try handler.perform([landmarks]) } catch { return nil }
        guard let face = landmarks.results?.first,
              let marks = face.landmarks, let left = marks.leftEye, let right = marks.rightEye
        else {
            // A face without usable eyes (turned away, occluded) is not an absent user.
            return FaceSignals(faceFound: true, ear: 0, gazeOffset: 0, yaw: 0, pitch: 0, confidence: 0)
        }

        let degrees = 180 / Double.pi
        return FaceSignals(
            faceFound: true,
            ear: (openness(left) + openness(right)) / 2,
            gazeOffset: max(offset(left, marks.leftPupil), offset(right, marks.rightPupil)),
            yaw: (pose.yaw?.doubleValue ?? 0) * degrees,
            pitch: (pose.pitch?.doubleValue ?? 0) * degrees,
            confidence: Double(marks.confidence)
        )
    }

    private static func largest(_ faces: [VNFaceObservation]?) -> VNFaceObservation? {
        faces?.max { $0.boundingBox.width < $1.boundingBox.width }
    }

    private static func bounds(_ region: VNFaceLandmarkRegion2D) -> CGRect {
        let xs = region.normalizedPoints.map(\.x), ys = region.normalizedPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func openness(_ eye: VNFaceLandmarkRegion2D) -> Double {
        let box = bounds(eye)
        return box.width > 0 ? box.height / box.width : 0
    }

    private static func offset(_ eye: VNFaceLandmarkRegion2D, _ pupil: VNFaceLandmarkRegion2D?) -> Double {
        let box = bounds(eye)
        guard let p = pupil?.normalizedPoints.first, box.width > 0 else { return 0 }
        return abs(p.x - box.midX) / (box.width / 2)
    }
}
