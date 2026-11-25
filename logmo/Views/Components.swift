import SwiftUI

// MARK: - Card

struct Card<Content: View, Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let trailing: Trailing
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border, lineWidth: 1))
    }
}

extension Card where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Status icon, info popover

struct StatusIcon: View {
    @Environment(\.theme) private var theme
    let ok: Bool?
    var body: some View {
        Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "circle")
            .foregroundStyle(ok == true ? theme.good : ok == false ? theme.bad : theme.muted)
    }
}

/// A small "i" that shows a short explanation in a popover when tapped.
struct InfoButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(theme.accent)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $shown) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding().frame(width: 270, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Full-screen landscape charts

/// Which orientations the app currently allows. Portrait everywhere except a full-screen chart.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

@MainActor
func setOrientation(_ mask: UIInterfaceOrientationMask) {
    OrientationLock.mask = mask
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
}

struct ExpandButton: View {
    @Environment(\.theme) private var theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 14))
                .foregroundStyle(theme.accent).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open full screen")
    }
}

/// Full-screen cover that turns the phone to landscape while it is open and back after.
extension View {
    func landscapeCover<Full: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Full) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: { setOrientation(.portrait) }) {
            content().onAppear { setOrientation(.landscape) }
        }
    }

    /// A fixed height, or all the room there is when nil.
    @ViewBuilder func chartHeight(_ h: CGFloat?) -> some View {
        if let h { frame(height: h) } else { frame(maxHeight: .infinity) }
    }
}

struct FullScreenFrame<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(theme.muted)
                }
                .accessibilityLabel("Close full screen")
                Text(title).font(.headline)
                Spacer()
            }
            content
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg.ignoresSafeArea())
    }
}

/// Closes the keyboard from anywhere.
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// Lets the keyboard always be put away: dragging the form down closes it, and a Done button sits above it. Number pads have no
    /// Return key, so without this there is no way to close them.
    func keyboardDismissible() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissKeyboard() } } }
    }
}
