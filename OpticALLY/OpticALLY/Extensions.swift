//
//  Extensions.swift
//  OpticALLY
//
//  Created by John Seong on 9/11/23.
//

import Foundation
import SceneKit
import simd

extension Array where Element == SIMD3<Float> {
    init(unsafeData: Data, count: Int) {
        self = []
        self.reserveCapacity(count)
        for i in 0..<count {
            let start = Data.Index(i * MemoryLayout<SIMD3<Float>>.stride)
            let end = start + MemoryLayout<SIMD3<Float>>.stride
            let element = unsafeData.subdata(in: start..<end).withUnsafeBytes { $0.load(as: SIMD3<Float>.self) }
            self.append(element)
        }
    }
}

extension SCNVector3 {
    func magnitude() -> Float {
        return sqrt(x*x + y*y + z*z)
    }
    
    static func dot(_ v1: SCNVector3, _ v2: SCNVector3) -> Float {
        return (v1.x * v2.x) + (v1.y * v2.y) + (v1.z * v2.z)
    }
    
    static func subtractVectors(_ left: SCNVector3, _ right: SCNVector3) -> SCNVector3 {
        return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
    }
}

extension Collection where Element == CGFloat, Index == Int {
    /// Return the mean of a list of CGFloat. Used with `recentVirtualObjectDistances`.
    var average: CGFloat? {
        guard !isEmpty else {
            return nil
        }
        
        let sum = reduce(CGFloat(0)) { current, next -> CGFloat in
            return current + next
        }
        
        return sum / CGFloat(count)
    }
}

extension CGPoint {
    // Multiply CGPoint by a scalar
    static func * (left: CGPoint, right: CGFloat) -> CGPoint {
        return CGPoint(x: left.x * right, y: left.y * right)
    }
    
    // Multiply CGPoint by another CGPoint (element-wise multiplication)
    static func * (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x * right.x, y: left.y * right.y)
    }
}
