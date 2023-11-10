//
//  IntroductionView.swift
//  ClassFinder
//
//  Created by John Seong on 8/22/23.
//

import SwiftUI
import AVKit

struct BackgroundVideoPlayer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        
        // Assuming the video is in the app's resources bundle.
        if let fileURL = Bundle.main.url(forResource: "promo", withExtension: "mp4") {
            let player = AVPlayer(url: fileURL)
            playerViewController.player = player
            playerViewController.showsPlaybackControls = false
            playerViewController.videoGravity = .resizeAspectFill
            playerViewController.player?.isMuted = true
            playerViewController.player?.play()
            playerViewController.player?.actionAtItemEnd = .none
            
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerViewController.player?.currentItem, queue: .main) { _ in
                playerViewController.player?.seek(to: CMTime.zero)
                playerViewController.player?.play()
            }
        }
        
        return playerViewController
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

struct IntroductionView: View {
    @EnvironmentObject var globalState: GlobalState
    
    var body: some View {
        ZStack {
            // Background video player
            BackgroundVideoPlayer()
                .opacity(0.25)
                .edgesIgnoringSafeArea(.all)
            
            // All your other views go here
            ScrollView {
                VStack(alignment: .center) {
                    Spacer()
                    TitleView()
                    InformationContainerView()
                    Spacer(minLength: 30)
                    
                    Button(action: {
                        withAnimation {
                            globalState.currentView = .tracking
                        }
                    }) {
                        Text("Continue")
                            .customButton()
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct TitleView: View {
    var body: some View {
        VStack {
            Image("1024")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 20)) // Clips the image as a rounded rectangle
                .overlay(
                    RoundedRectangle(cornerRadius: 20) // Applies a border on top of the rounded rectangle image
                        .stroke(Color.primary, lineWidth: 2) // Adjust the color and line width as needed
                )
                .accessibility(hidden: true)
            
            Text("Welcome to")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.mainColor)
                .monospaced()
            
            Text("Harolden")
                .font(.system(size: 36, weight: .bold))
                .monospaced()
        }
    }
}

struct InformationContainerView: View {
    var body: some View {
        VStack(alignment: .leading) {
            InformationDetailView(title: "Custom Eyewear", subTitle: "Tailor eyewear based on your face's unique dimensions.", imageName: "eyeglasses")
            
            InformationDetailView(title: "3D Facial Scanning", subTitle: "Get a precise 3D model of your face using our AR technology.", imageName: "face.dashed")
            
            InformationDetailView(title: "Pupillary Distance", subTitle: "Accurately measure your pupillary distance for a perfect fit.", imageName: "ruler.fill")
        }
        .padding(.horizontal)
    }
}


struct InformationDetailView: View {
    var title: String = "title"
    var subTitle: String = "subTitle"
    var imageName: String = "car"
    var backgroundLabel: String? = nil  // Optional background label property
    
    var body: some View {
        HStack(alignment: .center) {
            // Container for the image and the label (if it exists)
            VStack(spacing: 10) {
                Image(systemName: imageName)
                    .font(.largeTitle)
                    .accessibility(hidden: true)
                
                // This displays the label (if it exists) next to the image
                if let label = backgroundLabel {
                    Text(label)
                        .font(.caption)
                        .bold()
                        .foregroundColor(.mainColor)
                        .padding(5)
                        .background(Color.pink.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .accessibility(addTraits: .isHeader)
                
                Text(subTitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top)
    }
}
