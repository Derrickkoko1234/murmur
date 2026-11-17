import SwiftUI

struct HUDView: View {
    @Bindable var controller: DictationController

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Waveform(level: controller.level, isActive: controller.state == .listening)
                .frame(width: DS.Size.hudWaveformWidth, height: DS.Size.hudWaveformHeight)

            if controller.isHandsFree {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
            }

            Text(label)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(DS.Motion.quick, value: controller.transcript)
        }
        // Applied to the row so the hands-free lock inherits the label's font and colour,
        // rather than restating them. Nothing here draws with it except the label.
        .font(DS.Font.bodyEmphasis)
        // Never red, even for errors: red means recording.
        .foregroundStyle(DS.Color.hudInk)
        .padding(.horizontal, DS.Space.wide)
        .frame(width: DS.Size.hudWidth, height: DS.Size.hudHeight)
        .background {
            Capsule()
                .fill(DS.Color.hud)
                .overlay { Capsule().strokeBorder(DS.Color.hudBorder, lineWidth: DS.Border.hairline) }
                .shadow(
                    color: DS.Shadow.hud.color,
                    radius: DS.Shadow.hud.radius,
                    x: DS.Shadow.hud.x,
                    y: DS.Shadow.hud.y
                )
        }
    }

    private var label: String {
        switch controller.state {
        // The mic isn't open yet — almost always the model still loading, which can take
        // minutes on a cold cache. "Listening…" here makes people talk into nothing.
        case .starting: "Loading speech model…"
        case .listening: controller.transcript.isEmpty ? listeningLabel : controller.transcript
        // Parakeet transcribes in one pass on release, so there's nothing to show until
        // it lands — say what's happening instead of leaving an empty pill.
        case .finishing: controller.transcript.isEmpty ? "Transcribing…" : controller.transcript
        case .error(let message): message
        case .idle: ""
        }
    }

    /// Hands-free keeps recording with the key up, so say how to stop it.
    private var listeningLabel: String {
        controller.isHandsFree
            ? "Hands-free · tap \(Settings.shared.pushToTalkKey.displayName) to finish"
            : "Listening…"
    }
}

/// Level-reactive bars. Each bar gets a fixed phase offset so the group ripples rather
/// than pumping in unison.
private struct Waveform: View {
    let level: Float
    let isActive: Bool

    private static let barCount = 10
    private static let phases: [Double] = (0..<barCount).map { index in
        // Irrational multiplier keeps the offsets from lining up into a visible period.
        (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(DS.Color.hudInk)
                        .frame(width: 3, height: height(for: index, at: t))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let floorHeight: CGFloat = 3
        guard isActive else { return floorHeight }

        let phase = Self.phases[index]
        let wave = sin(time * 6.0 + phase * .pi * 2)
        let amplitude = CGFloat(max(0.04, level))
        // Wave rides on top of the level so bars still breathe during quiet passages.
        let scaled = amplitude * (0.55 + 0.45 * CGFloat(wave))
        return floorHeight + max(0, scaled) * 19
    }
}
