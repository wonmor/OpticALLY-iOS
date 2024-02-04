//
//  FilesListView.swift
//  OpticALLY
//
//  Created by John Seong on 2/4/24.
//

import SwiftUI

struct FilesListView: View {
    @ObservedObject var viewModel = FilesViewModel()

    var body: some View {
        List {
            Section(header: Text("3D Face Models")) {
                ForEach(viewModel.faceModels) { item in
                    FileRow(item: item)
                }
            }

            Section(header: Text("RGB-D Raw Data")) {
                ForEach(viewModel.rawDatas) { item in
                    FileRow(item: item)
                }
            }
        }
        .onAppear {
            viewModel.loadFiles()
        }
    }
}

struct FileRow: View {
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading) {
            Text(title(for: item.type))
                .font(.headline)
            Text(item.date, style: .date)
                .font(.subheadline)
        }
        .padding()
        // Add tap gesture or navigation link here
    }
    
    private func title(for type: FileItem.FileType) -> String {
        switch type {
        case .faceModel:
            return "PLY & OBJ Export"
        case .rawData:
            return "BIN & JSON Dump"
        }
    }
}
