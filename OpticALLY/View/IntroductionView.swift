import SwiftUI
import AVKit

struct TextOverlayView: View {
    @EnvironmentObject var globalState: GlobalState
    
    @State private var showingCredits = false
    @State private var showingPreviousScanView = false
    
    var body: some View {
        VStack {
            Image("1024")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, alignment: .center)
                .accessibility(hidden: true)
                .padding(.top)
            
            VStack {
                Text("OPTICALLY")
                    .bold()
                    .monospaced()
                    .cornerRadius(10)
                
                Text("3D CAPTURE")
                    .font(.title)
            }
            .padding(.horizontal)
            
            Button(action: {
                globalState.currentView = .scanning
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Scan")
                        .font(.body)
                        .bold()
                }
                .foregroundColor(.white)
                .padding()
                .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
            }
            .padding(.bottom)
            
            Button(action: {
               showingCredits.toggle()
           }) {
               Text("CREDITS")
                   .font(.footnote)
                   .monospaced()
                   .bold()
           }
           .padding(.bottom)
           .sheet(isPresented: $showingCredits) {
               CreditsView(showingCredits: $showingCredits)
            }
           .padding(.bottom)
            
            Button(action: {
                showingPreviousScanView.toggle()
            }) {
                Text("PREVIOUS SCANS")
                    .font(.footnote)
                    .monospaced()
                    .bold()
                    .foregroundColor(.black) // Set text color to black
                    .padding()
                    .background(Capsule() // Use RoundedRectangle for rounded corners
                        .fill(Color.white)) // Set the background to white
            }
            .padding(.bottom)
            .sheet(isPresented: $showingPreviousScanView) {
                PreviousScanView(showingCredits: $showingPreviousScanView)
            }
}
        .background(Color(.black))
        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 10)))
        .shadow(color: .black, radius: 10, x: 5, y: 5)
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
