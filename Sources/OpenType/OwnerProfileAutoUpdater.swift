import Foundation

enum OwnerProfileAutoUpdater {
    static let updateInterval = 100

    private static let identityPrefix = "OpenType 自动归纳的近期任务："
    private static let stylePrefix = "OpenType 自动归纳的表达偏好："
    private static let termsPrefix = "OpenType 自动归纳的术语："

    /// Kept for source compatibility with earlier callers. Learned signals no
    /// longer mutate the user-confirmed profile; they are persisted separately
    /// by `AgentMemoryStore`.
    static func merging(
        profile: OwnerProfile,
        insights: MemoryInsights,
        personalDictionary: [String]
    ) -> OwnerProfile {
        removingLegacyManagedLines(from: profile)
    }

    static func removingLegacyManagedLines(from profile: OwnerProfile) -> OwnerProfile {
        var cleaned = profile
        cleaned.identityAndWork = removingManagedLines(from: profile.identityAndWork)
        cleaned.communicationStyle = removingManagedLines(
            from: profile.communicationStyle
        )
        cleaned.importantTerms = removingManagedLines(from: profile.importantTerms)
        if cleaned.preferredLanguage == .followInput {
            let explicitStyle = cleaned.communicationStyle.lowercased()
            if explicitStyle.contains("中文为主")
                || explicitStyle.contains("默认使用中文")
                || explicitStyle.contains("默认中文") {
                cleaned.preferredLanguage = .chinese
            } else if explicitStyle.contains("英文为主")
                || explicitStyle.contains("english by default")
                || explicitStyle.contains("default to english") {
                cleaned.preferredLanguage = .english
            }
        }
        return cleaned
    }

    private static func removingManagedLines(from text: String) -> String {
        var lines = text
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix(identityPrefix)
                    && !trimmed.hasPrefix(stylePrefix)
                    && !trimmed.hasPrefix(termsPrefix)
            }

        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
