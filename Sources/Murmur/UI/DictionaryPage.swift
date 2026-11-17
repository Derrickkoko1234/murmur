import MurmurDictionary
import AppKit
import SwiftUI

/// The dictionary: add, edit, delete, search.
///
/// Both entry kinds live in one list rather than separate tabs — they're two shapes of the
/// same idea and you want to see everything you've taught it at once. The kind is carried by
/// a tag on each row.
struct DictionaryPage: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                PageHeader(
                    title: "Dictionary",
                    subtitle: "Names, jargon and fixes Murmur should always get right."
                ) {
                    Button { isAdding = true } label: {
                        Label("Add word", systemImage: "plus")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut("n", modifiers: .command)
                }

                SearchField(text: $query, placeholder: "Search dictionary")

                if entries.isEmpty {
                    EmptyState(
                        title: store.entries.isEmpty ? "Your dictionary is empty" : "No matches",
                        detail: store.entries.isEmpty
                            ? "Add words it keeps getting wrong."
                            : "Try a different search."
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Rectangle()
                                    .fill(DS.Color.border)
                                    .frame(height: DS.Border.hairline)
                            }
                            DictionaryRow(
                                entry: entry,
                                onEdit: { editing = entry },
                                onToggle: {
                                    var updated = entry
                                    updated.isEnabled.toggle()
                                    store.update(updated)
                                },
                                onDelete: { store.delete(entry) }
                            )
                        }
                    }
                    .clipShape(.rect(cornerRadius: DS.Radius.card))
                    .card()
                }

                footer
            }
            .padding(DS.Space.page)
        }
        .sheet(isPresented: $isAdding) {
            DictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry) { store.update($0) }
        }
    }

    /// The file path is shown because the spec asks for the dictionary to be editable outside
    /// the UI — which is only true if you can find it.
    private var footer: some View {
        HStack(spacing: DS.Space.snug) {
            Text("\(store.entries.count) entries")
            Text("·")
            Button("Reveal dictionary.txt") {
                NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
            }
            .buttonStyle(.plain)
            .underline()
            .help(DictionaryStore.fileURL.path)
        }
        .font(DS.Font.label)
        .foregroundStyle(DS.Color.inkTertiary)
    }
}

// MARK: - Row

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Text(entry.kind == .correction ? "Fix" : "Term")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.inkSecondary)
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.hair)
                .background(DS.Color.hover, in: .capsule)

            Group {
                if entry.kind == .correction {
                    Text(entry.hear)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: DS.Size.smallIcon, weight: .semibold))
                        .foregroundStyle(DS.Color.inkTertiary)
                }

                Text(entry.write)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.ink)
            }
            .opacity(entry.isEnabled ? 1 : 0.45)

            Spacer()

            HStack(spacing: DS.Space.hair) {
                IconButton(systemImage: "pencil", help: "Edit", action: onEdit)
                IconButton(systemImage: "trash", help: "Delete", action: onDelete)
            }
            .opacity(isHovering ? 1 : 0)

            Toggle("Enabled", isOn: Binding(get: { entry.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(entry.isEnabled ? "Turn off" : "Turn on")
        }
        .padding(.horizontal, DS.Space.roomy)
        .padding(.vertical, DS.Space.base)
        .background(isHovering ? DS.Color.hover : .clear)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.quick, value: isHovering)
    }
}

// MARK: - Editor

/// Add or edit one entry, with the false-positive warning shown live as you type.
private struct DictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    private var isValid: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            Text(entry == nil ? "New entry" : "Edit entry")
                .font(DS.Font.heading)
                .foregroundStyle(DS.Color.ink)

            Picker("Kind", selection: $kind) {
                Text("Term").tag(DictionaryEntry.Kind.term)
                Text("Correction").tag(DictionaryEntry.Kind.correction)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if kind == .correction {
                field("When you hear", text: $hear, prompt: "cloud code")
            }
            field(
                kind == .correction ? "Write" : "Word or phrase",
                text: $write,
                prompt: kind == .correction ? "Claude Code" : "Anthropic"
            )

            ForEach(warnings) { warning in
                Label {
                    Text(warning.message)
                        .foregroundStyle(DS.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Color.caution)
                }
                .font(DS.Font.label)
                .padding(DS.Space.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: DS.Radius.control)
            }

            HStack(spacing: DS.Space.snug) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .controlSize(.large)
        }
        .padding(DS.Space.wide)
        .frame(width: DS.Size.editorWidth)
        .animation(DS.Motion.page, value: kind)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text(label)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)
            TextField(label, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
        }
    }
}
