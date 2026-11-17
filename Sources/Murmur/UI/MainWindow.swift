import SwiftUI

/// The main window: a sidebar on the window background, and the selected page as one large
/// card beside it.
struct MainWindow: View {
    @Bindable var controller: DictationController

    @State private var section: Section = .home

    enum Section: CaseIterable, Identifiable {
        case home
        case dictionary

        var id: Self { self }
        var title: String { self == .home ? "Home" : "Dictionary" }
        var systemImage: String { self == .home ? "house" : "character.book.closed" }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch section {
                case .home: HomePage(controller: controller)
                case .dictionary: DictionaryPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.surface)
            .clipShape(.rect(cornerRadius: DS.Radius.page))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.page)
                    .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
            )
            .padding([.vertical, .trailing], DS.Space.base)
        }
        .background(DS.Color.background)
        .frame(minWidth: DS.Size.windowMinWidth, minHeight: DS.Size.windowMinHeight)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DS.Space.hair) {
            HStack(spacing: DS.Space.snug) {
                Image(systemName: "waveform")
                Text("Murmur")
            }
            .font(DS.Font.logo)
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, DS.Space.base)
            .padding(.bottom, DS.Space.wide)

            ForEach(Section.allCases) { candidate in
                Button {
                    withAnimation(DS.Motion.page) { section = candidate }
                } label: {
                    SidebarRow(
                        title: candidate.title,
                        systemImage: candidate.systemImage,
                        isSelected: section == candidate
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            SettingsLink {
                SidebarRow(title: "Settings", systemImage: "gearshape", isSelected: false)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Space.base)
        .frame(width: DS.Size.sidebarWidth, alignment: .leading)
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Size.icon))
                .frame(width: DS.Space.wide)
            Text(title)
                .font(DS.Font.sidebar)
            Spacer()
        }
        .foregroundStyle(DS.Color.ink)
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(fill, in: .rect(cornerRadius: DS.Radius.control))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.quick, value: isHovering)
    }

    private var fill: Color {
        if isSelected { return DS.Color.selection }
        return isHovering ? DS.Color.hover : .clear
    }
}
