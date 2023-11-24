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
                
                Text("LOS ANGELES")
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
                .background(Capsule().fill(Color.black))
            }
            .padding(.bottom)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 10)))
        .foregroundStyle(.black)
    }
}

struct BackgroundVideoPlayer: UIViewControllerRepresentable {
    var firstVideoName: String
    var secondVideoName: String
    @Binding var playSecondVideo: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        setupPlayer(for: playerViewController, with: firstVideoName, playMuted: false)

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerViewController.player?.currentItem, queue: .main) { _ in
            withAnimation {
                if !self.playSecondVideo {
                    self.playSecondVideo = true
                }
                self.setupPlayer(for: playerViewController, with: self.secondVideoName, playMuted: true)
            }
        }

        return playerViewController
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if playSecondVideo {
            setupPlayer(for: uiViewController, with: secondVideoName, playMuted: true)
        }
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
            BackgroundVideoPlayer(firstVideoName: "glasses", secondVideoName: "promo", playSecondVideo: $playSecondVideo)
                .opacity(playSecondVideo ? 0.5 : 0.8)
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
