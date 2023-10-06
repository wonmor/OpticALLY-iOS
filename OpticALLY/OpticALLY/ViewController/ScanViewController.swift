import UIKit
import AVFoundation

class ScanViewController: UIViewController {
    var captureSession: AVCaptureSession!
    var photoOutput: AVCapturePhotoOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    
    var depthFileCounter = 1
    var videoFileCounter = 1
    
    var captureButton: UIButton!
    var exportButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("Hi there!")
        
        // Initialize the capture session
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        // Set up the capture device (builtInTrueDepthCamera in this case)
        guard let imageCaptureDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .depthData, position: .unspecified),
              let deviceInput = try? AVCaptureDeviceInput(device: imageCaptureDevice) else {
            fatalError("Unable to access the TrueDepth camera.")
        }
        
        // Add input and output to the capture session
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
        }
        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        captureSession.commitConfiguration()
        
        photoOutput.isDepthDataDeliveryEnabled = true
        
        // Set up the preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Add the preview layer to your UIView for camera preview
        let previewContainerView = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300)) // Adjust the frame as needed
        previewContainerView.layer.insertSublayer(previewLayer, at: 0)
        view.addSubview(previewContainerView)
        previewLayer.frame = previewContainerView.bounds
        
        // Create the circular capture button
        captureButton = UIButton(type: .system)
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 30 // Adjust the corner radius to change the size of the button
        captureButton.layer.borderWidth = 2
        captureButton.layer.borderColor = UIColor.blue.cgColor // Adjust the color of the ring
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        view.addSubview(captureButton)
        
        // Add constraints to position the button at the bottom center with padding
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20), // Adjust the padding as needed
            captureButton.widthAnchor.constraint(equalToConstant: 60), // Adjust the width and height to change the size of the button
            captureButton.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        // Create the circular export button
        exportButton = UIButton(type: .system)
        exportButton.backgroundColor = .white
        exportButton.layer.cornerRadius = 30 // Adjust the corner radius to change the size of the button
        exportButton.layer.borderWidth = 2
        exportButton.layer.borderColor = UIColor.green.cgColor // Adjust the color of the ring
        exportButton.setTitle("Export", for: .normal)
        exportButton.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)
        view.addSubview(exportButton)
        
        // Add constraints to position the export button at the bottom left with padding
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            exportButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), // Adjust the padding as needed
            exportButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20), // Adjust the padding as needed
            exportButton.widthAnchor.constraint(equalToConstant: 100), // Adjust the width and height to change the size of the button
            exportButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureSession.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }
    
    @objc func captureButtonTapped() {
        // Handle the capture button tap here
        capturePhoto()
    }
    
    @objc func exportButtonTapped() {
        exportDocumentsFolderAsZip()
    }
    
    
    // Function to capture the photo using AVCapturePhotoOutput
    func capturePhoto() {
        // Create an AVCapturePhotoSettings instance with depth data delivery enabled
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isDepthDataDeliveryEnabled = true
        photoSettings.isDepthDataFiltered = true
        
        // Capture the photo with the specified settings and set the delegate to handle the result
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
        
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            printItemsInDirectory(directoryURL: documentsDirectory)
        }
    }
    
    func printItemsInDirectory(directoryURL: URL) {
        let fileManager = FileManager.default
        
        do {
            let directoryContents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [])
            
            print("Items in directory \(directoryURL.path):")
            for itemURL in directoryContents {
                print(itemURL.lastPathComponent)
            }
        } catch {
            print("Error reading directory: \(error)")
        }
    }
    
}

import ZipArchive
import MobileCoreServices

