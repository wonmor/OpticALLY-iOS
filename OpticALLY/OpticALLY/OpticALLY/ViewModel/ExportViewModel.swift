//
//  ExportViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import Foundation
import Firebase

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
    @Published var showShareSheet = false
    @Published var isLoading = false
    @Published var estimatedExportTime: Int? = nil
    
    @Published var hasTurnedRight = false
    @Published var hasTurnedLeft = false
    @Published var hasTurnedCenter = false
    
    private var exportStartTime: Date?
    
    func reset(completion: @escaping () -> Void) {
        fileURL = nil
        showShareSheet = false
        isLoading = false
        estimatedExportTime = nil
        hasTurnedRight = false
        hasTurnedLeft = false
        
        completion()
    }
    
    func fetchExportDurations() {
        let db = Firestore.firestore()
        db.collection("misc").document("render_time").getDocument { [weak self] (document, error) in
            if let document = document, document.exists {
                if let durations = document.data()?["obj_duration"] as? [Int], !durations.isEmpty {
                    self?.estimatedExportTime = self?.calculateAverage(durations: durations)
                } else {
                    // Handle the case where array doesn't exist or is empty
                    self?.estimatedExportTime = nil // No data available
                }
            } else {
                // Handle the case where document doesn't exist
                self?.estimatedExportTime = nil // No data available
            }
        }
    }
    
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
    
    func updateExportDurationInFirestore(newDuration: Int) {
        let db = Firestore.firestore()
        let docRef = db.collection("misc").document("render_time")
        
        docRef.getDocument { (document, error) in
            var durations: [Int]
            
            if let document = document, document.exists, let existingDurations = document.data()?["obj_duration"] as? [Int] {
                durations = existingDurations
                if durations.count >= 20 {
                    durations.removeFirst() // Remove the oldest entry
                }
            } else {
                // Document does not exist, start a new array
                durations = []
            }
            
            durations.append(newDuration) // Add the new duration
            
            // Set the new array to the document, creating it if necessary
            docRef.setData(["obj_duration": durations], merge: true)
        }
    }
    
    func exportAV_PLY(showShareSheet: Bool) {
        // Determine a temporary file URL to save the PLY file
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("model.ply")
        
        // Export the PLY data to the file
        ExternalData.exportAV_GeometryAsPLY(to: fileURL)
        
        // Update the state to indicate that there's a file to share
        DispatchQueue.main.async {
            self.fileURL = fileURL
            self.showShareSheet = showShareSheet
        }
    }
    
    func exportPLY(showShareSheet: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Determine a temporary file URL to save the ZIP file
            let tempDirectory = FileManager.default.temporaryDirectory
            let zipFileURL = tempDirectory.appendingPathComponent("model.zip")
            
            // Export the PLY data to multiple files and compress them into a ZIP file
            ExternalData.exportGeometryAsPLY(to: zipFileURL)
            
            // Update the state to indicate that there's a file to share
            DispatchQueue.main.async {
                self.fileURL = zipFileURL
                self.showShareSheet = showShareSheet
            }
        }
    }
    
    func exportOBJ() {
        fetchExportDurations()

        // Start the export timer
        startExportTimer()

        // Export the PLY data to the file
        let tempDirectory = FileManager.default.temporaryDirectory
        let plyFileURL = tempDirectory.appendingPathComponent("model.ply")
        ExternalData.exportAV_GeometryAsPLY(to: plyFileURL)

        // Update the state to indicate that there's a file to share
        DispatchQueue.main.async {
            self.isLoading = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Use convertToObj to convert PLY to OBJ
                let objFileURL = try OpticALLYApp.convertToObj(fileURL: plyFileURL)

                // Update the state with the OBJ file URL and stop loading
                DispatchQueue.main.async {
                    self.fileURL = objFileURL
                    self.showShareSheet = true
                    self.isLoading = false

                    // Stop the export timer and update the duration in Firestore
                    let exportDuration = self.stopExportTimer()
                    self.updateExportDurationInFirestore(newDuration: exportDuration)
                }
            } catch {
                print("Error converting PLY to OBJ: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}
