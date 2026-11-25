import SwiftUI

/// A tinted card with a message and one to three buttons. Used for the setup, finished-campaign
/// and similar nudges so they look alike.
struct PromptCard: View {
    @Environment(\.theme) private var theme
    struct Action: Identifiable { let id = UUID(); var title: String; var filled = false; var run: () -> Void }

    var tint: Color
    var icon: String
    var title: String
    var text: String
    var steps: [(String, Bool)] = []          // optional checklist: title, done
    var actions: [Action]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(text).font(.subheadline).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                        Label(s.0, systemImage: s.1 ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline).foregroundStyle(s.1 ? theme.good : Color.primary)
                    }
                }
            }
            HStack(spacing: 12) {
                ForEach(actions) { a in
                    Button(action: a.run) {
                        Text(a.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 24).padding(.vertical, 12).padding(.horizontal, 8)
                            .foregroundStyle(a.filled ? theme.onAccent : theme.accent)
                            .background(a.filled ? theme.accent : theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
    }
}
