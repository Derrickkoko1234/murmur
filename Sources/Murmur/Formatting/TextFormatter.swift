import Foundation

/// The cleanup pass between raw transcription and injection.
///
/// This is where Wispr Flow actually earns its keep — raw STT output is full of filler
/// words, missing punctuation, and spoken corrections. Swapping in an LLM-backed
/// formatter (Apple Foundation Models on-device, or Claude for the high-quality tier)
/// is the point of keeping this behind a protocol.
protocol TextFormatter: Sendable {
    func format(_ raw: String) async -> String
}

/// Deterministic, zero-latency cleanup. Good enough to be useful on its own and always
/// the fallback when a model-backed formatter is unavailable or times out.
struct RuleBasedFormatter: TextFormatter {
    /// Standalone filler words, stripped only when surrounded by word boundaries.
    private static let fillers = ["um", "uh", "erm", "uhm", "hmm", "mhm"]

    /// Spoken punctuation people actually use mid-dictation.
    private static let spokenPunctuation: [(String, String)] = [
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
        ("open paren", " ("),
        ("close paren", ") "),
    ]

    func format(_ raw: String) async -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        text = stripFillers(from: text)
        text = applySpokenPunctuation(to: text)
        text = collapseWhitespace(in: text)
        text = formatSpokenLists(in: text)
        text = capitalizeSentences(in: text)
        text = ensureTerminalPunctuation(in: text)

        return text
    }

    private func stripFillers(from text: String) -> String {
        var result = text
        for filler in Self.fillers {
            // Match the filler as a whole word, plus a trailing comma if the ASR added one.
            let pattern = "(?i)(?<![\\w'])\(filler)\\b,?"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    private func applySpokenPunctuation(to text: String) -> String {
        var result = text
        for (phrase, replacement) in Self.spokenPunctuation {
            result = result.replacingOccurrences(
                of: "(?i)\\b\(phrase)\\b",
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Spoken enumerators, folded to the number they mark. Digits are accepted too, since
    /// engines disagree on whether "number one" comes out as "number 1".
    private static let listNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]

    /// A "number N" marker plus the punctuation and spacing the engine put around it, so
    /// removing the match leaves clean item boundaries.
    private static let listMarker = try! NSRegularExpression(
        pattern: "[ \\t,.;:]*\\bnumber\\s+(one|two|three|four|five|six|seven|eight|nine|ten|\\d{1,2})\\b[ \\t,.;:]*",
        options: [.caseInsensitive]
    )

    /// "…here's the plan, number one, buy milk, number two, call mum" → a numbered list.
    ///
    /// Only a run that starts at one and counts up by one, with at least two items, becomes
    /// a list — a lone "my number one priority" is left alone. Text before the first marker
    /// is the lead-in; the last item runs to the next line break, so "new line" or "new
    /// paragraph" ends the list.
    private func formatSpokenLists(in text: String) -> String {
        let ns = text as NSString
        let markers = Self.listMarker.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> (range: NSRange, value: Int)? in
                let word = ns.substring(with: match.range(at: 1)).lowercased()
                guard let value = Self.listNumbers[word] ?? Int(word) else { return nil }
                return (match.range, value)
            }

        // The first "number one" immediately followed by "number two" — an earlier lone
        // "number one" is just prose.
        guard let start = markers.indices.dropLast().first(where: {
            markers[$0].value == 1 && markers[$0 + 1].value == 2
        }) else { return text }
        var end = start
        while end + 1 < markers.count, markers[end + 1].value == markers[end].value + 1 {
            end += 1
        }
        let run = markers[start...end]

        // The last item stops at the first line break after its marker.
        let lastBodyStart = NSMaxRange(run.last!.range)
        let lineBreak = ns.range(of: "\n", range: NSRange(location: lastBodyStart, length: ns.length - lastBodyStart))
        let listEnd = lineBreak.location == NSNotFound ? ns.length : lineBreak.location

        var items: [String] = []
        for (offset, marker) in run.enumerated() {
            let bodyStart = NSMaxRange(marker.range)
            let bodyEnd = offset + 1 < run.count ? run[run.startIndex + offset + 1].range.location : listEnd
            let item = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                .trimmingCharacters(in: CharacterSet(charactersIn: ",.;:").union(.whitespaces))
            // An empty item means the markers weren't really a list ("number one, number two").
            guard !item.isEmpty else { return text }
            items.append("\(offset + 1). \(item)")
        }

        let leadIn = ns.substring(to: run.first!.range.location)
        let tail = ns.substring(from: listEnd)
        let list = items.joined(separator: "\n")
        let joined = leadIn.isEmpty || leadIn.hasSuffix("\n") ? leadIn + list : "\(leadIn):\n\(list)"
        return joined + formatSpokenLists(in: tail)
    }

    private func capitalizeSentences(in text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(Character(character.uppercased()))
                capitalizeNext = false
            } else {
                result.append(character)
                if ".!?\n".contains(character) { capitalizeNext = true }
            }
        }
        return result
    }

    private func ensureTerminalPunctuation(in text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        // List items are left unpunctuated, so the last one shouldn't be the odd one out.
        let lastLine = text.split(separator: "\n").last ?? ""
        guard lastLine.range(of: "^\\d+\\. ", options: .regularExpression) == nil else { return text }
        return text + "."
    }
}

/// No-op formatter, for comparing raw engine output against the cleanup pass.
struct PassthroughFormatter: TextFormatter {
    func format(_ raw: String) async -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
