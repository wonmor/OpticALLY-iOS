//
//  CameraDelegate.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import UIKit
import AVFoundation
import CoreVideo
import MobileCoreServices
import Accelerate
import SwiftUI
import Vision
import SceneKit
import ARKit
import Combine
import Firebase
import Foundation

struct CameraPreview: UIViewControllerRepresentable {
    @Binding var session: AVCaptureSession
    
    func makeUIViewController(context: Context) -> CameraPreviewController {
        let controller = CameraPreviewController()
        controller.session = session
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {
        // Nothing to update
    }
}

class CameraPreviewController: UIViewController {
    var session: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}

class CameraDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isFaceDetected: Bool = false
    @Published var rotationPercentage: Double = 0
    @Published var isComplete: Bool = false
    @Published var faceLandmarks: [CIFaceFeature] = []
    @Published var faceShape: FaceShape? = nil
    
    var stillImageOutput: AVCaptureStillImageOutput!
    
    private var computeFaceShapeWorkItem: DispatchWorkItem?
    
    enum FaceShape: String {
        case oval = "Oval"
        case square = "Square"
        case rectangle = "Rectangle"
        case round = "Round"
        case triangle = "Triangle"
        case diamond = "Diamond"
    }
    
    func computeFaceShape(from faces: [CIFaceFeature]) {
        guard let face = faces.first else {
            faceShape = nil
            return
        }
        
        let faceWidth = face.bounds.width
        let faceLength = face.bounds.height
        
        // Detecting aspect ratio
        let aspectRatio = faceLength / faceWidth
        
        print("Face Aspect Ratio: \(aspectRatio)")
        
        // Using a threshold to decide the face shape based on the aspect ratio and position of landmarks
        if aspectRatio < 1.2 {
            if let leftEye: CGPoint? = face.leftEyePosition, let rightEye: CGPoint? = face.rightEyePosition {
                let eyeWidth = abs(leftEye!.x - rightEye!.x)
                
                if eyeWidth / faceWidth > 0.5 {
                    faceShape = .round
                } else {
                    faceShape = .square
                }
            }
        } else if aspectRatio < 1.5 {
            faceShape = .oval
        } else if aspectRatio >= 1.5 {
            faceShape = .rectangle
        }
        
        // If there are landmarks available, modify the classification based on their positions
        if let leftEye: CGPoint? = face.leftEyePosition, let rightEye: CGPoint? = face.rightEyePosition, let mouthPosition: CGPoint? = face.mouthPosition {
            let eyeCenterY = (leftEye!.y + rightEye!.y) / 2.0
            let topThird = face.bounds.minY + faceLength * (2.0/3.0)
            let bottomThird = face.bounds.minY + faceLength * (1.0/3.0)
            
            if eyeCenterY > topThird {
                faceShape = .triangle
            } else if mouthPosition!.y < bottomThird {
                faceShape = .diamond
            }
        }
    }
    
    var session = AVCaptureSession()
    private var lastFaceBounds: CGRect? = nil
    
    func setupCamera() {
        session.sessionPreset = .photo
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Unable to access the camera!")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            if session.canAddInput(input) {
                session.addInput(input)
                
                let metadataOutput = AVCaptureMetadataOutput()
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                if session.canAddOutput(metadataOutput) {
                    session.addOutput(metadataOutput)
                    metadataOutput.metadataObjectTypes = [.face]
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.session.startRunning()
                    }
                }
            }
        } catch {
            print(error.localizedDescription)
        }
        // Add video data output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        
        stillImageOutput = AVCaptureStillImageOutput()
        if session.canAddOutput(stillImageOutput) {
            session.addOutput(stillImageOutput)
        }
    }
    
    // Handle video frames and detect face landmarks
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let faces = faceDetector?.features(in: ciImage) as? [CIFaceFeature] ?? []
        
        DispatchQueue.main.async {
            self.faceLandmarks = faces
            
            // Cancel the previous work item if it's still pending
            self.computeFaceShapeWorkItem?.cancel()
            
            // Create a new work item and dispatch it after a delay
            let workItem = DispatchWorkItem { [weak self] in
                self?.computeFaceShape(from: faces)
            }
            self.computeFaceShapeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)  // 0.5 second delay for debouncing
        }
    }
    
    func captureStillImage(completion: @escaping (CIImage?) -> Void) {
        guard let videoConnection = stillImageOutput.connection(with: .video) else { return }
        
        stillImageOutput.captureStillImageAsynchronously(from: videoConnection) { (sampleBuffer, error) in
            guard let sampleBuffer = sampleBuffer, let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer) else {
                completion(nil)
                return
            }
            
            let image = UIImage(data: imageData)
            completion(CIImage(image: image!))
        }
    }
    
    func detectFaceShape(from ciImage: CIImage) {
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let faces = faceDetector?.features(in: ciImage) as? [CIFaceFeature] ?? []
        if let face = faces.first {
            DispatchQueue.main.async {
                self.computeFaceShape(from: [face])
            }
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let faceObject = metadataObjects.first(where: { $0.type == .face }) as? AVMetadataFaceObject else {
            isFaceDetected = false
            return
        }
        
        isFaceDetected = true
        
        // If face is detected and we haven't computed the face shape yet, capture a still image
        if faceShape == nil {
            captureStillImage { image in
                if let ciImage = image {
                    self.detectFaceShape(from: ciImage)
                }
            }
        }
        
        if let lastBounds = lastFaceBounds {
            let movement = faceObject.bounds.origin.x - lastBounds.origin.x
            rotationPercentage += Double(abs(movement))
            if rotationPercentage >= 1 {
                rotationPercentage = 1
                isComplete = true
            }
        }
        
        lastFaceBounds = faceObject.bounds
    }
}
