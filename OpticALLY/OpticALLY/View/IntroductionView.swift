import SwiftUI
import AVKit

struct TextOverlayView: View {
    @EnvironmentObject var globalState: GlobalState

    var body: some View {
        VStack {
            VStack {
                Text("HAROLDEN")
                    .font(.system(size: 48, weight: .bold))
                    .monospaced()
                    .cornerRadius(10)

                Text("3D CAPTURE")
                    .font(.title)
            }
            .padding()

            Button(action: {
                globalState.currentView = .scanning
            }) {
                HStack {
                    Image(systemName: "eyeglasses")
                    Text("EXPLORE")
                        .font(.body)
                        .bold()
                }
                .foregroundColor(.white)
                .padding()
                .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
            }
            .padding(.bottom)
        }
        .background(Color(.black))
        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 10)))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }
}

struct BackgroundVideoPlayer: UIViewControllerRepresentable {
    var videoName: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        setupPlayer(for: playerViewController, with: videoName, playMuted: false)
        return playerViewController
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // This function can be used for future updates if needed
    }

    private func setupPlayer(for playerViewController: AVPlayerViewController, with videoName: String, playMuted: Bool) {
        if let fileURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            let player = AVPlayer(url: fileURL)
            playerViewController.player = player
            playerViewController.showsPlaybackControls = false
            playerViewController.videoGravity = .resizeAspectFill
            playerViewController.player?.isMuted = playMuted
            playerViewController.player?.play()
        }
    }
}

struct IntroductionView: View {
    @State private var playSecondVideo = false

    var body: some View {
        ZStack {
            BackgroundVideoPlayer(videoName: "glasses")
                .overlay(
                    TextOverlayView(), // Overlay view
                    alignment: .center
                )
                .edgesIgnoringSafeArea(.all)
        }
        .animation(.easeInOut, value: playSecondVideo)
    }
}

struct TitleView: View {
    var body: some View {
        VStack {
            Text("HAROLDEN")
                .font(.system(size: 48, weight: .bold))
                .monospaced()
                .cornerRadius(10)
            
            Text("LOS ANGELES")
                .font(.title)
        }
        .foregroundStyle(.black)
    }
}

struct IntroductionView_Previews: PreviewProvider {
    static var previews: some View {
        IntroductionView()
            .environmentObject(GlobalState())
            .preferredColorScheme(.dark)
    }
}
