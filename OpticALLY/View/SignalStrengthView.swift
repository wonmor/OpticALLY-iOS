//
//  ContentView.swift
//  SignalStrengthView
//
//  Created by John Seong on 3/25/24.
//

import SwiftUI

struct SignalStrengthView: View {
    @Binding var scanState: ScanState
    @Binding var scanDirection: ScanDirection
    
    @ObservedObject var cameraViewController: CameraViewController
    
    private func determineActive1(scanState: ScanState, scanDirection: ScanDirection) -> Int {
        if scanState == .scanning {
            switch scanDirection {
            case .left:
                let delta = abs(20 - cameraViewController.faceYawAngle)
                
                print("Delta left: \(delta)")
                
                if delta >= 14 {
                    return 3
                    
                } else if delta >= 11 {
                    return 2
                    
                } else if delta >= 9 {
                    return 1
                    
                } else if delta >= 6 {
                    return 0
                }
                
            case .right where cameraViewController.faceYawAngle < -20:
                return -1
                
            default:
                return -1
            }
        }
        
        return -1
            
    }
    
    private func determineActive2(scanState: ScanState, scanDirection: ScanDirection) -> Int {
        if scanState == .scanning {
            switch scanDirection {
            case .left where cameraViewController.faceYawAngle > 20:
                return -1
                
            case .right where cameraViewController.faceYawAngle < -20:
                let delta = abs(cameraViewController.faceYawAngle - 20)
                
                print("Delta right: \(delta)")
                
                if delta >= 14 {
                    return 3
                    
                } else if delta >= 11 {
                    return 2
                    
                } else if delta >= 9 {
                    return 1
                    
                } else if delta >= 6 {
                    return 0
                }
                
            default:
                return -1
            }
        }
        
        return -1
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: -225) {
                ForEach(0..<5) { index in
                    if index <= determineActive1(scanState: scanState, scanDirection: scanDirection) {
                        SignalArc(index: index, isActive: true)
                        
                    } else {
                        SignalArc(index: index, isActive: false)
                    }
                }
                
            }
            
            HStack(spacing: -225) {
                ForEach(0..<5) { index in
                    if index <= determineActive2(scanState: scanState, scanDirection: scanDirection) {
                        SignalArc(index: index, isActive: true)
                        
                    } else {
                        SignalArc(index: index, isActive: false)
                    }
                }
            }
            .scaleEffect(x: -1, y: 1)
        }
    }
}

struct SignalArc: View {
    let index: Int
    let isActive: Bool
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let arcWidth = width / 10 // width of each arc
                
                let arcStart = width * CGFloat(index) / 5 // start of arc
                
                path.addArc(
                    center: CGPoint(x: width / 2, y: height / 2),
                    radius: height / 2,
                    startAngle: Angle(degrees: Double(180 - index * 15)),
                    endAngle: Angle(degrees: Double(180 + index * 15)),
                    clockwise: false
                )
            }
            .stroke(isActive ? .green : .gray, lineWidth: 2)
        }
    }
}
