//
//  ContentView.swift
//  SignalStrengthView
//
//  Created by John Seong on 3/25/24.
//

import SwiftUI

struct SignalStrengthView: View {
    var body: some View {
        ZStack {
            HStack(spacing: -225) {
                ForEach(0..<5) { index in
                    SignalArc(index: index)
                }
                
            }
            
            HStack(spacing: -225) {
                ForEach(0..<5) { index in
                    SignalArc(index: index)
                }
            }
            .scaleEffect(x: -1, y: 1)
        }
    }
}

struct SignalArc: View {
    let index: Int
    
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
            .stroke(.gray, lineWidth: 2)
        }
    }
}
