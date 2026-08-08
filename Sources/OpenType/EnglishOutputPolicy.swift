import Foundation

enum EnglishOutputPolicy {
    static func needsCorrection(
        mode: InputMode,
        source: String = "",
        output: String
    ) -> Bool {
        guard mode == .english else { return false }
        if containsUnexpectedHanCharacters(output) { return true }

        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return false }

        // English Mode is a bounded rewrite, not an invitation to answer or
        // invent. A very large expansion is a reliable signal that a chat
        // model acted on a short utterance instead of transforming it.
        let maximumReasonableLength = max(96, source.count * 6)
        if output.count > maximumReasonableLength { return true }

        // When ASR supplies explicit question punctuation, the transformed
        // utterance must still be a question. This catches fluent English
        // answers that contain no Han characters.
        if sourceIsClearlyAQuestion(source), !candidateIsAQuestion(output) {
            return true
        }

        // A request or command in English Mode is still dictated content. A
        // fluent model can otherwise turn “帮我写一封邮件” into the email
        // itself, which looks like valid English and evades language/length
        // checks. Require both the request shape and its core action to remain
        // visible in the transformed utterance.
        if SpeechActGuard.sourceRequestsAction(source),
           !SpeechActGuard.candidatePreservesRequestedAction(
                source: source,
                candidate: output
           ) {
            return true
        }

        return false
    }

    static func containsUnexpectedHanCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }

    static func sourceIsClearlyAQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("?") || trimmed.contains("？") { return true }

        let normalized = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.!！"))
            .lowercased()
        if normalized.hasSuffix("吗") || normalized.hasSuffix("嘛") {
            return true
        }

        let directQuestionPrefixes = [
            "为什么", "为啥", "怎么", "如何", "是不是", "是否", "能不能",
            "可不可以", "什么", "谁", "哪里", "哪儿", "什么时候", "多少", "几点",
            "why ", "how ", "what ", "when ", "where ", "who ", "which ",
            "can ", "could ", "would ", "should ", "is ", "are ", "do ",
            "does ", "did "
        ]
        return directQuestionPrefixes.contains { normalized.hasPrefix($0) }
    }

    static func candidateIsAQuestion(_ text: String) -> Bool {
        let trailingDecoration = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'”’）)]}》】"))
        let normalized = text.trimmingCharacters(in: trailingDecoration)
        return normalized.hasSuffix("?") || normalized.hasSuffix("？")
    }
}

enum SmartEditOutputPolicy {
    static func needsCorrection(
        mode: InputMode,
        source: String,
        output: String
    ) -> Bool {
        guard mode == .clean else { return false }

        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !output.isEmpty else { return false }

        // Smart Edit may reorganize dictation, but it must not turn a short
        // utterance into a conversational answer or an invented artifact.
        if output.count > max(160, source.count * 3) { return true }

        if EnglishOutputPolicy.sourceIsClearlyAQuestion(source),
           !EnglishOutputPolicy.candidateIsAQuestion(output) {
            return true
        }

        if SpeechActGuard.sourceRequestsAction(source),
           !SpeechActGuard.candidatePreservesRequestedAction(
                source: source,
                candidate: output
           ) {
            return true
        }

        return false
    }
}

enum NonAgenticOutputPolicy {
    static func needsCorrection(
        mode: InputMode,
        source: String,
        output: String
    ) -> Bool {
        switch mode {
        case .english:
            return EnglishOutputPolicy.needsCorrection(
                mode: mode,
                source: source,
                output: output
            )
        case .clean:
            return SmartEditOutputPolicy.needsCorrection(
                mode: mode,
                source: source,
                output: output
            )
        default:
            return false
        }
    }
}

private enum SpeechActGuard {
    private struct ActionFamily {
        let sourceSignals: [String]
        let candidateSignals: [String]
    }

