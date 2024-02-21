//
//  ExportView.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import SwiftUI
import Lottie

enum CurrentState {
    case prescan
    case scan
    case postscan
}

struct ShareSheet: UIViewControllerRepresentable {
    var fileURL: URL
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FlashButtonView: View {
    @Binding var isFlashOn: Bool
    
    var body: some View {
        Button(action: toggleFlash) {
            Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                .foregroundColor(isFlashOn ? .black : .gray)
                .font(.title)
        }
        .padding(.top)
    }
    
    private func toggleFlash() {
        HapticManager.playHapticFeedback(type: .error)
        isFlashOn.toggle()
        // Update camera flash setting here
    }
}

enum HeadTurnState {
    
                                    if lastLog.contains("Converting") {
                                        LottieView(animationFileName: "face-id-2", loopMode: .loop)
                                            .frame(width: 60, height: 60)
                                            .opacity(0.5)
                                            .scaleEffect(0.5)
                                            .padding(.top)
                                    }
                                    
                                    
                                    if lastLog.contains("Done") {
                                        LottieView(animationFileName: "face-found-successfully", loopMode: .playOnce)
                                            .frame(width: 60, height: 60)
                                            .scaleEffect(0.5)
                                            .opacity(0.5)
                                    }
                                }
                            }
                        }
                        .onDisappear {
                            logManager.stopTimer()
                        }
                        
                    } else if headTurnMessage != "" {
                        ScrollView {
                            Text(headTurnMessage)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .monospaced()
                        }
                        
                    } else {
                        ScrollView {
                            Text("PUPIL DISTANCE\n\(String(format: "%.1f", faceTrackingViewModel.pupilDistance)) mm")
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .monospaced()
                        }
                    }
                    
                    if showArrow {
                        if headTurnState == .left {
                            // Display a large arrow pointing to the direction the user should turn their head
                            if isFlashOn {
                                LottieView(animationFileName: "left-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                                
                            } else {
                                LottieView(animationFileName: "left-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .colorInvert()
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                            }
                            
                        } else if headTurnState == .right {
                            // Display a large arrow pointing to the direction the user should turn their head
                            if isFlashOn {
                                LottieView(animationFileName: "right-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                                
                            } else {
                                LottieView(animationFileName: "right-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .colorInvert()
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                            }
                            
                        }
                    }

                    Spacer()
                    
                    // Button to start/pause scanning
                    if !isRingAnimationStarted {
                        Button(action: {
                            if !isButtonDisabled {
                                // Temporary addition to prevent previous scans from showinwg up...
                                OpticALLYApp.clearDocumentsFolder()
                                // REMOVE ABOVE LINE IN PRODUCTION!
                                
                                HapticManager.playHapticFeedback(type: .success)
                                headTurnMessage = "TURN YOUR HEAD\nLEFT/RIGHT"
                                isRingAnimationStarted = true  // Start the ring animation
                                startButtonPressed = true
                            }
                        }) {
                            if showConsoleOutput {
                                if let lastLog = logManager.latestLog {
                                    if lastLog.lowercased().contains("done") {
                                        VStack {
                                            Button(action: {
                                                globalState.currentView = .postScanning
                                            }) {
                                                VStack {
                                                    Image(systemName: "ruler")
                                                        .font(.title)
                                                    
                                                    Text("Measure")
                                                        .font(.body)
                                                        .bold()
                                                }
                                                .padding()
                                                .foregroundColor(.white)
                                                .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                                            }
                                        }
                                        .padding()
                                    } else {
                                        HStack {
                                            Image(systemName: "circle.dotted") // Different SF Symbols for start and pause
                                            Text("Processing")
                                                .bold()
                                                .onAppear() {
                                                    isButtonDisabled = true
                                                }
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                                    }
                                }
                            } else {
                                VStack(spacing: 5) {
                                    Text("Start")
                                        .font(.title3)
                                        .bold()
                                        .onAppear() {
                                            isButtonDisabled = false
                                        }
                                    
                                    Image(systemName: "arrow.up")
                                        .font(.largeTitle) // Adjust the size of the icon
                                }
                                .foregroundColor(.white) // Text and icon color
                                .padding() // Padding around VStack
                                .background(Capsule().fill(Color.black)) // Capsule shape filled with black color
                                .overlay(
                                    Capsule().stroke(Color.white, lineWidth: 2) // White border around the capsule
                                )
                            }
                        }
                        .padding(.bottom)
                    }
                }
            }
        }
        .padding()
        .foregroundColor(isFlashOn ? .black : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Setting the frame size to infinity
        .ignoresSafeArea()
    }
}
