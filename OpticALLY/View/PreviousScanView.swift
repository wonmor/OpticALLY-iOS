//
//  PreviousScanView.swift
//  OpticALLY
//
//  Created by John Seong on 2/3/24.
//

import SwiftUI

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
    
    // Define common styling
    private let foregroundColor = Color.white
    private let backgroundColor = Color.black
    private let commonFont = Font.system(.subheadline).monospaced()
    
    var body: some View {
        VStack {
            Spacer()
            
            // Title
            Text("PREVIOUS SCANS")
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
            
            // Credit Lines
            VStack(alignment: .center, spacing: 20) {
                PreviousScanCreditView(title: "Product Manager", name: "Drew Shepard")
                PreviousScanCreditView(title: "Developer", name: "John Seong")
                PreviousScanCreditView(title: "Consultant", name: "Shawn Patridge")
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(20)
            
            // Button
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

struct PreviousScanCreditView: View {
    var title: String
    var name: String
    
    var body: some View {
        VStack {
            Text(title)
                .bold()
                .font(Font.system(.subheadline).monospaced())
                .foregroundColor(.white)
            Text(name)
                .foregroundColor(.white)
        }
        .multilineTextAlignment(.center)
    }
}
