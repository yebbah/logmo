import SwiftUI

/// The first screen: the logo and the version, shown for three seconds, then faded away to reveal the Dashboard.
struct LandingView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            LogoMark(size: 132)                                   // exactly centred, like the launch screen before it
            VStack(spacing: 6) {
                Text("logmo").font(.system(size: 40, weight: .heavy, design: .rounded))
                Text("Track progress with clarity").font(.subheadline).foregroundStyle(theme.muted)
            }
            .offset(y: 132 / 2 + 52)
            VStack {
                Spacer()
                Text("Version \(AppInfo.versionString)").font(.footnote).foregroundStyle(theme.muted)
                    .padding(.bottom, 40)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("logmo, version \(AppInfo.versionString)")
    }
}
