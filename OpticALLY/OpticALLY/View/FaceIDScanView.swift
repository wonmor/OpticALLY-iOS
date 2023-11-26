//
//  FaceIDScanView.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import SwiftUI

struct FaceIDScanView: View {
    @Binding var isScanComplete: Bool
    @Binding var showDropdown: Bool
    
    @State private var isAnimating: Bool = false
    @StateObject private var cameraDelegate = CameraDelegate()
    
    var body: some View {
        ZStack {
            CameraPreview(session: $cameraDelegate.session)
                .clipShape(Circle())
                .frame(width: 200, height: 200)
            
            Circle()
                .trim(from: 0, to: CGFloat(cameraDelegate.rotationPercentage))
                .stroke(Color.green, lineWidth: 5)
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(cameraDelegate.isFaceDetected ? 360 : 0))
                .onAppear {
                    withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                        isAnimating.toggle()
                    }
                }
            
            if !cameraDelegate.isFaceDetected {
                Image(systemName: "face.dashed")
                    .foregroundColor(.white)
                    .font(.system(size: 75))
                    .background(Color.black.opacity(0.8).blur(radius: 20.0))
            }
            
            // Draw face landmarks
            ForEach(cameraDelegate.faceLandmarks, id: \.self) { face in
                Path { path in
                    if let leftEye: CGPoint? = face.leftEyePosition {
                        path.addEllipse(in: CGRect(x: leftEye!.x - 5, y: leftEye!.y - 5, width: 10, height: 10))
                    }
                    if let rightEye: CGPoint? = face.rightEyePosition {
                        path.addEllipse(in: CGRect(x: rightEye!.x - 5, y: rightEye!.y - 5, width: 10, height: 10))
                    }
                    // Add more landmarks as needed
                }
                .stroke(Color.green, lineWidth: 2)
            }
            
            // Display face shape
            if !showDropdown {
                VStack {
                    Text(cameraDelegate.faceShape?.rawValue ?? "Determining")
                        .foregroundColor(.white)
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("FACE PROFILE")
                        .bold()
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
        }
        .onAppear(perform: cameraDelegate.setupCamera)
        .padding(.bottom)
    }
}
