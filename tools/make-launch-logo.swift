// Draws the logo mark (rounded blue square, white check above four rising bars) on a transparent
// background for the launch screen, at 2x and 3x of a 132-point image. Run from the repo root:
//   swiftc tools/make-launch-logo.swift -o /tmp/make-launch-logo && /tmp/make-launch-logo logmo/Assets.xcassets/LaunchLogo.imageset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func draw(size: Int, to url: URL) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size)
    func X(_ f: CGFloat) -> CGFloat { f * s }
    func Y(_ f: CGFloat) -> CGFloat { s - f * s }
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerWidth: s * 0.225, cornerHeight: s * 0.225, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 2 / 255, green: 94 / 255, blue: 246 / 255, alpha: 1))
    ctx.fillPath()
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    for b in [(0.165, 0.294, 0.641), (0.337, 0.467, 0.544), (0.510, 0.639, 0.436), (0.678, 0.812, 0.309)] as [(CGFloat, CGFloat, CGFloat)] {
        let r = CGRect(x: X(b.0), y: Y(0.764), width: X(b.1 - b.0), height: X(0.764 - b.2))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.38, cornerHeight: r.width * 0.38, transform: nil))
        ctx.fillPath()
    }
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(X(0.086)); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: X(0.259), y: Y(0.328)))
    ctx.addLine(to: CGPoint(x: X(0.340), y: Y(0.409)))
    ctx.addLine(to: CGPoint(x: X(0.502), y: Y(0.248)))
    ctx.strokePath()
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest))
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
draw(size: 264, to: dir.appendingPathComponent("LaunchLogo@2x.png"))
draw(size: 396, to: dir.appendingPathComponent("LaunchLogo@3x.png"))
print("wrote launch logos to \(dir.path)")