    private static let actionFamilies: [ActionFamily] = [
        ActionFamily(
            sourceSignals: ["总结", "概括", "归纳", "summarize", "sum up"],
            candidateSignals: ["总结", "概括", "归纳", "summarize", "sum up"]
        ),
        ActionFamily(
            sourceSignals: ["翻译", "翻成", "译成", "translate", "render into"],
            candidateSignals: ["翻译", "翻成", "译成", "translate", "render"]
        ),
        ActionFamily(
            sourceSignals: ["写", "生成", "起草", "创作", "撰写", "write", "draft", "generate", "compose"],
            candidateSignals: ["写", "生成", "起草", "创作", "撰写", "write", "draft", "generate", "compose", "create"]
        ),
        ActionFamily(
            sourceSignals: ["发送", "发一", "发布", "寄给", "send", "post", "publish", "tweet", "email"],
            candidateSignals: ["发送", "发一", "发布", "寄给", "send", "post", "publish", "tweet", "email"]
        ),
        ActionFamily(
            sourceSignals: ["告诉", "提醒", "通知", "tell", "remind", "notify"],
            candidateSignals: ["告诉", "提醒", "通知", "tell", "remind", "notify"]
        ),
        ActionFamily(
            sourceSignals: ["列出", "列一下", "列个", "列一份", "list"],
            candidateSignals: ["列出", "列一下", "list"]
        ),
        ActionFamily(
            sourceSignals: ["搜索", "查一下", "查找", "找一下", "检索", "search", "look up", "find"],
            candidateSignals: ["搜索", "查一下", "查找", "找一下", "检索", "search", "look up", "find"]
        ),
        ActionFamily(
            sourceSignals: ["保存", "存到", "save"],
            candidateSignals: ["保存", "存到", "save"]
        ),
        ActionFamily(
            sourceSignals: ["打开", "启动", "open", "launch"],
            candidateSignals: ["打开", "启动", "open", "launch"]
        ),
        ActionFamily(
            sourceSignals: ["删除", "删掉", "去掉", "remove", "delete"],
            candidateSignals: ["删除", "删掉", "去掉", "remove", "delete"]
        ),
        ActionFamily(
            sourceSignals: ["修改", "改写", "润色", "优化", "edit", "revise", "rewrite", "polish"],
            candidateSignals: ["修改", "改写", "润色", "优化", "edit", "revise", "rewrite", "polish"]
        ),
        ActionFamily(
            sourceSignals: ["解释", "说明一下", "explain"],
            candidateSignals: ["解释", "说明一下", "explain"]
        )
    ]

    private static let chineseRequestSignals = [
        "帮我", "请你", "请帮", "麻烦你", "麻烦帮", "替我", "给我",
        "我要你", "我希望你", "你帮我", "你帮忙", "你来", "你把",
        "你可以", "你能", "能不能", "可不可以"
    ]

    private static let englishRequestSignals = [
        "please ", "could you", "can you", "would you", "will you",
        "help me", "i need you to", "i want you to", "i'd like you to",
        "let's "
    ]

    private static let directChineseCommandPrefixes = [
        "总结一下", "概括一下", "翻译一下", "翻成", "写一", "写个", "写份",
        "写封", "写条", "生成一", "起草一", "列出", "列一下", "发一",
        "发送", "发布", "告诉", "提醒", "通知", "搜索", "查一下", "找一下",
        "保存", "打开", "删除", "删掉", "去掉", "修改", "改写", "润色",
        "优化", "解释一下", "说明一下"
    ]

    private static let directEnglishCommandPrefixes = [
        "summarize ", "translate ", "write ", "draft ", "generate ",
        "create ", "make ", "build ", "design ", "list ", "send ",
        "post ", "publish ", "tweet ", "email ", "tell ", "remind ",
        "notify ", "search ", "look up ", "find ", "save ", "open ",
        "delete ", "remove ", "edit ", "revise ", "rewrite ", "polish ",
        "explain "
    ]

    static func sourceRequestsAction(_ text: String) -> Bool {
        let normalized = normalized(text)
        guard !normalized.isEmpty else { return false }

        if chineseRequestSignals.contains(where: normalized.contains)
            || englishRequestSignals.contains(where: normalized.contains) {
            return true
        }

        let stripped = strippingSpokenLeadIn(normalized)
        if (stripped.hasPrefix("把") || stripped.hasPrefix("将")),
           actionFamilies.contains(where: { family in
               family.sourceSignals.contains(where: stripped.contains)
           }) {
            return true
        }
        return directChineseCommandPrefixes.contains(where: stripped.hasPrefix)
            || directEnglishCommandPrefixes.contains(where: stripped.hasPrefix)
    }

    static func candidatePreservesRequestedAction(
        source: String,
        candidate: String
    ) -> Bool {
        let normalizedSource = normalized(source)
        let normalizedCandidate = normalized(candidate)
        guard candidateLooksLikeRequestOrCommand(normalizedCandidate) else {
            return false
        }

        let requiredFamilies = actionFamilies.filter { family in
            family.sourceSignals.contains(where: normalizedSource.contains)
        }
        return requiredFamilies.allSatisfy { family in
            family.candidateSignals.contains(where: normalizedCandidate.contains)
        }
    }

    private static func candidateLooksLikeRequestOrCommand(
        _ candidate: String
    ) -> Bool {
        if sourceRequestsAction(candidate) { return true }
        let stripped = strippingSpokenLeadIn(candidate)
        return directChineseCommandPrefixes.contains(where: stripped.hasPrefix)
            || directEnglishCommandPrefixes.contains(where: stripped.hasPrefix)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func strippingSpokenLeadIn(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "嗯", "呃", "额", "然后", "那", "那么", "好", "ok", "okay",
            "请", "please"
        ]
        var didStrip = true
        while didStrip {
            didStrip = false
            for prefix in prefixes where result.hasPrefix(prefix) {
                result.removeFirst(prefix.count)
                result = result.trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines
                        .union(.punctuationCharacters)
                )
                didStrip = true
                break
            }
        }
        return result
    }
}
