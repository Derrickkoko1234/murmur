import SwiftUI

// Shared building blocks. Every value here comes from `DS`; if a component needs a number
// that isn't a token, add the token there rather than inlining it.

extension View {
    /// A rounded card with a hairline border.
    func card(_ fill: Color = DS.Color.raised, radius: CGFloat = DS.Radius.card) -> some View {
        background(fill, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
            )
    }
}

/// A page's title, with an optional line underneath.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(title)
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Small, uppercase, tracked — the label above a group.
struct SectionLabel: View {
    let text: Text

    init(_ string: String) { text = Text(string) }
    init(_ text: Text) { self.text = text }

    var body: some View {
        text
            .textCase(.uppercase)
            .font(DS.Font.caption)
            .tracking(DS.Font.sectionTracking)
            .foregroundStyle(DS.Color.inkSecondary)
    }
}

/// Ink-filled when prominent, a quiet outline otherwise.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.bodyEmphasis)
            .foregroundStyle(prominent ? DS.Color.inkInverse : DS.Color.ink)
            .padding(.horizontal, DS.Space.roomy)
            .padding(.vertical, DS.Space.snug)
            .background(prominent ? DS.Color.ink : DS.Color.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(DS.Color.border, lineWidth: prominent ? 0 : DS.Border.hairline))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A borderless icon that shows a hover background, for row actions.
struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Size.smallIcon, weight: .semibold))
                .foregroundStyle(isHovering ? DS.Color.ink : DS.Color.inkSecondary)
                .frame(width: DS.Space.wide, height: DS.Space.wide)
                .background(isHovering ? DS.Color.hover : .clear, in: .rect(cornerRadius: DS.Radius.chip))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// Red means recording — this is the one place it's drawn.
struct RecordDot: View {
    var body: some View {
        Circle()
            .fill(DS.Color.record)
            .frame(width: DS.Size.recordDot, height: DS.Size.recordDot)
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: DS.Size.smallIcon, weight: .semibold))
                .foregroundStyle(DS.Color.inkTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .card(DS.Color.raised, radius: DS.Radius.control)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Space.snug) {
            Text(title)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.ink)
            Text(detail)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.page)
        .card()
    }
}
