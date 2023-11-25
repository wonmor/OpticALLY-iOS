//
//  ExportViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import Foundation
import Firebase

// ViewModel to handle the export and share
class ExportViewModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var showShareSheet = false
    @Published var isLoading = false
    @Published var estimatedExportTime: Int? = nil
    
    private var exportStartTime: Date?
    
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
    
    func exportUSDZ() {
        // Determine a temporary file URL to save the PLY file
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("model.usdz")
        
        // Export the PLY data to the file
        ExternalData.exportGeometryAsUSDZ(to: fileURL)
        
        // Update the state to indicate that there's a file to share
        DispatchQueue.main.async {
            self.fileURL = fileURL
            self.showShareSheet = true
        }
    }
    
    func exportOBJ() {
        fetchExportDurations()
        
        // Start the export timer
        startExportTimer()
        
        // Convert to PLY and get the file URL
        // Determine a temporary file URL to save the PLY file
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("model.ply")
        
        // Export the PLY data to the file
        ExternalData.exportGeometryAsPLY(to: fileURL)
        
        // Update the state to indicate that there's a file to share
        DispatchQueue.main.async {
            guard let plyFileURL: URL? = fileURL else {
                print("Failed to get PLY file URL")
                return
            }
            
            // Start loading
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            // Prepare the request
            let url = URL(string: "https://harolden-server.apps.johnseong.com/convert-to-obj/")! // Replace with your actual API URL
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            // Create a multipart form data body
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var data = Data()
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"file\"; filename=\"model.ply\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            data.append(try! Data(contentsOf: plyFileURL!))
            data.append("\r\n".data(using: .utf8)!)
            data.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Upload the file
            let task = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
                DispatchQueue.main.async {
                    self.isLoading = false // Stop loading
                    if let error = error {
                        print("Error: \(error)")
                        return
                    }
                    
                    guard let data = data else {
                        print("No data received")
                        return
                    }
                    
                    print("Received .OBJ file...")
                    
                    // Save the OBJ file to a temporary location
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let objFileURL = tempDirectory.appendingPathComponent("model.obj")
                    do {
                        try data.write(to: objFileURL)
                        self.fileURL = objFileURL
                        self.showShareSheet = true
                        
                        // Stop the export timer and update the duration in Firestore
                        let exportDuration = self.stopExportTimer()
                        self.updateExportDurationInFirestore(newDuration: exportDuration)
                    } catch {
                        print("Error saving OBJ file: \(error)")
                    }
                }
            }
            task.resume()
        }
    }
}
