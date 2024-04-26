import SwiftUI

struct CountdownTimerView: View {
    @State private var remainingTime = 120 // 120 seconds for 2 minutes
    @State private var timer: Timer?

    var body: some View {
        Text(timeString(time: remainingTime))
            .font(.largeTitle) // Customize the font as needed
            .foregroundColor(.white) // Customize the text color as needed
            .padding()
            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height, alignment: .center)
            .onAppear {
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
    }

    // Helper function to format time as minutes and seconds
    func timeString(time: Int) -> String {
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // Function to start the timer
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { tempTimer in
            if self.remainingTime > 0 {
                self.remainingTime -= 1
            } else {
                self.stopTimer()
                // Perform any actions when timer finishes
            }
        }
    }

    // Function to stop the timer
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
