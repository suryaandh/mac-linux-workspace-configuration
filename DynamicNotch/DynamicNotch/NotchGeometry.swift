import Foundation
import CoreGraphics

struct NotchGeometry {
    static func collapsedRect(screen: CGRect, left: CGRect?, right: CGRect?, topInset: CGFloat) -> CGRect {
        if let left, let right, topInset > 0, right.minX > left.maxX {
            return CGRect(x: left.maxX, y: screen.maxY - topInset,
                          width: right.minX - left.maxX, height: topInset)
        }
        // A compact virtual notch for displays without a camera cutout.
        return CGRect(x: screen.midX - 85, y: screen.maxY - 24, width: 170, height: 24)
    }
}
