import Foundation
import CoreGraphics

@main
struct NotchGeometryChecks {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NotchGeometry.collapsedRect(
            screen: screen,
            left: CGRect(x: 0, y: 950, width: 666, height: 32),
            right: CGRect(x: 846, y: 950, width: 666, height: 32), topInset: 32)
        precondition(notch == CGRect(x: 666, y: 950, width: 180, height: 32))
        precondition(notch.contains(CGPoint(x: 756, y: 966)))
        precondition(!notch.contains(CGPoint(x: 665, y: 966)))
        precondition(!notch.contains(CGPoint(x: 847, y: 966)))
        precondition(!notch.contains(CGPoint(x: 756, y: 949)))
        let external = NotchGeometry.collapsedRect(screen: CGRect(x: -1920, y: 200, width: 1920, height: 1080), left: nil, right: nil, topInset: 0)
        precondition(external == CGRect(x: -1045, y: 1256, width: 170, height: 24))
        print("Notch geometry checks passed: physical bounds, outside edges, external display")
    }
}
