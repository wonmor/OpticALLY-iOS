import SwiftUI

struct FaceIDScanView: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            CameraPreview(session: .constant(AVCaptureSession()))
                .clipShape(Circle())
                .frame(width: 200, height: 200)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, lineWidth: 5)
                .frame(width: 200, height: 200)
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        progress = 1
                    }
                }
        }
        .padding(.bottom)
    }
}

