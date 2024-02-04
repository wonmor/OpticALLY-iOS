//
//  FileItem.swift
//  OpticALLY
//
//  Created by John Seong on 2/4/24.
//

import Foundation

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
    let type: FileType

    enum FileType {
        case faceModel
        case rawData
    }
}

