//
//  FilesListView.swift
//  OpticALLY
//
//  Created by John Seong on 2/4/24.
//

import SwiftUI

struct FilesListView: View {
    @ObservedObject var viewModel = FilesViewModel()
    @State private var selectedFolder: FileItem?
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("3D Face Models")) {
                    ForEach(viewModel.faceModels) { item in
                        FileRow(item: item) {
                            self.selectedFolder = item
                        }
                    }
                }

                Section(header: Text("RGB-D Raw Data")) {
                    ForEach(viewModel.rawDatas) { item in
                        FileRow(item: item) {
                            self.selectedFolder = item
                        }
                    }
                }
            }
            .onAppear {
                viewModel.loadFiles() // Load files when the view appears
            }
        }
        .sheet(item: $selectedFolder) { folder in
            FolderDetailView(folderName: folder.name, files: listFilesInFolder(folder.name))
        }
    }

    func listFilesInFolder(_ folderName: String) -> [String] {
        var fileNames: [String] = []
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Documents directory not found")
            return fileNames
        }

        let folderURL = documentsDirectory.appendingPathComponent(folderName)

        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            fileNames = fileURLs.map { $0.lastPathComponent }
        } catch {
            print("Error reading contents of directory: \(error)")
        }

        return fileNames
    }
}


struct FileRow: View {
    let item: FileItem
    var onTap: () -> Void  // Closure to handle tap action

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title(for: item.type))
                        .font(.headline)
                    Text(item.date, style: .date)
                        .font(.subheadline)
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
            }
            .padding()
        }
    }
    
    private func title(for type: FileItem.FileType) -> String {
        switch type {
        case .faceModel:
            return "PLY & OBJ Export"
        case .rawData:
            return "BIN & JSON Cache"
        }
    }
}
