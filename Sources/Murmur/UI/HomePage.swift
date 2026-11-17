import MurmurCore
import MurmurDictionary
import AppKit
import SwiftUI

/// Greeting, the record card, usage stats, and every past dictation grouped by day.
struct HomePage: View {
    @Bindable var controller: DictationController

    @State private var store = RunStore.shared

    private var stats: UsageStats {
        UsageStats(runs: store.runs.map { ($0.date, $0.audioSeconds, $0.text) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.panel) {
                PageHeader(title: greeting)

                HStack(alignment: .top, spacing: DS.Space.roomy) {
                    RecordCard(controller: controller)
                    StatsCard(stats: stats)
                }
                // Lets both cards stretch to the taller one's height.
                .fixedSize(horizontal: false, vertical: true)

                History()
            }
            .padding(DS.Space.page)
        }
    }

    private var greeting: String {
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Welcome back" : "Welcome back, \(first)"
    }
}

// MARK: - Record card

/// How to dictate, plus a button for recording without the hotkey.
private struct RecordCard: View {
    @Bindable var controller: DictationController

    @State private var settings = Settings.shared
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var isRecording: Bool { controller.state == .listening }

    private var instructions: String {
        switch controller.state {
        case .starting: "Loading speech model… Wait for Listening before speaking."
        case .listening: "Listening… Speak now, then click Stop to transcribe."
        case .finishing: "Transcribing your recording…"
        case .error(let message): message
        case .idle: "Hold \(settings.pushToTalkKey.displayName) in any app and talk. Double-tap it for hands-free."
        }
    }

    private var buttonTitle: String {
        switch controller.state {
        case .starting: "Cancel"
        case .listening: "Stop"
        case .finishing: "Transcribing…"
        case .idle, .error: "Record"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Text("Speak, don’t type")
                .font(DS.Font.display)
                .foregroundStyle(DS.Color.heroInk)
            Text(instructions)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.heroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DS.Space.wide)

            HStack(spacing: DS.Space.base) {
                Button {
                    if controller.state.isActive {
                        controller.stopButtonRecording()
                    } else {
                        controller.startButtonRecording()
                    }
                } label: {
                    HStack(spacing: DS.Space.snug) {
                        if isRecording {
                            RecordDot()
                        } else {
                            Image(systemName: "mic.fill")
                        }
                        Text(buttonTitle)
                    }
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.heroInk)
                    .padding(.horizontal, DS.Space.roomy)
                    .padding(.vertical, DS.Space.snug)
                    .background(DS.Color.heroControl, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(controller.state == .finishing)

                if isRecording {
                    Text(counterText)
                        .font(DS.Font.counter)
                        .foregroundStyle(DS.Color.heroInkSecondary)
                }
            }
        }
        .padding(DS.Space.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.hero, in: .rect(cornerRadius: DS.Radius.card))
        .onChange(of: isRecording) { _, active in
            startedAt = active ? Date() : nil
            if !active { elapsed = 0 }
        }
        .task(id: startedAt) {
            guard let startedAt else { return }
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var counterText: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Stats

private struct StatsCard: View {
    let stats: UsageStats

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            row(stats.words.formatted(), "total words")
            row(stats.wordsPerMinute.formatted(), "wpm")
            row(stats.dayStreak.formatted(), "day streak")
        }
        .padding(DS.Space.wide)
        .frame(width: DS.Size.statsWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.snug) {
            Text(value)
                .font(DS.Font.stat)
                .foregroundStyle(DS.Color.ink)
            Text(label)
                .font(DS.Font.statLabel)
                .foregroundStyle(DS.Color.inkSecondary)
        }
    }
}

// MARK: - History

/// Past transcriptions, newest first, one card per day. Searchable, each copyable.
private struct History: View {
    @State private var store = RunStore.shared
    @State private var settings = Settings.shared
    @State private var query = ""
    @State private var isSearching = false
    @State private var isConfirmingClear = false

