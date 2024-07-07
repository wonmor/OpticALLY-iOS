import SwiftUI

struct CreditsView: View {
    @Binding var showingCredits: Bool
    
    private let player = AVPlayer(url: Bundle.main.url(forResource: "promo", withExtension: "mp4")!)
    
    var body: some View {
        ZStack {
            Color.white
            
            BackgroundVideoPlayer(videoName: "promo")
                .opacity(0.35)
                .overlay(CreditNestedView(showingCredits: $showingCredits),
                         alignment: .center
                )
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct CreditNestedView: View {
    @Binding var showingCredits: Bool
    
    // Define common styling
    private let foregroundColor = Color.white
    private let backgroundColor = Color.black
    private let commonFont = Font.system(.subheadline).monospaced()
    
    var body: some View {
        VStack {
            Spacer()
            
            // Title
            Text("CREDITS")
                .bold()
                .font(commonFont)
                .foregroundColor(foregroundColor)
                .padding()
                .background(backgroundColor)
                .cornerRadius(20)
            
            // Python interpolated
            Text("Dlib Version 19.24.4")
                .monospaced()
                .padding(.horizontal)
                .padding(.top)
                .foregroundStyle(.black)
                .font(.caption)
                .bold()
            
            // Python interpolated
            Text("Open3D Version\n\(o3d!.__version__.description)")
                .monospaced()
                .padding(.horizontal)
                .padding(.top)
                .foregroundStyle(.black)
                .font(.caption)
                .bold()
            
            Text(OpenCVWrapper.getOpenCVVersion())
                .monospaced()
                .padding(.horizontal)
                .padding(.top)
                .foregroundStyle(.black)
                .font(.caption)
                .bold()
            
            Text(EigenWrapper.eigenVersionString())
                .monospaced()
                .padding(.horizontal)
                .padding(.top)
                .foregroundStyle(.black)
                .font(.caption)
                .bold()
            
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
                CreditLine(title: "PRODUCT MANAGER", name: "Drew Shepard")
                CreditLine(title: "DEVELOPER", name: "John Seong")
                CreditLine(title: "CONSULTANT", name: "Shawn Patridge")
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

struct CreditLine: View {
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
