import UIKit
import AVFoundation

class CameraViewController: UIViewController {

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if captureSession?.isRunning == false {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession?.isRunning == true {
            captureSession.stopRunning()
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera not available.")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                previewLayer.frame = view.bounds
                previewLayer.videoGravity = .resizeAspectFill
                view.layer.addSublayer(previewLayer)
                
            } else {
                print("Cannot add input to session.")
            }
        } catch {
            print("Error creating input: \(error)")
        }
    }

    // If you want to handle orientation changes, this method will help
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if let connection = self.previewLayer?.connection {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) ?? .portrait
            }
        }
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
}
