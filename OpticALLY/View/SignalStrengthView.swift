//
//  ContentView.swift
//  SignalStrengthView
//
//  Created by John Seong on 3/25/24.
//

import SwiftUI

struct SignalStrengthView: View {
    @Binding var scanDirection: ScanDirection
    
    @ObservedObject var cameraViewController: CameraViewController
    
    private func determineActive1() -> Int {
        switch scanDirection {
        case .left:
            let diff = abs(20 - cameraViewController.faceYawAngle)
            
            if diff >= 15 {
                return 0
                
            } else if diff >= 10 {
                return 1
                
            } else if diff >= 5 {
                return 2
                
            } else if diff >= 2.5 {
                return 3
            }
            
        case .front where abs(cameraViewController.faceYawAngle) < 10:
            return -1
            
        case .right where cameraViewController.faceYawAngle < -20:
            return -1
            
        default:
            return -1
        }
        
        return -1
    }
    
    private func determineActive2() -> Int {
        switch scanDirection {
        case .left where cameraViewController.faceYawAngle > 20:
            return -1
            
        case .front where abs(cameraViewController.faceYawAngle) < 10:
            let diff = abs(0 - cameraViewController.faceYawAngle)
            
            if diff >= 15 {
                return 0
                
            } else if diff >= 10 {
                return 1
                
            } else if diff >= 5 {
                return 2
                
            } else if diff >= 2.5 {
                return 3
            }
            
        case .right where cameraViewController.faceYawAngle < -20:
            let diff = abs(-20 - cameraViewController.faceYawAngle)
            
            if diff >= 15 {
                return 0
                
            } else if diff >= 10 {
                return 1
                
            } else if diff >= 5 {
                return 2
                
            } else if diff >= 2.5 {
                return 3
            }
            
        default:
            return -1
        }
        
        return -1
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: -225) {
                ForEach(0..<5) { index in
                    if index <= determineActive1() {
                        SignalArc(index: index, isActive: true)
                        
                    } else {
                        SignalArc(index: index, isActive: false)
                    }
                }
                
            }
            
            HStack(spacing: -225) {
                ForEach(0..<5) { index in
                    if index <= determineActive2() {
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
