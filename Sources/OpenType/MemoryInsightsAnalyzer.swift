import Foundation
import NaturalLanguage

enum MemoryInsightsAnalyzer {
    private struct DomainRule {
        let title: String
        let keywords: [String]
    }

    private struct StyleRule {
        let title: String
        let keywords: [String]
    }

    private static let domainRules = [
        DomainRule(
            title: "产品与 AI 工具",
            keywords: [
                "产品", "功能", "agent", "ai", "模型", "prompt", "api",
                "代码", "bug", "数据库", "工作流", "上下文", "记忆"
            ]
        ),
        DomainRule(
            title: "内容写作与编辑",
            keywords: [
                "文章", "写一", "改写", "润色", "整理", "标题", "脚本",
                "文案", "表达", "语气", "风格", "编辑", "总结"
            ]
        ),
        DomainRule(
            title: "社交媒体与评论",
            keywords: [
                "twitter", "tweet", "x reply", "推特", "推文", "回复",
                "评论", "发布", "帖子", "涨粉"
            ]
        ),
        DomainRule(
            title: "沟通与协作",
            keywords: [
                "邮件", "email", "消息", "通知", "微信", "slack", "回信",
                "邀请", "会议", "对话"
            ]
        ),
        DomainRule(
            title: "中英文翻译",
            keywords: [
                "英文", "english", "翻译", "地道", "native", "translate"
            ]
        )
    ]

    private static let styleRules = [
        StyleRule(
            title: "简洁、直接",
            keywords: [
                "简洁", "直接", "短一点", "精简", "别太长", "少用",
                "不要废话", "concise", "direct"
            ]
        ),
        StyleRule(
            title: "自然、口语化、低 AI 味",
            keywords: [
                "自然", "口语", "真人", "ai 味", "ai味", "像人", "像聊天",
                "human", "conversational"
            ]
        ),
        StyleRule(
            title: "保留原意和个人语气",
            keywords: [
                "保留原意", "不要改变", "忠实", "原话", "个人风格",
                "我的语气", "preserve"
            ]
        ),
        StyleRule(
            title: "结构清楚",
            keywords: [
                "结构", "分段", "列表", "条理", "层次", "整理一下"
            ]
        ),
        StyleRule(
            title: "地道英文，不直译",
            keywords: [
                "地道英文", "地道的英文", "不要直译", "native english",
                "idiomatic"
            ]
        )
    ]

    private static let stopwords: Set<String> = [
        "这个", "那个", "一个", "一些", "这些", "那些", "我们", "你们",
        "他们", "自己", "现在", "然后", "就是", "因为", "所以", "但是",
        "还是", "而且", "可以", "应该", "需要", "希望", "觉得", "帮我",
        "把这", "进行", "一下", "东西", "功能", "用户", "任务", "这样",
        "那样", "对吧", "是不是", "其实", "理论上", "可能", "比较",
        "the", "and", "that", "this", "with", "from", "have", "will", "would",
        "could", "should", "please", "help", "make", "write", "about", "into", "just",
        "really", "some", "more", "less", "than", "then", "when", "what", "your",
        "you", "for", "are", "was", "were", "its", "our"
    ]

    static func analyze(_ events: [MemoryEvent]) -> MemoryInsights {
        let texts = events.map {
            let effective = $0.effectiveInput
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return effective.isEmpty ? $0.rawTranscript : effective
        }
        let normalizedTexts = texts.map { $0.lowercased() }

        return MemoryInsights(
            observedTaskCount: events.count,
            commonTerms: commonTerms(in: texts),
            taskDomains: matchingRules(
                domainRules,
                texts: normalizedTexts
            ),
            languagePattern: languagePattern(in: texts),
            stylePreferences: matchingStyleRules(
                styleRules,
                texts: normalizedTexts
            ),
            updatedAt: Date()
        )
    }

    private static func commonTerms(in texts: [String]) -> [String] {
        var occurrenceCount: [String: Int] = [:]
        var taskCount: [String: Int] = [:]
        var displayValue: [String: String] = [:]

        for text in texts {
            let tokens = tokens(in: text)
            var seenInTask: Set<String> = []
            for token in tokens where isCandidateTerm(token) {
                let key = token.lowercased()
                occurrenceCount[key, default: 0] += 1
                displayValue[key] = preferredDisplay(
                    current: displayValue[key],
                    candidate: token
                )
                seenInTask.insert(key)
            }
            for key in seenInTask {
                taskCount[key, default: 0] += 1
            }
        }

        return occurrenceCount.keys
            .filter { key in
                (taskCount[key] ?? 0) >= 2 && (occurrenceCount[key] ?? 0) >= 2
            }
            .sorted { lhs, rhs in
                let lhsTasks = taskCount[lhs] ?? 0
                let rhsTasks = taskCount[rhs] ?? 0
                if lhsTasks != rhsTasks { return lhsTasks > rhsTasks }
                let lhsCount = occurrenceCount[lhs] ?? 0
                let rhsCount = occurrenceCount[rhs] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs < rhs
            }
            .prefix(12)
            .compactMap { displayValue[$0] }
    }

    private static func tokens(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) {
            range, _ in
            result.append(String(text[range]))
            return true
        }
        return result
    }

    private static func isCandidateTerm(_ token: String) -> Bool {
        let cleaned = token.trimmingCharacters(
            in: .punctuationCharacters.union(.whitespacesAndNewlines)
        )
        guard cleaned.count >= 2, cleaned.count <= 40 else { return false }
        let key = cleaned.lowercased()
        guard !stopwords.contains(key) else { return false }
        guard cleaned.rangeOfCharacter(from: .letters) != nil else { return false }
        return true
    }

    private static func preferredDisplay(
        current: String?,
        candidate: String
    ) -> String {
        guard let current else { return candidate }
        let candidateHasUppercase = candidate.rangeOfCharacter(
            from: .uppercaseLetters
        ) != nil
        let currentHasUppercase = current.rangeOfCharacter(
            from: .uppercaseLetters
        ) != nil
        return candidateHasUppercase && !currentHasUppercase ? candidate : current
    }

    private static func matchingRules(
        _ rules: [DomainRule],
        texts: [String]
    ) -> [String] {
        rules.compactMap { rule -> (String, Int)? in
            let count = texts.reduce(0) { partial, text in
                partial + (rule.keywords.contains { text.contains($0) } ? 1 : 0)
            }
            return count >= 2 ? (rule.title, count) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(4)
        .map(\.0)
    }

    private static func matchingStyleRules(
        _ rules: [StyleRule],
        texts: [String]
    ) -> [String] {
        rules.compactMap { rule -> (String, Int)? in
            let count = texts.reduce(0) { partial, text in
                partial + (rule.keywords.contains { text.contains($0) } ? 1 : 0)
            }
            return count >= 2 ? (rule.title, count) : nil
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    private static func languagePattern(in texts: [String]) -> String? {
        var hanCount = 0
        var latinCount = 0
        for scalar in texts.joined().unicodeScalars {
            if (0x4E00...0x9FFF).contains(Int(scalar.value)) {
                hanCount += 1
            } else if CharacterSet.letters.contains(scalar), scalar.isASCII {
                latinCount += 1
            }
        }

        let total = hanCount + latinCount
        guard total >= 40 else { return nil }
        let latinRatio = Double(latinCount) / Double(total)
        if hanCount >= 20, latinCount >= 10, latinRatio >= 0.08 {
            return "主要使用中文，经常混合英文专业词"
        }
        if latinRatio >= 0.70 {
            return "主要使用英文"
        }
        return "主要使用中文"
    }
}
