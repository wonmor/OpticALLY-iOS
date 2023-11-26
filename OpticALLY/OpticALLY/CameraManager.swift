import AVFoundation

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var session = AVCaptureSession()
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoOutputQueue = DispatchQueue(label: "VideoOutputQueue")

    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        // Ensure the session is configured for video capture
        session.beginConfiguration()

        // Check for camera availability
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera is not available.")
            return
        }
        
        // Add video input
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                print("Cannot add video input to the session.")
                return
            }
        } catch {
            print("Error configuring video input: \(error)")
            return
        }
        
        // Set up video output
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        } else {
            print("Cannot add video output to the session.")
        }

        // Complete the session configuration
        session.commitConfiguration()

        // Start the session on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // Implement AVCaptureVideoDataOutputSampleBufferDelegate methods if needed
}
