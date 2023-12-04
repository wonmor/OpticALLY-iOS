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
            
            VStack {
                Text("OPTICALLY")
                    .font(.title)
                
                Text("3D CAPTURE")
                    .font(.title)
                    .font(.system(size: 48, weight: .bold))
                    .monospaced()
            }
            .foregroundStyle(.black)
            .padding(.horizontal)
            .padding(.bottom)
            
            // Credit Lines
            VStack(alignment: .center, spacing: 20) {
                CreditLine(title: "Product Manager", name: "Drew Shepard")
                CreditLine(title: "Developer", name: "John Seong")
                CreditLine(title: "Consultant", name: "Shawn Patridge")
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

struct CreditsView_Previews: PreviewProvider {
    @State static var showingCreditsDummy = true
    
    static var previews: some View {
        CreditsView(showingCredits: $showingCreditsDummy)
            .environmentObject(GlobalState())
            .preferredColorScheme(.dark)
    }
}
