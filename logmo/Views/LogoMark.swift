import SwiftUI

/// The logmo mark: a blue rounded square with a white check above four rising bars.
/// Drawn from the same proportions as the app icon (tools/make-app-icon.swift).
struct LogoMark: View {
    var size: CGFloat = 56

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: s * 0.225),
                     with: .color(Color(hex: 0x025EF6)))
            let bars: [(CGFloat, CGFloat, CGFloat)] = [(0.165, 0.294, 0.641), (0.337, 0.467, 0.544),
                                                      (0.510, 0.639, 0.436), (0.678, 0.812, 0.309)]
            for (x0, x1, top) in bars {
                let r = CGRect(x: x0 * s, y: top * s, width: (x1 - x0) * s, height: (0.764 - top) * s)
                ctx.fill(Path(roundedRect: r, cornerRadius: r.width * 0.38), with: .color(.white))
            }
            var check = Path()
            check.move(to: CGPoint(x: 0.259 * s, y: 0.328 * s))
            check.addLine(to: CGPoint(x: 0.340 * s, y: 0.409 * s))
            check.addLine(to: CGPoint(x: 0.502 * s, y: 0.248 * s))
            ctx.stroke(check, with: .color(.white),
                       style: StrokeStyle(lineWidth: 0.086 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
