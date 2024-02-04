//
//  FileViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 2/4/24.
//

import Foundation

class FilesViewModel: ObservableObject {
    @Published var faceModels: [FileItem] = []
    @Published var rawDatas: [FileItem] = []

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd"
        return formatter
    }()

    func loadFiles() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        do {
            let items = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)

            for item in items {
                if item.lastPathComponent.starts(with: "ply_obj_") {
                    let dateString = String(item.lastPathComponent.dropFirst("ply_obj_".count))
                    if let date = dateFormatter.date(from: dateString) {
                        faceModels.append(FileItem(name: item.lastPathComponent, date: date, type: .faceModel))
                    }
                } else if item.lastPathComponent.starts(with: "bin_json_") {
                    let dateString = String(item.lastPathComponent.dropFirst("bin_json_".count))
                    if let date = dateFormatter.date(from: dateString) {
                        rawDatas.append(FileItem(name: item.lastPathComponent, date: date, type: .rawData))
                    }
                }
            }

            // Sort the arrays by date in descending order so the latest scans are at the top
            faceModels.sort { $0.date > $1.date }
            rawDatas.sort { $0.date > $1.date }
        } catch {
            print("Error loading files: \(error)")
        }
    }
}
