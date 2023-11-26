import SwiftUI

struct FaceIDScanView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var progress: CGFloat = 0
    @State private var strokeColor: Color = .white

    var body: some View {
        ZStack {
            CameraPreview(session: $cameraManager.session)
                .clipShape(Circle())
                .frame(width: 200, height: 200)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(strokeColor, lineWidth: 5)
                .frame(width: 200, height: 200)
                .onAppear {
                    withAnimation(.linear(duration: 10)) {
                        progress = 1
                        strokeColor = .green
                    }
                }
        }
        .padding()
    }
}
