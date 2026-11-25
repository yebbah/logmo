import SwiftUI

/// The first screen: the logo and the version, shown for three seconds, then faded away to reveal the Dashboard.
struct LandingView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            // Logo, name and tagline are one block, centred together a little above the middle.
            VStack(spacing: 18) {
                LogoMark(size: 132)
                VStack(spacing: 6) {
                    Text("logmo").font(.system(size: 40, weight: .heavy, design: .rounded))
                    Text("Track progress with clarity").font(.subheadline).foregroundStyle(theme.muted)
                }
            }
            .offset(y: -40)
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
