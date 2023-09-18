//
//  IntroductionView.swift
//  ClassFinder
//
//  Created by John Seong on 8/22/23.
//

import SwiftUI

struct IntroductionView: View {
    @Binding var currentView: ViewState  // Add this binding
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                Spacer()
                TitleView()
                InformationContainerView()
                Spacer(minLength: 30)
                
                Button(action: {
                    currentView = .tracking
                }) {
                    Text("Continue")
                        .customButton()
                }
                .padding(.horizontal)
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
                .customTitleText()
            
            Text("OpticALLY")
                .customTitleText()
                .foregroundColor(.mainColor)
        }
    }
}

struct InformationContainerView: View {
    var body: some View {
        VStack(alignment: .leading) {
            InformationDetailView(title: "3D Facial Scanning", subTitle: "Get a precise 3D model of your face using our AR technology.", imageName: "face.dashed")
            
            InformationDetailView(title: "Pupillary Distance", subTitle: "Accurately measure your pupillary distance for a perfect fit.", imageName: "ruler.fill")
            
            InformationDetailView(title: "Custom Eyewear", subTitle: "Tailor eyewear based on your face's unique dimensions.", imageName: "eyeglasses")
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
                    .foregroundColor(.mainColor)
                    .accessibility(hidden: true)
                
                // This displays the label (if it exists) next to the image
                if let label = backgroundLabel {
                    Text(label)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.pink)
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
