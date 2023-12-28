//
//  Extensions+Modifiers.swift
//  ClassFinder
//
//  Created by John Seong on 8/22/23.
//

import Foundation
import SwiftUI
import SceneKit
import ARKit
import simd

func += (left: inout SCNVector3, right: SCNVector3) {
    left = SCNVector3(left.x + right.x, left.y + right.y, left.z + right.z)
}

extension PointCloudMetadata {
    func scaled(scaleX: Float, scaleY: Float, scaleZ: Float) -> PointCloudMetadata {
        return PointCloudMetadata(
            yaw: self.yaw, // Assuming yaw, pitch, roll don't need scaling
            pitch: self.pitch,
            roll: self.roll,
            leftEyePosition: self.leftEyePosition, // Assuming 2D positions don't need scaling
            rightEyePosition: self.rightEyePosition,
            chinPosition: self.chinPosition,
            leftEyePosition3D: SCNVector3(self.leftEyePosition3D.x * scaleX, self.leftEyePosition3D.y * scaleY, self.leftEyePosition3D.z * scaleZ),
            rightEyePosition3D: SCNVector3(self.rightEyePosition3D.x * scaleX, self.rightEyePosition3D.y * scaleY, self.rightEyePosition3D.z * scaleZ),
            chinPosition3D: SCNVector3(self.chinPosition3D.x * scaleX, self.chinPosition3D.y * scaleY, self.chinPosition3D.z * scaleZ),
            image: self.image, // Assuming image and depth are not scaled here
            depth: self.depth
        )
    }
}

extension ARSession {
    // Returns the original capturedImage from the current frame
    func getCapturedImage() -> CVPixelBuffer? {
        return self.currentFrame?.capturedImage
    }
    
    // Returns a resized and transformed version of the capturedImage
    func getTransformedCapturedImage(resizedTo size: CGSize, in viewController: UIViewController) -> CVPixelBuffer? {
        guard let frame = self.currentFrame else { return nil }
        let imageBuffer = frame.capturedImage
        let imageSize = CGSize(width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))
        let interfaceOrientation = viewController.view.window?.windowScene?.interfaceOrientation ?? .portrait
        let image = CIImage(cvImageBuffer: imageBuffer)
        let normalizeTransform = CGAffineTransform(scaleX: 1.0 / imageSize.width, y: 1.0 / imageSize.height)
        let displayTransform = frame.displayTransform(for: interfaceOrientation, viewportSize: size)
        let toViewPortTransform = CGAffineTransform(scaleX: size.width, y: size.height)
        let transformedImage = image.transformed(by: normalizeTransform.concatenating(displayTransform).concatenating(toViewPortTransform))
        
        let context = CIContext(options: nil)
        var newPixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes as CFDictionary, &newPixelBuffer)
        
        guard let pixelBuffer = newPixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0)) }
        context.render(transformedImage, to: pixelBuffer)
        
        return pixelBuffer
    }
}

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

// Extension to add cross and dot product functionality to SCNVector3
extension SCNVector3 {
    func cross(_ v: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            x: self.y * v.z - self.z * v.y,
            y: self.z * v.x - self.x * v.z,
            z: self.x * v.y - self.y * v.x
        )
    }
    
    func dot(_ v: SCNVector3) -> Float {
        return self.x * v.x + self.y * v.y + self.z * v.z
    }
    
    func length() -> Float {
        return sqrt(self.dot(self))
    }
    
    func normalized() -> SCNVector3 {
        let len = self.length()
        return len > 0 ? self / len : SCNVector3(0, 0, 0)
    }
}

// Implement division of SCNVector3 by a scalar
func / (vector: SCNVector3, scalar: Float) -> SCNVector3 {
    return SCNVector3(vector.x / scalar, vector.y / scalar, vector.z / scalar)
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


struct ButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.black)
            .font(.headline)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.mainColor))
            .padding(.bottom)
    }
}

struct ButtonStyle: ViewModifier {
    //MARK:- PROPERTIES
    let buttonHeight: CGFloat
    let buttonColor: Color
    let buttonRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(buttonColor)
            .cornerRadius(buttonRadius)
    }
}
struct CustomTextM: ViewModifier {
    //MARK:- PROPERTIES
    let fontName: String
    let fontSize: CGFloat
    let fontColor: Color
    
    func body(content: Content) -> some View {
        content
            .font(.custom(fontName, size: fontSize))
            .foregroundColor(fontColor)
    }
}

struct CustomTextfield: View {
    //MARK:- PROPERTIES
    var placeholder: Text
    var fontName: String
    var fontSize: CGFloat
    var fontColor: Color
    var foregroundColor: Color?
    
    @Binding var username: String
    var editingChanged: (Bool)->() = { _ in }
    var commit: ()->() = { }
    
    var body: some View {
        ZStack(alignment: .leading) {
            if username.isEmpty { placeholder.modifier(CustomTextM(fontName: fontName, fontSize: fontSize, fontColor: fontColor)) }
            TextField("", text: $username, onEditingChanged: editingChanged, onCommit: commit).foregroundColor((foregroundColor != nil) ?  foregroundColor : Color.primary)
                .autocapitalization(.none)
        }
    }
}

struct CustomSecureField: View {
    //MARK:- PROPERTIES
    var placeholder: Text
    var fontName: String
    var fontSize: CGFloat
    var fontColor: Color
    
    @Binding var password: String
    var editingChanged: (Bool)->() = { _ in }
    var commit: ()->() = { }
    
    var body: some View {
        ZStack(alignment: .leading) {
            if password.isEmpty { placeholder.modifier(CustomTextM(fontName: fontName, fontSize: fontSize, fontColor: fontColor)) }
            SecureField("", text: $password, onCommit: commit)
                .foregroundColor(.white)
                .autocapitalization(.none)
        }
    }
}

extension UIApplication {
    func hideKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    func customButton() -> ModifiedContent<Self, ButtonModifier> {
        return modifier(ButtonModifier())
    }
}

extension Color {
    static var mainColor = Color(UIColor.systemGray)
    static var subColor = Color(UIColor.systemYellow)
}

extension Data {
    func toArray<T>(type: T.Type, count: Int) -> [T] {
        return withUnsafeBytes { (pointer) -> [T] in
            let bufferPointer = pointer.bindMemory(to: T.self)
            guard let address = bufferPointer.baseAddress else { return [] }
            return Array(UnsafeBufferPointer(start: address, count: count))
        }
    }
    
    func toFloatArray() -> [Float] {
        var array = [Float](repeating: 0.0, count: self.count / MemoryLayout<Float>.size)
        self.withUnsafeBytes {
            array = UnsafeBufferPointer<Float>(start: $0.bindMemory(to: Float.self).baseAddress, count: array.count).map { $0 }
        }
        return array
    }
    
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
