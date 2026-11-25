// Draws the logmo app icon at 1024 x 1024: a blue square with a white check above four rising bars.
// Proportions were measured from the supplied logo sheet. Run from the repo root:
//   swiftc tools/make-app-icon.swift -o /tmp/make-app-icon && /tmp/make-app-icon logmo/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// iOS rounds the corners itself, so the artwork is a full-bleed square with no transparency.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// Everything below is in fractions of the icon, y measured from the top.
func X(_ f: CGFloat) -> CGFloat { f * s }
func Y(_ f: CGFloat) -> CGFloat { s - f * s }          // CoreGraphics' origin is bottom-left

ctx.setFillColor(CGColor(srgbRed: 2 / 255, green: 94 / 255, blue: 246 / 255, alpha: 1))   // #025EF6
ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
let bars: [(x0: CGFloat, x1: CGFloat, top: CGFloat)] = [
    (0.165, 0.294, 0.641), (0.337, 0.467, 0.544), (0.510, 0.639, 0.436), (0.678, 0.812, 0.309),
]
let bottom: CGFloat = 0.764
for b in bars {
    let rect = CGRect(x: X(b.x0), y: Y(bottom), width: X(b.x1 - b.x0), height: X(bottom - b.top))
    let r = rect.width * 0.38
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()
}

ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(X(0.086))
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: X(0.259), y: Y(0.328)))
ctx.addLine(to: CGPoint(x: X(0.340), y: Y(0.409)))
ctx.addLine(to: CGPoint(x: X(0.502), y: Y(0.248)))
ctx.strokePath()

let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest), "could not write the icon")
print("wrote \(out.path)")
