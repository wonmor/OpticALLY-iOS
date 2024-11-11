//
//  PreviousScanView.swift
//  OpticALLY
//
//  Created by John Seong on 2/3/24.
//

import SwiftUI
import AVKit

struct PreviousScanView: View {
    @Binding var showingCredits: Bool
    
    private let player = AVPlayer(url: Bundle.main.url(forResource: "promo", withExtension: "mp4")!)
    
    var body: some View {
        ZStack {
            Color.white
            
            BackgroundVideoPlayer(videoName: "promo")
                .opacity(0.35)
                .overlay(PreviousScanNestedView(showingCredits: $showingCredits),
                         alignment: .center
                )
        }
        .edgesIgnoringSafeArea(.all)
        .colorInvert()
    }
}

struct PreviousScanNestedView: View {
    @Binding var showingCredits: Bool
    
    private let foregroundColor = Color.white
    private let backgroundColor = Color.black
    private let commonFont = Font.system(.subheadline).monospaced()
    
    var body: some View {
        VStack {
            Spacer()
            
            // Title
            Text("PRIVACY POLICY")
                .bold()
                .font(commonFont)
                .foregroundColor(foregroundColor)
                .padding()
                .background(backgroundColor)
                .cornerRadius(20)
           
            VStack {
                Text("OPTICALLY")
                    .monospaced()
                    .cornerRadius(10)
                
                Text("3D CAPTURE")
                    .font(.title)
            }
            .foregroundStyle(.black)
            .padding()
            .bold()
            
            // Privacy Policy Details
            VStack(alignment: .leading) {
                Text("Every 3D scan is processed LOCALLY ON DEVICE.")
                    .font(.system(size: 18.0, weight: .bold, design: .rounded))
                
                Text("NO data is collected or stored.\nNo scans are processed on cloud servers, ensuring complete privacy.")
                    .padding(.top, 10)
                    .font(.system(size: 18.0, weight: .bold, design: .rounded))
                    .opacity(0.5)
                
                Text("ALL data remains on your device and is discarded when the app is closed.\nYour privacy is our priority.")
                    .padding(.top, 5)
                    .font(.system(size: 18.0, weight: .bold, design: .rounded))
                    .opacity(0.5)
            }
            .multilineTextAlignment(.leading)
            .padding()
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(20)
            .padding(.bottom)
            
            // Confirm Button
            Button(action: {
                withAnimation {
                    showingCredits = false
                }
            }) {
                Text("CONFIRM")
                    .fontWeight(.bold)
                    .font(commonFont)
                    .foregroundColor(.black)
                    .padding()
                    .background(Capsule().fill(.white).overlay(Capsule().stroke(.black, lineWidth: 2)))
            }
            .padding(.bottom)
            
            Spacer()
        }
        .padding()
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }
}
