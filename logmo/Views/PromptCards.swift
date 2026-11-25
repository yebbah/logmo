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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text).font(.caption).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 0)
            }
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                        Label(s.0, systemImage: s.1 ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline).foregroundStyle(s.1 ? theme.good : Color.primary)
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(actions) { a in
                    Button(action: a.run) {
                        Text(a.title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .foregroundStyle(a.filled ? theme.onAccent : theme.accent)
                            .background(a.filled ? theme.accent : theme.card, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
    }
}
