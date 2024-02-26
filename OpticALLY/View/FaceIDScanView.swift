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
    
    @Binding var showFaceIdLoading: Bool
    @Binding var showFaceIdSuccessful: Bool

    var body: some View {
        ZStack {
            if showFaceIdLoading {
                LottieView(animationFileName: "face-id-2", loopMode: .loop)
                    .frame(width: 60, height: 60)
                    .opacity(0.5)
                    .scaleEffect(0.5)
                    .padding(.top)
                
            } else if showFaceIdSuccessful {
                LottieView(animationFileName: "face-found-successfully", loopMode: .playOnce)
                    .frame(width: 60, height: 60)
                    .scaleEffect(0.5)
                    .opacity(0.5)
            }
            
            // Display the captured image
            if let image = cameraViewController.currentImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(90))
                    .blur(radius: showFaceIdLoading || showFaceIdSuccessful ? 20 : 0)
                
            } else {
                ARViewContainer(arSessionDelegate: cameraViewController)
                    .clipShape(Circle())
                    .frame(width: 200, height: 200)
                    .blur(radius: showFaceIdLoading || showFaceIdSuccessful ? 20 : 0)
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
