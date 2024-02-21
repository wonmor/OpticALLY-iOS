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
    
    @State private var isAnimating = false
    @State private var isComplete = false // Temporary value...
    @State private var isFaceDetected = true // Temporary value...

    var body: some View {
        ZStack {
            ARViewContainer(arSessionDelegate: cameraViewController)
                .clipShape(Circle())
                .frame(width: 200, height: 200)
            
            Circle()
                .trim(from: 0, to: CGFloat(100))
                .stroke(Color.green, lineWidth: 5)
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(isFaceDetected ? 360 : 0))
                .onAppear {
                    withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                        isAnimating.toggle()
                    }
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
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arSessionDelegate: CameraViewController

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = arSessionDelegate
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { }
}