    private var days: [(day: Date, runs: [DictationRun])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trimmed.isEmpty
            ? store.runs
            : store.runs.filter { $0.text.localizedStandardContains(trimmed) }
        return Dictionary(grouping: matching) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            header

            if isSearching {
                SearchField(text: $query, placeholder: "Search transcriptions")
            }

            if days.isEmpty {
                EmptyState(
                    title: store.runs.isEmpty ? "No dictations yet" : "No matches",
                    detail: store.runs.isEmpty
                        ? "Hold \(settings.pushToTalkKey.displayName) in any app and start talking."
                        : "Try a different search."
                )
            } else {
                LazyVStack(alignment: .leading, spacing: DS.Space.wide) {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: DS.Space.snug) {
                            SectionLabel(Text(group.day, format: .dateTime.month(.wide).day().year()))
                            VStack(spacing: 0) {
                                ForEach(Array(group.runs.enumerated()), id: \.element.id) { index, run in
                                    if index > 0 {
                                        Rectangle()
                                            .fill(DS.Color.border)
                                            .frame(height: DS.Border.hairline)
                                    }
                                    TranscriptionRow(run: run) {
                                        withAnimation(DS.Motion.page) { RunLog.delete(run) }
                                    }
                                }
                            }
                            .clipShape(.rect(cornerRadius: DS.Radius.card))
                            .card()
                        }
                    }
                }
            }
        }
        // Confirmed, unlike a single row: one row is trivially re-recorded, the whole
        // history is not, and there's no undo.
        .confirmationDialog(
            "Delete all \(store.runs.count) transcriptions?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { RunLog.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.tight) {
            Text("History")
                .font(DS.Font.heading)
                .foregroundStyle(DS.Color.ink)
            Spacer()
            IconButton(systemImage: "magnifyingglass", help: "Search transcriptions") {
                withAnimation(DS.Motion.page) { isSearching.toggle() }
                if !isSearching { query = "" }
            }
            Menu {
                Button("Delete All…", role: .destructive) { isConfirmingClear = true }
                    .disabled(store.runs.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }
}

private struct TranscriptionRow: View {
    let run: DictationRun
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.roomy) {
            Text(run.date, format: .dateTime.hour().minute())
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkTertiary)
                .frame(width: DS.Size.timeColumn, alignment: .leading)
                .help(String(format: "Typed %.2fs after release", run.processSeconds))

            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Text(run.text)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: DS.Size.textColumn, alignment: .leading)

                if let corrections = run.corrections, !corrections.isEmpty {
                    CorrectionBadges(corrections: corrections)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DS.Space.hair) {
                IconButton(systemImage: didCopy ? "checkmark" : "doc.on.doc", help: "Copy") { copy() }
                // Deletes without a confirmation — a single transcript is cheap to redo, and a
                // dialog on every row would make tidying up tedious. "Delete All" confirms.
                IconButton(systemImage: "trash", help: "Delete this transcription", action: onDelete)
            }
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, DS.Space.wide)
        .padding(.vertical, DS.Space.roomy)
        .background(isHovering ? DS.Color.hover : .clear)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.quick, value: isHovering)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: DS.Motion.copiedFeedback)
            didCopy = false
        }
    }
}

/// Shows that the dictionary fired, and on what. Without this the dictionary is invisible
/// and you can't tell a rule that works from one that never matches.
private struct CorrectionBadges: View {
    let corrections: [AppliedCorrection]

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            ForEach(corrections, id: \.self) { correction in
                HStack(spacing: DS.Space.tight) {
                    Text(correction.from)
                        .strikethrough()
                        .foregroundStyle(DS.Color.inkTertiary)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(DS.Color.inkTertiary)
                    Text(correction.to)
                        .foregroundStyle(DS.Color.ink)
                    if correction.count > 1 {
                        Text("×\(correction.count)")
                            .foregroundStyle(DS.Color.inkTertiary)
                    }
                }
                .font(DS.Font.caption)
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.hair)
                .overlay(
                    Capsule().strokeBorder(DS.Color.caution.opacity(0.5), lineWidth: DS.Border.hairline)
                )
            }
        }
        .help("Dictionary corrections applied")
    }
}
