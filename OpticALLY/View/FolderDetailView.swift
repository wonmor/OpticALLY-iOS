//
//  FolderDetailView.swift
//  OpticALLY
//
//  Created by John Seong on 2/4/24.
//

import SwiftUI

struct FolderDetailView: View {
    var folderName: String
    var files: [String]  // Assuming you have a way to list these files

    var body: some View {
        List {
            if let sceneKitPreviewURL = files.first(where: { $0.contains("combined_face_scan.obj") || $0.contains("single_face_scan.obj") }) {
                SceneKitPreview(url: URL(fileURLWithPath: sceneKitPreviewURL))
                    .frame(height: 200)
            }

            ForEach(files, id: \.self) { file in
                Text(displayName(for: file))
            }
        }
        .navigationTitle(folderName)
    }

    private func displayName(for file: String) -> String {
        let baseName = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension.uppercased()
        switch baseName {
        case "single_face_scan":
            return "Single Face Scan - \(ext)"
        case "combined_face_scan":
            return "Full Head Scan - \(ext)"
        case "landmark_3dmm":
            return "Landmark 3DMM - ZIP"
        default:
            return "\(baseName) - \(ext)"
        }
    }
}
