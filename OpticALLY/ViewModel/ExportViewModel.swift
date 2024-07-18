//
//  ExportViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import Foundation
import PythonKit
import PythonSupport
import LinkPython

/// ExportViewModel handles the export and sharing functionality for 3D models. It is designed as a ViewModel for SwiftUI-based UI components and manages various properties and methods related to exporting models and tracking export durations.

/// - Properties:
/// - fileURL: The URL of the exported model file.
/// - showShareSheet: A flag indicating whether to display the share sheet for sharing the exported model.
/// - isLoading: A flag indicating whether an export operation is currently in progress.
/// - estimatedExportTime: An estimate of the time it takes to export a model.
/// - hasTurnedRight: A boolean flag indicating if a right turn has been made.
/// - hasTurnedLeft: A boolean flag indicating if a left turn has been made.
/// - exportStartTime: A private property to record the start time of the export timer.

/// - Methods:
/// - fetchExportDurations(): Fetches export durations from Firestore and calculates an average export time.
/// - calculateAverage(durations:): Calculates the average of an array of export durations.
/// - startExportTimer(): Starts the export timer by recording the current time.
/// - stopExportTimer(): Stops the export timer and returns the elapsed time in seconds.
/// - updateExportDurationInFirestore(newDuration:): Updates export durations in Firestore.
/// - exportPLY(showShareSheet:): Exports a model as a PLY file and optionally shows the share sheet.
/// - exportOBJ(): Exports a model as a PLY file, converts it to OBJ format, and handles the export process.

/// ExportViewModel is a crucial component for managing the export and sharing of 3D models, and it provides functionality to estimate export times, update export durations, and initiate export operations. It can be integrated into SwiftUI-based applications that require 3D model export and sharing capabilities.

class ExportViewModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var fileURLForViewer: URL?
    @Published var showShareSheet = false
    @Published var isLoading = false
    @Published var estimatedExportTime: Int? = nil
    
    @Published var hasTurnedRight = false
    @Published var hasTurnedLeft = false
    @Published var hasTurnedCenter = false
    
    @Published var objURLs: [String]?
    @Published var objURL: URL?
    
    private var exportStartTime: Date?
    private var tstate: UnsafeMutableRawPointer?
    
    func reset(completion: @escaping () -> Void) {
        fileURL = nil
        fileURLForViewer = nil
        showShareSheet = false
        isLoading = false
        estimatedExportTime = nil
        hasTurnedRight = false
        hasTurnedLeft = false
        
        completion()
    }
    
//    func fetchExportDurations() {
//        let db = Firestore.firestore()
//        db.collection("misc").document("render_time").getDocument { [weak self] (document, error) in
//            if let document = document, document.exists {
//                if let durations = document.data()?["obj_duration"] as? [Int], !durations.isEmpty {
//                    self?.estimatedExportTime = self?.calculateAverage(durations: durations)
//                } else {
//                    // Handle the case where array doesn't exist or is empty
//                    self?.estimatedExportTime = nil // No data available
//                }
//            } else {
//                // Handle the case where document doesn't exist
//                self?.estimatedExportTime = nil // No data available
//            }
//        }
//    }
    
    private func calculateAverage(durations: [Int]) -> Int {
        return durations.reduce(0, +) / durations.count
    }
    
    func startExportTimer() {
        exportStartTime = Date()
    }
    
    func stopExportTimer() -> Int {
        guard let startTime = exportStartTime else { return 0 }
        let duration = Date().timeIntervalSince(startTime)
        return Int(duration)
    }
    
    func exportPLY(showShareSheet: Bool) {
        // Determine a temporary file URL to save the PLY file
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("model.ply")
        
        // Export the PLY data to the file
        ExternalData.exportGeometryAsPLY(to: fileURL)
        
        // Update the state to indicate that there's a file to share
        DispatchQueue.main.async {
            self.fileURL = fileURL
            self.showShareSheet = showShareSheet
        }
    }
    
    func exportCombinedModel(showShareSheet: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let gstate = PyGILState_Ensure()
            
          defer {
              DispatchQueue.main.async {
                  guard let tstate = self.tstate else { fatalError() }
                  PyEval_RestoreThread(tstate)
                  self.tstate = nil
              }
              PyGILState_Release(gstate)
          }
            // Determine a temporary file URL to save the ZIP file
            let tempDirectory = FileManager.default.temporaryDirectory
//            let zipFileURL = tempDirectory.appendingPathComponent("model.zip")
//            
//            // Export the PLY data to multiple files and compress them into a ZIP file
//            ExternalData.exportGeometryAsPLY(to: zipFileURL)
            
            let plyFileURL = tempDirectory.appendingPathComponent("combined.ply")
            
            ExternalData.exportUsingMultiwayRegistrationAsPLY(to: plyFileURL)
            
            // Update the state to indicate that there's a file to share
            DispatchQueue.main.async {
                // self.fileURL = zipFileURL
                self.fileURL = plyFileURL
                self.showShareSheet = showShareSheet
            }
        }
        
        tstate = PyEval_SaveThread()
    }
    
    func exportOBJ() {
        if OpticALLYApp.isConnectedToNetwork() {
            // Fetch previous export durations to estimate the current export time
            // fetchExportDurations()
            
            // Start the export timer to measure the duration of the export process
            startExportTimer()
        }

        // Indicate the start of the export process
        DispatchQueue.main.async {
            self.isLoading = true
        }

        // Perform the export and conversion operations asynchronously to avoid blocking the UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Define the initial file URL for the PLY file
            let tempDirectory = FileManager.default.temporaryDirectory
            let plyFileURL = tempDirectory.appendingPathComponent("model.ply")

            do {
                let gstate = PyGILState_Ensure()
                
              defer {
                  DispatchQueue.main.async {
                      guard let tstate = self.tstate else { fatalError() }
                      PyEval_RestoreThread(tstate)
                      self.tstate = nil
                  }
                  PyGILState_Release(gstate)
              }
                // Call convertToObj, which now handles both PLY export and OBJ conversion
                let objFileURL = try OpticALLYApp.ballPivotingSurfaceReconstruction_PLYtoOBJ(fileURL: plyFileURL)

                // Update the UI with the results of the export process
                DispatchQueue.main.async {
                    // Update the state with the new OBJ file URL
                    self.fileURL = objFileURL
                    // Indicate that the file is ready to be shared
                    self.showShareSheet = true
                    // Mark the export process as completed
                    self.isLoading = false

                    if OpticALLYApp.isConnectedToNetwork() {
                        // Stop the export timer and record the duration of the export process
                        let exportDuration = self.stopExportTimer()
                        // Update the Firestore database with the new export duration
                        // self.updateExportDurationInFirestore(newDuration: exportDuration)
                    }
                    
                    do {
                        let objData = try Data(contentsOf: objFileURL)
                        ExternalData.saveSingleScan(data: objData, fileExtension: "obj")
                        
                    } catch {
                        print("Error reading back OBJ data: \(error)")
                    }
                }
            } catch {
                // Handle any errors that occurred during the export process
                print("Error during PLY to OBJ conversion: \(error)")
                DispatchQueue.main.async {
                    // Mark the export process as completed, even if it ended in error
                    self.isLoading = false
                }
            }
        }
        
        tstate = PyEval_SaveThread()
    }
}
