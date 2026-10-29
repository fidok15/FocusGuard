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

    var isRunning: Bool { session.isRunning }

    func start(_ completion: @escaping (CameraStatus) -> Void) {
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
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func run() -> CameraStatus {
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
        return session.isRunning ? .running : .unavailable
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastFrame >= 0.1, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        onSignals?(FaceAnalyzer.analyze(pixels), now)
    }
}

/// Apple Vision's pretrained face models -> eye openness, gaze offset and head pose.
enum FaceAnalyzer {
    static func analyze(_ pixels: CVPixelBuffer) -> FaceSignals {
        let rectangles = VNDetectFaceRectanglesRequest()
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        let landmarks = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([rectangles, landmarks])

        guard let face = largest(landmarks.results),
              let marks = face.landmarks, let left = marks.leftEye, let right = marks.rightEye
        else { return .noFace }

        let pose = largest(rectangles.results) ?? face
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