extension ScanViewController {
    func exportDocumentsFolderAsZip() {
        let fileManager = FileManager.default
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let zipFileName = "Documents.zip"
        let zipFilePath = documentsDirectory.appendingPathComponent(zipFileName)
        
        // Check if the zip file already exists and remove it if it does
        if fileManager.fileExists(atPath: zipFilePath.path) {
            try? fileManager.removeItem(at: zipFilePath)
        }
        
        // Create a zip file containing all the contents of the Documents folder
        SSZipArchive.createZipFile(atPath: zipFilePath.path, withContentsOfDirectory: documentsDirectory.path)
        
        // Save the zip file to the Files app
        let activityViewController = UIActivityViewController(activityItems: [zipFilePath], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { _, _, _, _ in
            // Delete the temporary zip file after the export is completed or canceled
            try? fileManager.removeItem(at: zipFilePath)
        }
        
        // You can present the activityViewController to the user to export the zip file.
        // For example:
        self.present(activityViewController, animated: true, completion: nil)
    }
}


extension ScanViewController {
    // Function to export the current frame's image and depth data as .bin files
    func exportImageAndDepthData(image: UIImage, depthData: [[Float32]]) {
        guard let imageData = image.pngData() else {
            print("Error converting image to data.")
            return
        }
        
        let depthDataArray = depthData.flatMap { $0 }
        let depthDataBuffer = UnsafeBufferPointer(start: depthDataArray, count: depthDataArray.count)
        let depthDataNSData = NSData(bytes: depthDataBuffer.baseAddress, length: depthDataBuffer.count * MemoryLayout<Float32>.size)
        
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let depthFileName = "depth\(String(format: "%02d", depthFileCounter)).bin"
            let videoFileName = "video\(String(format: "%02d", videoFileCounter)).bin"
            
            let imageFileURL = documentsDirectory.appendingPathComponent(videoFileName)
            let depthDataFileURL = documentsDirectory.appendingPathComponent(depthFileName)
            
            do {
                try imageData.write(to: imageFileURL)
                depthDataNSData.write(to: depthDataFileURL, atomically: true)
                print("Image and depth data exported successfully.")
            } catch {
                print("Error exporting image and depth data: \(error)")
            }
            
            depthFileCounter += 1
            videoFileCounter += 1
        }
    }
}

extension ScanViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let imageData = photo.fileDataRepresentation(),
           let image = UIImage(data: imageData),
           let depthData = photo.depthData {
            let convertedDepthMap = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
            
            // Call the export function to save the image and depth data as .bin files
            exportImageAndDepthData(image: image, depthData: convertDepthData(depthMap: convertedDepthMap))
        } else {
            print("Error capturing photo or depth data.")
        }
    }
    
    func wrapEstimateImageData(
        depthMap: CVPixelBuffer,
        calibration: AVCameraCalibrationData) -> Data {
            let jsonDict: [String : Any] = [
                "calibration_data" : [
                    "intrinsic_matrix" : (0 ..< 3).map{ x in
                        (0 ..< 3).map{ y in calibration.intrinsicMatrix[x][y]}
                    },
                    "pixel_size" : calibration.pixelSize,
                    "intrinsic_matrix_reference_dimensions" : [
                        calibration.intrinsicMatrixReferenceDimensions.width,
                        calibration.intrinsicMatrixReferenceDimensions.height
                    ],
                    "lens_distortion_center" : [
                        calibration.lensDistortionCenter.x,
                        calibration.lensDistortionCenter.y
                    ],
                    "lens_distortion_lookup_table" : convertLensDistortionLookupTable(
                        lookupTable: calibration.lensDistortionLookupTable!
                    ),
                    "inverse_lens_distortion_lookup_table" : convertLensDistortionLookupTable(
                        lookupTable: calibration.inverseLensDistortionLookupTable!
                    )
                ],
                "depth_data" : convertDepthData(depthMap: depthMap)
            ]
            let jsonStringData = try! JSONSerialization.data(
                withJSONObject: jsonDict,
                options: .prettyPrinted
            )
            return jsonStringData
        }
    
    func convertLensDistortionLookupTable(lookupTable: Data) -> [Float] {
        let tableLength = lookupTable.count / MemoryLayout<Float>.size
        var floatArray: [Float] = Array(repeating: 0, count: tableLength)
        _ = floatArray.withUnsafeMutableBytes{lookupTable.copyBytes(to: $0)}
        return floatArray
    }
    
    func convertDepthData(depthMap: CVPixelBuffer) -> [[Float32]] {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        var convertedDepthMap: [[Float32]] = Array(
            repeating: Array(repeating: 0, count: width),
            count: height
        )
        CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 2))
        let floatBuffer = unsafeBitCast(
            CVPixelBufferGetBaseAddress(depthMap),
            to: UnsafeMutablePointer<Float32>.self
        )
        for row in 0 ..< height {
            for col in 0 ..< width {
                convertedDepthMap[row][col] = floatBuffer[width * row + col]
            }
        }
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 2))
        return convertedDepthMap
    }
}
