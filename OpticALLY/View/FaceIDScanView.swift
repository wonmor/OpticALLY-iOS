//
//  FaceIDScanView.swift
//  OpticALLY
//
//  Created by John Seong on 2/21/24.
//

import SwiftUI
import ARKit

struct FaceIDScanView: View {
    @Binding var isScanComplete: Bool
    @ObservedObject var cameraViewController: CameraViewController // Make sure this is an ObservableObject
    
    @State private var isAnimating = false
    @State private var isComplete = false // Temporary value...
    @State private var isFaceDetected = true // Temporary value...

    var body: some View {
        ZStack {
            // Display the captured image
            if let image = cameraViewController.currentImage {
                Image(uiImage: image)
                    .resizable()
                    .clipShape(Circle())
                    .frame(width: 200, height: 200)
            } else {
                ARViewContainer(arSessionDelegate: cameraViewController)
                    .clipShape(Circle())
                    .frame(width: 200, height: 200)
            }

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 50))
                    .background(Color.black.opacity(0.8).blur(radius: 20.0))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isScanComplete = true
                        }
                    }
                    
            } else if !isFaceDetected {
                Image(systemName: "face.dashed")
                    .foregroundColor(.white)
                    .font(.system(size: 75))
                    .background(Color.black.opacity(0.8).blur(radius: 20.0))
            }
        }
        .onAppear {
            cameraViewController.arSCNView = ARSCNView()
            cameraViewController.arSCNView?.session.delegate = cameraViewController
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arSessionDelegate: CameraViewController

    func makeUIView(context: Context) -> ARSCNView {
        let view = arSessionDelegate.arSCNView
        view!.session.delegate = arSessionDelegate
        return view!
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { }
}
