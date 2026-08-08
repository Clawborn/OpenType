import Foundation

/// Keeps Light Transcription useful without turning it into a second chat
/// interface. Short, already-clean dictation is handled locally. Dictation
/// that benefits from cleanup gets one model pass, followed by a deterministic
/// faithfulness check. A suspicious rewrite always falls back to the ASR text.
enum LightTranscriptionPolicy {
    private static let modelLengthThreshold = 24
    private static let fillerSignals = [
        "嗯", "呃", "额", "那个", "就是说", "然后呢", "怎么说呢"
    ]

    static func shouldUseModel(for transcript: String) -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text.count >= modelLengthThreshold { return true }
        if text.contains("\n") { return true }
        if fillerSignals.contains(where: text.contains) { return true }
        return containsImmediateRepeatedPhrase(text)
    }

    static func localResult(for transcript: String) -> String {
        let text = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty, !hasTerminalPunctuation(text) else { return text }

        if looksLikeQuestion(text) {
            return text + (containsIdeograph(text) ? "？" : "?")
        }
        return text
    }

    static func validatedResult(
        original: String,
        candidate: String
    ) -> String {
        isFaithful(original: original, candidate: candidate)
            ? candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            : localResult(for: original)
    }

    static func isFaithful(original: String, candidate: String) -> Bool {
        let source = comparisonScalars(original)
        let output = comparisonScalars(candidate)
        guard !source.isEmpty, !output.isEmpty else { return false }

        let sourceCount = source.count
        let outputCount = output.count
        let maximumGrowth = max(8, sourceCount / 3)
        guard outputCount <= sourceCount + maximumGrowth else { return false }
        guard outputCount * 2 >= sourceCount else { return false }

        let distance = levenshteinDistance(source, output)
        let similarity = 1 - Double(distance) / Double(max(sourceCount, outputCount))
        let minimumSimilarity = sourceCount < 40 ? 0.55 : 0.45
        return similarity >= minimumSimilarity
    }

    private static func containsImmediateRepeatedPhrase(_ text: String) -> Bool {
        let characters = Array(text)
        guard characters.count >= 4 else { return false }
        let maximumWidth = min(6, characters.count / 2)
        guard maximumWidth >= 2 else { return false }

        for width in 2...maximumWidth {
            guard characters.count >= width * 2 else { continue }
            for start in 0...(characters.count - width * 2) {
                let middle = start + width
                let end = middle + width
                if characters[start..<middle].elementsEqual(characters[middle..<end]) {
                    return true
                }
            }
        }
        return false
    }

    private static func hasTerminalPunctuation(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".!?。！？…".contains(last)
    }

    private static func looksLikeQuestion(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let chineseSignals = [
            "为什么", "为啥", "怎么", "如何", "是否", "是不是",
            "能不能", "可不可以", "谁", "哪里", "哪一个", "多少", "几点"
        ]
        if text.hasSuffix("吗") || chineseSignals.contains(where: text.contains) {
            return true
        }
        let englishPrefixes = [
            "why ", "what ", "how ", "when ", "where ", "who ",
            "can ", "could ", "would ", "is ", "are ", "do ", "does ", "did "
        ]
        return englishPrefixes.contains(where: lowered.hasPrefix)
    }

    private static func containsIdeograph(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic }
    }

    private static func comparisonScalars(_ text: String) -> [UnicodeScalar] {
        text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func levenshteinDistance(
        _ lhs: [UnicodeScalar],
        _ rhs: [UnicodeScalar]
    ) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)
        for (leftIndex, left) in lhs.enumerated() {
            current[0] = leftIndex + 1
            for (rightIndex, right) in rhs.enumerated() {
                let substitution = previous[rightIndex]
                    + (left == right ? 0 : 1)
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
