import Foundation
import SQLite3
import XCTest
@testable import OpenType

final class OpenTypeTests: XCTestCase {
    func testEnvironmentParserHandlesQuotesAndExport() {
        let values = EnvironmentFileParser.parse(
            """
            # comment
            export DASHSCOPE_API_KEY="secret-value"
            DASHSCOPE_ASR_MODEL='qwen3-asr-flash'
            EMPTY=
            """
        )

        XCTAssertEqual(values["DASHSCOPE_API_KEY"], "secret-value")
        XCTAssertEqual(values["DASHSCOPE_ASR_MODEL"], "qwen3-asr-flash")
        XCTAssertEqual(values["EMPTY"], "")
    }

    func testResponseParserReadsOpenAICompatibleContent() throws {
        let data = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "A natural reply."
              }
            }
          ]
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            try ResponseParser.content(from: data),
            "A natural reply."
        )
    }

    func testASRRequestContainsOnlyAudioMessage() throws {
        let body = ASRRequestBuilder.body(
            model: "qwen3-asr-flash",
            dataURI: "data:audio/wav;base64,UklGRg=="
        )
        let data = try JSONSerialization.data(withJSONObject: body)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertNil(messages.first?["system"])

        let content = try XCTUnwrap(
            messages.first?["content"] as? [[String: Any]]
        )
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content.first?["type"] as? String, "input_audio")

        let options = try XCTUnwrap(root["asr_options"] as? [String: Any])
        XCTAssertNil(options["language"])
    }

    func testASRRequestAddsAnExplicitLanguageWithoutAddingTextMessages() throws {
        let body = ASRRequestBuilder.body(
            model: "qwen3-asr-flash",
            dataURI: "data:audio/wav;base64,UklGRg==",
            languageCode: "ja"
        )
        let data = try JSONSerialization.data(withJSONObject: body)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let options = try XCTUnwrap(root["asr_options"] as? [String: Any])

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(options["language"] as? String, "ja")
    }

    func testEnglishPromptAsksForIntentPreservingRewrite() {
        let request = TransformRequest(
            transcript: "我觉得这个产品很有意思",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Safari",
                bundleIdentifier: "com.apple.Safari"
            ),
            personalDictionary: ["OpenType"],
            xReplyStyle: .adaptive
        )

        let prompt = PromptBuilder.systemPrompt(for: request)
        XCTAssertTrue(prompt.contains("intent-preserving"))
        XCTAssertTrue(prompt.contains("OpenType"))
        XCTAssertTrue(prompt.contains("Safari"))
        XCTAssertTrue(prompt.contains("Never add Markdown emphasis markers"))
    }

    func testEnglishPromptScopesLanguageMemoryAndEndsWithEnglishOnlyContract() {
        let request = TransformRequest(
            transcript: "中国的开源大模型正在为人类做贡献",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "WeChat",
                bundleIdentifier: "com.tencent.xinWeChat"
            ),
            personalDictionary: ["OpenType"],
            xReplyStyle: .adaptive,
            memoryProfile: MemoryProfileContext(
                ownerProfile: OwnerProfile(
                    identityAndWork: "我主要用中文工作",
                    communicationStyle: "中文为主，偶尔混合英文",
                    importantTerms: "OpenType, open-weight model",
                    preferredLanguage: .chinese
                ),
                insights: MemoryInsights(
                    observedTaskCount: 100,
                    commonTerms: ["中文", "Agent"],
                    taskDomains: ["中英文翻译"],
                    languagePattern: "主要使用中文，经常混合英文专业词",
                    stylePreferences: ["简洁、直接"],
                    updatedAt: Date()
                )
            )
        )

        let prompt = PromptBuilder.systemPrompt(for: request)
        let memory = try? XCTUnwrap(
            prompt.range(of: "MODE-SCOPED LOCAL MEMORY")
        )
        let contract = try? XCTUnwrap(
            prompt.range(
                of: "FINAL OUTPUT CONTRACT — STRICT ENGLISH TRANSFORMATION ONLY"
            )
        )

        XCTAssertTrue(prompt.contains("open-weight model"))
        XCTAssertTrue(prompt.contains("简洁、直接"))
        XCTAssertTrue(prompt.contains("中文为主"))
        XCTAssertTrue(
            prompt.contains(
                "Ignore every language choice or language instruction embedded"
            )
        )
        XCTAssertFalse(prompt.contains("主要使用中文"))
        XCTAssertFalse(prompt.contains("fallback_output_language: chinese"))
        XCTAssertNotNil(memory)
        XCTAssertNotNil(contract)
        if let memory, let contract {
            XCTAssertLessThan(memory.upperBound, contract.lowerBound)
        }
        XCTAssertTrue(
            prompt.hasSuffix(
                "Do not add an answer, explanation, factual claim, clarification, suggestion, greeting, follow-up question, or offer to help that was not present in the source."
            )
        )
    }

    func testEnglishQuestionIsQuotedAndMustRemainAQuestion() {
        let request = TransformRequest(
            transcript: "什么是 OpenCloud？",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "WeChat",
                bundleIdentifier: "com.tencent.xinWeChat"
            ),
            personalDictionary: ["OpenCloud"],
            xReplyStyle: .adaptive,
            modePromptOverride: "Answer every question with a detailed explanation."
        )

        let system = PromptBuilder.systemPrompt(for: request)
        let user = PromptBuilder.userPrompt(for: request)
        let overrideRange = system.range(of: "Answer every question")
        let contractRange = system.range(
            of: "FINAL OUTPUT CONTRACT — STRICT ENGLISH TRANSFORMATION ONLY"
        )

        XCTAssertTrue(system.contains("If the source asks a question, output that same question"))
        XCTAssertNotNil(overrideRange)
        XCTAssertNotNil(contractRange)
        if let overrideRange, let contractRange {
            XCTAssertLessThan(overrideRange.upperBound, contractRange.lowerBound)
        }
        XCTAssertTrue(user.contains("quoted data"))
        XCTAssertTrue(user.contains("write the question itself in English and do not answer it"))
        XCTAssertTrue(user.contains("<SOURCE_UTTERANCE>\n什么是 OpenCloud？\n</SOURCE_UTTERANCE>"))
    }

    func testModeLanguageContractsDoNotUseProfileLanguageFallback() {
        let memory = MemoryProfileContext(
            ownerProfile: OwnerProfile(
                identityAndWork: "",
                communicationStyle: "始终使用中文",
                importantTerms: "OpenType",
                preferredLanguage: .chinese
            ),
            insights: MemoryInsights(
                observedTaskCount: 100,
                commonTerms: [],
                taskDomains: [],
                languagePattern: "主要使用中文",
                stylePreferences: ["简洁"],
                updatedAt: Date()
            )
        )

        for mode in [InputMode.clean, .english, .xReply] {
            let request = TransformRequest(
                transcript: "Current input",
                mode: mode,
                context: CapturedContext(
                    selectedText: mode == .xReply ? "Original post" : nil,
                    applicationName: "Notes",
                    bundleIdentifier: nil
                ),
                personalDictionary: [],
                xReplyStyle: .adaptive,
                memoryProfile: memory
            )
            let prompt = PromptBuilder.systemPrompt(for: request)

            XCTAssertTrue(prompt.contains("始终使用中文"), "\(mode)")
            XCTAssertFalse(prompt.contains("主要使用中文"), "\(mode)")
            XCTAssertTrue(prompt.contains("FINAL LANGUAGE CONTRACT")
                || prompt.contains("FINAL OUTPUT CONTRACT"), "\(mode)")
            let styleRange = prompt.range(of: "始终使用中文")
            let contractRange = prompt.range(of: "FINAL LANGUAGE CONTRACT")
                ?? prompt.range(of: "FINAL OUTPUT CONTRACT")
            if let styleRange, let contractRange {
                XCTAssertLessThan(styleRange.upperBound, contractRange.lowerBound)
            }
        }
    }

    func testAgentProfileLanguagePreferenceIsOnlyAnUnspecifiedFallback() {
        let request = TransformRequest(
            transcript: "帮我写一条产品更新",
            mode: .instruction,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive,
            memoryProfile: MemoryProfileContext(
                ownerProfile: OwnerProfile(
                    identityAndWork: "Product builder",
                    communicationStyle: "Direct",
                    importantTerms: "OpenType",
                    preferredLanguage: .english
                ),
                insights: .empty
            )
        )

        let prompt = PromptBuilder.systemPrompt(for: request)
        XCTAssertTrue(prompt.contains("fallback_output_language: english"))
        XCTAssertTrue(
            prompt.contains(
                "applies only when the active mode, current instruction, selected source, and current input provide no language contract or signal"
            )
        )
        XCTAssertTrue(
            prompt.contains(
                "If no language is requested, use the language most clearly implied by the command and context"
            )
        )
    }

    func testEnglishOutputPolicyRejectsLanguageLeaksAndAnsweredQuestions() {
        XCTAssertTrue(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "中国的开源大模型正在帮助更多人。",
                output: "China's open-weight models 正在帮助更多人。"
            )
        )
        XCTAssertFalse(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "中国的开源大模型正在帮助更多人。",
                output: "China's open-weight models are helping more people."
            )
        )
        XCTAssertTrue(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "什么是 OpenCloud？",
                output: "OpenCloud is a cloud platform for building applications."
            )
        )
        XCTAssertFalse(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "什么是 OpenCloud？",
                output: "What is OpenCloud?"
            )
        )
        XCTAssertTrue(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "为什么 OpenCloud 不行",
                output: "OpenCloud does not work because its API is unavailable."
            )
        )
        XCTAssertFalse(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "为什么 OpenCloud 不行",
                output: "Why doesn't OpenCloud work?"
            )
        )
        XCTAssertTrue(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "什么是 OpenCloud",
                output: "OpenCloud is a cloud platform."
            )
        )
        XCTAssertFalse(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "什么是 OpenCloud",
                output: "What is OpenCloud?"
            )
        )
        XCTAssertTrue(
            EnglishOutputPolicy.needsCorrection(
                mode: .english,
                source: "什么是 OpenCloud？",
                output: String(repeating: "This is an invented answer. ", count: 8) + "Did you mean something else?"
            )
        )
        XCTAssertFalse(
            EnglishOutputPolicy.needsCorrection(
                mode: .clean,
                source: "这是一段需要保留的中文。",
                output: "这是一段需要保留的中文。"
            )
        )
    }

    func testEnglishOutputPolicyRejectsExecutedRequestsAndCommands() {
        let cases: [(source: String, invalid: String, valid: String)] = [
            (
                "帮我写一封邮件，告诉 Henry 明天不开会。",
                "Hi Henry, tomorrow's meeting has been canceled.",
                "Help me write an email telling Henry that tomorrow's meeting has been canceled."
            ),
            (
                "帮我发一条 X，说我今天心情很好。",
                "I'm in a great mood today!",
                "Help me post on X that I'm in a great mood today."
            ),
            (
                "总结一下这段内容。",
                "This passage argues that AI changes how teams work.",
                "Summarize this passage."
            ),
            (
                "把下面这句话翻译成日语。",
                "こんにちは。",
                "Translate the following sentence into Japanese."
            )
        ]

        for item in cases {
            XCTAssertTrue(
                EnglishOutputPolicy.needsCorrection(
                    mode: .english,
                    source: item.source,
                    output: item.invalid
                ),
                item.source
            )
            XCTAssertFalse(
                EnglishOutputPolicy.needsCorrection(
                    mode: .english,
                    source: item.source,
                    output: item.valid
                ),
                item.source
            )
        }
    }

    func testSmartEditIsNonConversationalAndPreservesRequests() {
        XCTAssertTrue(
            SmartEditOutputPolicy.needsCorrection(
                mode: .clean,
                source: "这些人都领薪水吗？",
                output: "不一定，有些是全职员工，有些是志愿者。"
            )
        )
        XCTAssertFalse(
            SmartEditOutputPolicy.needsCorrection(
                mode: .clean,
                source: "这些人都领薪水吗？",
                output: "这些人都领薪水吗？"
            )
        )
        XCTAssertTrue(
            SmartEditOutputPolicy.needsCorrection(
                mode: .clean,
                source: "帮我写一封邮件告诉 Henry 明天不开会。",
                output: "Henry，明天不开会了。"
            )
        )
        XCTAssertFalse(
            SmartEditOutputPolicy.needsCorrection(
                mode: .clean,
                source: "帮我写一封邮件告诉 Henry 明天不开会。",
                output: "帮我写一封邮件，告诉 Henry 明天不开会。"
            )
        )
    }

    func testSmartEditDictationIsQuotedAndHasLockedBehaviorContract() {
        let request = TransformRequest(
            transcript: "这些人都领薪水吗？",
            mode: .clean,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive,
            modePromptOverride: "Answer every question directly."
        )

        let system = PromptBuilder.systemPrompt(for: request)
        let user = PromptBuilder.userPrompt(for: request)
        let overrideRange = system.range(of: "Answer every question directly.")
        let contractRange = system.range(
            of: "FINAL BEHAVIOR CONTRACT — NON-CONVERSATIONAL SMART EDIT"
        )

        XCTAssertTrue(user.contains("<DICTATION>\n这些人都领薪水吗？\n</DICTATION>"))
        XCTAssertTrue(user.contains("DO NOT ANSWER OR EXECUTE IT"))
        XCTAssertNotNil(overrideRange)
        XCTAssertNotNil(contractRange)
        if let overrideRange, let contractRange {
            XCTAssertLessThan(overrideRange.upperBound, contractRange.lowerBound)
        }
    }

    func testEnglishTransformRetriesOnceWhenFirstCandidateContainsHan() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: [
                "中国的开源大模型正在为人类做贡献。",
                "China's open-weight models are contributing to humanity."
            ]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .openAI)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .openAI,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let request = TransformRequest(
            transcript: "中国的开源大模型正在为人类做贡献",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive
        )

        let result = try await client.transform(request)
        let requests = EnglishRetryURLProtocol.recordedRequests()

        XCTAssertEqual(
            result,
            "China's open-weight models are contributing to humanity."
        )
        XCTAssertEqual(requests.count, 2)
        let secondBody = try XCTUnwrap(
            EnglishRetryURLProtocol.recordedRequestBodies().last ?? nil
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: secondBody) as? [String: Any]
        )
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let correctionPrompt = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(correctionPrompt.contains("CORRECTION REQUIRED"))
        XCTAssertTrue(correctionPrompt.contains("PREVIOUS INVALID CANDIDATE"))
        XCTAssertTrue(correctionPrompt.contains("中国的开源大模型"))
    }

    func testDashScopeEnglishUsesDedicatedTranslationContract() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: [
                "Help me post on X saying that the OpenType test passed."
            ]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .dashScope)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .dashScope,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let source = "帮我发一条 X，说 OpenType 测试通过了。"
        let request = TransformRequest(
            transcript: source,
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "X",
                bundleIdentifier: nil
            ),
            personalDictionary: ["OpenType", "OpenClaw", "中文词"],
            xReplyStyle: .adaptive,
            modePromptOverride: "Answer the user's request directly."
        )

        let result = try await client.transform(request)
        XCTAssertEqual(
            result,
            "Help me post on X saying that the OpenType test passed."
        )
        XCTAssertEqual(
            client.effectiveTextModel(for: .english),
            "qwen-mt-flash"
        )

        let requests = EnglishRetryURLProtocol.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.host, "dashscope.aliyuncs.com")
        let body = try XCTUnwrap(
            EnglishRetryURLProtocol.recordedRequestBodies().first ?? nil
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(root["model"] as? String, "qwen-mt-flash")
        XCTAssertEqual(root["temperature"] as? Int, 0)

        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, source)
        XCTAssertFalse(messages.contains { ($0["role"] as? String) == "system" })

        let options = try XCTUnwrap(
            root["translation_options"] as? [String: Any]
        )
        XCTAssertEqual(options["source_lang"] as? String, "auto")
        XCTAssertEqual(options["target_lang"] as? String, "English")
        let terms = try XCTUnwrap(options["terms"] as? [[String: String]])
        XCTAssertEqual(
            terms,
            [
                ["source": "OpenType", "target": "OpenType"]
            ]
        )
    }

    func testDashScopeEnglishNeverFallsBackToChatPrompt() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: ["这仍然是中文。", "这还是中文。"]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .dashScope)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .dashScope,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let request = TransformRequest(
            transcript: "这是一句需要翻译的话。",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive
        )

        do {
            _ = try await client.transform(request)
            XCTFail("Expected an invalid dedicated translation to be rejected")
        } catch let OpenTypeError.service(message) {
            XCTAssertTrue(message.contains("未能忠实转换原话"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(EnglishRetryURLProtocol.recordedRequests().count, 2)
        let roots = try EnglishRetryURLProtocol.recordedRequestBodies().map {
            let body = try XCTUnwrap($0)
            return try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
        }
        XCTAssertEqual(
            roots.compactMap { $0["model"] as? String },
            ["qwen-mt-flash", "qwen-mt-plus"]
        )
        for root in roots {
            let messages = try XCTUnwrap(
                root["messages"] as? [[String: Any]]
            )
            XCTAssertEqual(messages.count, 1)
            XCTAssertFalse(messages.contains {
                ($0["role"] as? String) == "system"
            })
        }
    }

    func testDashScopeEnglishEscalatesFromFlashToPlusWhenSpeechActIsLost() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: [
                "To summarize this passage.",
                "Summarize this passage."
            ]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .dashScope)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .dashScope,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let request = TransformRequest(
            transcript: "总结一下这段内容。",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive
        )

        let result = try await client.transformResult(request)
        XCTAssertEqual(result.text, "Summarize this passage.")
        XCTAssertEqual(result.model, "qwen-mt-plus")
        XCTAssertEqual(EnglishRetryURLProtocol.recordedRequests().count, 2)
    }

    func testEnglishTransformRetriesWhenAQuestionWasAnswered() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: [
                "OpenCloud is a cloud platform for building applications.",
                "What is OpenCloud?"
            ]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .openAI)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .openAI,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let request = TransformRequest(
            transcript: "什么是 OpenCloud？",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "WeChat",
                bundleIdentifier: "com.tencent.xinWeChat"
            ),
            personalDictionary: ["OpenCloud"],
            xReplyStyle: .adaptive
        )

        let result = try await client.transform(request)
        XCTAssertEqual(result, "What is OpenCloud?")
        XCTAssertEqual(EnglishRetryURLProtocol.recordedRequests().count, 2)

        let secondBody = try XCTUnwrap(
            EnglishRetryURLProtocol.recordedRequestBodies().last ?? nil
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: secondBody) as? [String: Any]
        )
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let correctionPrompt = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(correctionPrompt.contains("never its answer"))
        XCTAssertTrue(correctionPrompt.contains("OpenCloud is a cloud platform"))
    }

    func testEnglishTransformRetriesWhenARequestWasExecuted() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: [
                "Hi Henry, tomorrow's meeting has been canceled.",
                "Help me write an email telling Henry that tomorrow's meeting has been canceled."
            ]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .openAI)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .openAI,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let request = TransformRequest(
            transcript: "帮我写一封邮件，告诉 Henry 明天不开会。",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Mail",
                bundleIdentifier: "com.apple.mail"
            ),
            personalDictionary: ["Henry"],
            xReplyStyle: .adaptive
        )

        let result = try await client.transform(request)
        XCTAssertEqual(
            result,
            "Help me write an email telling Henry that tomorrow's meeting has been canceled."
        )
        XCTAssertEqual(EnglishRetryURLProtocol.recordedRequests().count, 2)

        let secondBody = try XCTUnwrap(
            EnglishRetryURLProtocol.recordedRequestBodies().last ?? nil
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: secondBody) as? [String: Any]
        )
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let correctionPrompt = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(correctionPrompt.contains("requested action"))
        XCTAssertTrue(correctionPrompt.contains("never return the completed artifact"))
        XCTAssertTrue(correctionPrompt.contains("Hi Henry"))
    }

    func testSmartEditRetriesWhenAQuestionWasAnswered() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: [
                "不一定，有些人领薪水，有些人是志愿者。",
                "这些人都领薪水吗？"
            ]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .openAI)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .openAI,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let request = TransformRequest(
            transcript: "这些人都领薪水吗？",
            mode: .clean,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive
        )

        let result = try await client.transform(request)
        XCTAssertEqual(result, "这些人都领薪水吗？")
        XCTAssertEqual(EnglishRetryURLProtocol.recordedRequests().count, 2)

        let secondBody = try XCTUnwrap(
            EnglishRetryURLProtocol.recordedRequestBodies().last ?? nil
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: secondBody) as? [String: Any]
        )
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let correctionPrompt = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(correctionPrompt.contains("instead of editing the speaker's words"))
        XCTAssertTrue(correctionPrompt.contains("不一定"))
    }

    func testLiveDashScopeEnglishModePreservesRequestsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set OPENTYPE_LIVE_TESTS=1 to run provider integration checks")
        }

        let vault = ProviderVault()
        guard vault.hasToken(for: .dashScope) else {
            throw XCTSkip("DashScope token is not configured in OpenType")
        }
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .dashScope,
                textModel: "qwen-plus"
            ),
            vault: vault
        )
        let cases = [
            "帮我写一个标题。",
            "总结一下这段内容。",
            "帮我发一条 X，说测试已经通过了。"
        ]

        for transcript in cases {
            let request = TransformRequest(
                transcript: transcript,
                mode: .english,
                context: CapturedContext(
                    selectedText: nil,
                    applicationName: "OpenType Integration Test",
                    bundleIdentifier: "ai.rain.opentype.tests"
                ),
                personalDictionary: ["OpenType"],
                xReplyStyle: .adaptive
            )
            let result: String
            do {
                result = try await client.transform(request)
            } catch {
                XCTFail("Live translation failed for \(transcript): \(error)")
                continue
            }
            XCTAssertFalse(
                EnglishOutputPolicy.needsCorrection(
                    mode: .english,
                    source: transcript,
                    output: result
                ),
                "Provider returned an invalid transformation: \(result)"
            )
        }
    }

    func testEnglishTransformStopsAfterOneFailedCorrection() async throws {
        EnglishRetryURLProtocol.configure(
            responseTexts: [
                "第一次仍然是中文。",
                "第二次仍然是中文。"
            ]
        )
        defer { EnglishRetryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EnglishRetryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)
        try vault.save("test-token", for: .openAI)
        let client = AIServiceClient(
            selection: AIServiceSelection(
                speechProvider: .dashScope,
                speechModel: "qwen3-asr-flash",
                transcriptionLanguage: .automatic,
                textProvider: .openAI,
                textModel: "qwen-plus"
            ),
            vault: vault,
            session: session
        )
        let request = TransformRequest(
            transcript: "请把这句话写成英文",
            mode: .english,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive
        )

        do {
            _ = try await client.transform(request)
            XCTFail("Expected the second invalid candidate to be rejected")
        } catch let OpenTypeError.service(message) {
            XCTAssertTrue(message.contains("未能忠实转换原话"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(EnglishRetryURLProtocol.recordedRequests().count, 2)
    }

    func testCustomModePromptReplacesDefaultButKeepsSystemContext() {
        let request = TransformRequest(
            transcript: "帮我回复",
            mode: .xReply,
            context: CapturedContext(
                selectedText: "Original post",
                applicationName: "Arc",
                bundleIdentifier: "company.thebrowser.Browser"
            ),
            personalDictionary: ["OpenType"],
            xReplyStyle: .sharp,
            modePromptOverride: "CUSTOM X RULE: Write exactly two sentences."
        )

        let prompt = PromptBuilder.systemPrompt(for: request)
        XCTAssertTrue(prompt.contains("CUSTOM X RULE"))
        XCTAssertFalse(prompt.contains("Most replies should be one sentence"))
        XCTAssertTrue(prompt.contains("Never add Markdown emphasis markers"))
        XCTAssertTrue(prompt.contains("Arc"))
        XCTAssertTrue(prompt.contains("Keep the edge in the idea"))
    }

    func testDefaultXReplyPromptAvoidsFormulaicAIWriting() {
        let prompt = PromptBuilder.defaultModePrompt(for: .xReply)

        XCTAssertTrue(prompt.contains("lively party conversation"))
        XCTAssertTrue(prompt.contains("profile curiosity"))
        XCTAssertTrue(prompt.contains("spoken viewpoint is optional"))
        XCTAssertTrue(prompt.contains("Do not force agreement or disagreement"))
        XCTAssertTrue(prompt.contains("miniature essay"))
        XCTAssertTrue(prompt.contains("Most replies should be one short sentence"))
        XCTAssertTrue(prompt.contains("A crisp fragment is fine"))
        XCTAssertTrue(prompt.contains("not a piece of writing"))
        XCTAssertTrue(prompt.contains("simple, everyday English"))
        XCTAssertTrue(prompt.contains("Prefer “use” over “leverage,”"))
        XCTAssertTrue(prompt.contains("slightly loose spoken grammar"))
        XCTAssertTrue(prompt.contains("Do not manufacture slang, typos"))
        XCTAssertTrue(prompt.contains("Simplify the wording, not the thought"))
        XCTAssertTrue(prompt.contains("Do not use em dashes"))
    }

    func testXReplyWithoutSpeechRequestsAnAutonomousReply() {
        let request = TransformRequest(
            transcript: "",
            mode: .xReply,
            context: CapturedContext(
                selectedText: "Small teams will build the next great companies.",
                applicationName: "X",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive
        )

        let prompt = PromptBuilder.userPrompt(for: request)
        XCTAssertTrue(prompt.contains("No spoken viewpoint was provided"))
        XCTAssertTrue(prompt.contains("Generate the reply autonomously"))
        XCTAssertTrue(prompt.contains("Small teams"))
    }

    func testXReplyUsesSelectedPostAsContext() {
        let request = TransformRequest(
            transcript: "我同意，但执行成本经常被低估",
            mode: .xReply,
            context: CapturedContext(
                selectedText: "Ideas are easy. Execution is everything.",
                applicationName: "Arc",
                bundleIdentifier: "company.thebrowser.Browser"
            ),
            personalDictionary: [],
            xReplyStyle: .concise
        )

        let prompt = PromptBuilder.userPrompt(for: request)
        XCTAssertTrue(prompt.contains("Ideas are easy"))
        XCTAssertTrue(prompt.contains("执行成本"))
    }

    func testApplicationGuidanceAdaptsForChat() {
        let guidance = PromptBuilder.applicationGuidance(
            for: CapturedContext(
                selectedText: nil,
                applicationName: "微信",
                bundleIdentifier: "com.tencent.xinWeChat"
            )
        )

        XCTAssertTrue(guidance.contains("conversational"))
        XCTAssertTrue(guidance.contains("compact"))
    }

    func testSelectionRequiredErrorIsSpecificToXReply() {
        XCTAssertEqual(
            OpenTypeError.selectionRequired(.xReply).errorDescription,
            "请先选中要回复的推文，再开始说话"
        )
    }

    func testTechnicalASRErrorBecomesHumanReadable() {
        let message = ErrorMessagePresenter.message(
            for: OpenTypeError.service(
                "<400> InternalError.Algo.InvalidParameter: does not support this input"
            )
        )

        XCTAssertEqual(message, "这段语音没有识别成功，请再说一次")
    }

    func testCopiedStateExplainsClipboardFallback() {
        XCTAssertEqual(ProcessingState.copied.title, "已复制")
        XCTAssertEqual(ProcessingState.copied.symbol, "doc.on.clipboard.fill")
    }

    func testSendCommandIsRemovedFromTail() {
        let result = SendCommandParser.parse(
            "这就是我今天的判断。按回车",
            enabled: true
        )
        XCTAssertEqual(result.text, "这就是我今天的判断。")
        XCTAssertTrue(result.pressEnter)
    }

    func testSendCommandAllowsASRTrailingPunctuationAndKeepsQuestionMark() {
        let result = SendCommandParser.parse(
            "你睡了吗？发送。",
            enabled: true
        )
        XCTAssertEqual(result.text, "你睡了吗？")
        XCTAssertTrue(result.pressEnter)
    }

    func testSendCommandDoesNotTriggerWhenSendIsPartOfTheSentence() {
        let result = SendCommandParser.parse(
            "我想聊聊发送机制。",
            enabled: true
        )
        XCTAssertEqual(result.text, "我想聊聊发送机制。")
        XCTAssertFalse(result.pressEnter)
    }

    func testVoiceModeRouterSwitchesOneDictationToEnglish() {
        let result = VoiceModeRouter.route(
            "英文：我觉得这个方向是对的",
            currentMode: .clean
        )

        XCTAssertEqual(result.mode, .english)
        XCTAssertEqual(result.text, "我觉得这个方向是对的")
    }

    func testVoiceModeRouterRecognizesChineseToEnglishName() {
        let result = VoiceModeRouter.route(
            "中转英：我觉得这个方向是对的",
            currentMode: .clean
        )

        XCTAssertEqual(InputMode.english.title, "中转英")
        XCTAssertEqual(result.mode, .english)
        XCTAssertEqual(result.text, "我觉得这个方向是对的")
    }

    func testVoiceModeRouterSwitchesOneDictationToXReply() {
        let result = VoiceModeRouter.route(
            "X Reply, 我同意，但执行成本被低估了",
            currentMode: .clean
        )

        XCTAssertEqual(result.mode, .xReply)
        XCTAssertEqual(result.text, "我同意，但执行成本被低估了")
    }

    func testVoiceModeRouterRecognizesSelectedEditName() {
        let result = VoiceModeRouter.route(
            "选中修改：缩短一半，保留数字",
            currentMode: .clean
        )

        XCTAssertEqual(result.mode, .command)
        XCTAssertEqual(result.text, "缩短一半，保留数字")
    }

    func testVoiceModeRouterDoesNotMisreadOrdinarySentence() {
        let result = VoiceModeRouter.route(
            "英文产品的增长很快",
            currentMode: .clean
        )

        XCTAssertEqual(result.mode, .clean)
        XCTAssertEqual(result.text, "英文产品的增长很快")
    }

    func testModeCycleFollowsVisibleModeOrderAndWraps() {
        XCTAssertEqual(InputMode.clean.next, .english)
        XCTAssertEqual(InputMode.english.next, .instruction)
        XCTAssertEqual(InputMode.instruction.next, .xReply)
        XCTAssertEqual(InputMode.xReply.next, .raw)
        XCTAssertEqual(InputMode.raw.next, .clean)
        XCTAssertFalse(InputMode.visibleModes.contains(.command))
    }

    func testAgentModeCreatesAnArtifactAndReceivesStructuredMemory() {
        let memory = AgentTaskMemory(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            request: "先写一条产品发布推文",
            outcome: "OpenType is live today.",
            applicationName: "X",
            referencePreview: "Launch notes"
        )
        let request = TransformRequest(
            transcript: "沿用刚才的语气，再写一条后续推文",
            mode: .instruction,
            context: CapturedContext(
                selectedText: "Optional reference",
                applicationName: "X",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive,
            agentMemory: [memory]
        )

        let system = PromptBuilder.systemPrompt(for: request)
        let user = PromptBuilder.userPrompt(for: request)
        XCTAssertTrue(system.contains("MODE: AGENT"))
        XCTAssertTrue(system.contains("exact usable result"))
        XCTAssertTrue(system.contains("draft the content only"))
        XCTAssertTrue(system.contains("current request is always authoritative"))
        XCTAssertTrue(system.contains("Never claim that anything was posted or sent"))
        XCTAssertTrue(system.contains("Preserve the user's emotional intensity"))
        XCTAssertTrue(system.contains("Do not add emoji, hashtags"))
        XCTAssertTrue(user.contains("CURRENT AGENT TASK"))
        XCTAssertTrue(user.contains("沿用刚才的语气"))
        XCTAssertTrue(user.contains("OPTIONAL SELECTED REFERENCE"))
        XCTAssertTrue(user.contains("Optional reference"))
        XCTAssertTrue(user.contains("RETRIEVED AGENT MEMORY"))
        XCTAssertTrue(user.contains("先写一条产品发布推文"))
        XCTAssertTrue(user.contains("OpenType is live today"))
    }

    func testVoiceModeRouterRecognizesCommandInputName() {
        let result = VoiceModeRouter.route(
            "命令输入：帮我写一封简短的感谢邮件",
            currentMode: .clean
        )

        XCTAssertEqual(result.mode, .instruction)
        XCTAssertEqual(result.text, "帮我写一封简短的感谢邮件")
    }

    func testVoiceModeRouterRecognizesAgentModeName() {
        let result = VoiceModeRouter.route(
            "Agent 模式：继续刚才的任务",
            currentMode: .clean
        )

        XCTAssertEqual(result.mode, .instruction)
        XCTAssertEqual(result.text, "继续刚才的任务")
    }

    func testModeChangedOverlayHasExplicitStatus() {
        XCTAssertEqual(ProcessingState.modeChanged.title, "已切换模式")
        XCTAssertEqual(
            ProcessingState.modeChanged.symbol,
            "arrow.triangle.2.circlepath"
        )
        XCTAssertEqual(
            ProcessingState.modeChanged.overlayDetail(for: .clean),
            "智能编辑"
        )
    }

    func testSmartEditRoutesBySelectionAtRecordingStart() {
        XCTAssertEqual(
            SmartEditRouter.mode(selectedMode: .clean, selectedText: nil),
            .clean
        )
        XCTAssertEqual(
            SmartEditRouter.mode(selectedMode: .clean, selectedText: "原文"),
            .command
        )
        XCTAssertEqual(
            SmartEditRouter.mode(selectedMode: .instruction, selectedText: "参考"),
            .instruction
        )
    }

    func testSelectedEditRequiresAnExplicitInstruction() {
        XCTAssertTrue(EditInstructionValidator.isExplicit("缩短一半，保留数字"))
        XCTAssertTrue(EditInstructionValidator.isExplicit("语气自然一点"))
        XCTAssertTrue(EditInstructionValidator.isExplicit("帮我把它写得更像真人"))
        XCTAssertTrue(EditInstructionValidator.isExplicit("不要这么正式"))
        XCTAssertTrue(EditInstructionValidator.isExplicit("Translate to English"))
        XCTAssertTrue(EditInstructionValidator.isExplicit("英文"))
        XCTAssertFalse(EditInstructionValidator.isExplicit(""))
        XCTAssertFalse(EditInstructionValidator.isExplicit("嗯，那个"))
        XCTAssertFalse(EditInstructionValidator.isExplicit("我今天心情很好"))
        XCTAssertFalse(EditInstructionValidator.isExplicit("我还想补充一点"))
        XCTAssertTrue(EditInstructionValidator.isExplicit("帮我补充一句具体的例子"))
    }

    func testMissingEditInstructionUsesNeutralCancelledState() {
        let state = ProcessingState.cancelled("没有明确修改指令，原文保持不变")
        XCTAssertEqual(state.title, "未执行")
        XCTAssertEqual(state.symbol, "circle.slash")
        XCTAssertEqual(
            state.overlayDetail(for: .command),
            "没有明确修改指令，原文保持不变"
        )
    }

    func testFailureOverlayShowsTheActionableReason() {
        let message = "请先选中要编辑的文字，再开始说话"
        let state = ProcessingState.failure(message)

        XCTAssertEqual(state.title, "出现问题")
        XCTAssertEqual(state.overlayDetail(for: .command), message)
    }

    func testCopiedXReplyExplainsManualPaste() {
        XCTAssertEqual(
            ProcessingState.copied.overlayDetail(for: .xReply),
            "在 X 回复框按 ⌘V 粘贴"
        )
    }

    func testSelectedEditAlwaysKeepsAClipboardCopy() {
        XCTAssertTrue(OutputDeliveryPolicy.retainsClipboardCopy(for: .command))
        XCTAssertEqual(
            ProcessingState.success.overlayDetail(for: .command),
            "已替换 · 结果也已复制"
        )
        XCTAssertEqual(
            ProcessingState.copied.overlayDetail(for: .command),
            "结果已复制，可直接粘贴"
        )
    }

    func testEveryModeKeepsItsResultOnTheClipboard() {
        for mode in InputMode.allCases {
            XCTAssertTrue(
                OutputDeliveryPolicy.retainsClipboardCopy(for: mode),
                "Expected \(mode.title) to retain a clipboard copy"
            )
        }
    }

    func testXReplyAlwaysUsesClipboardDelivery() {
        XCTAssertEqual(
            OutputDeliveryPolicy.strategy(
                for: .xReply,
                automaticallyInsert: true
            ),
            .clipboard
        )
        XCTAssertEqual(
            OutputDeliveryPolicy.strategy(
                for: .xReply,
                automaticallyInsert: false
            ),
            .clipboard
        )
    }

    func testRegularModesRespectAutomaticInsertSetting() {
        XCTAssertEqual(
            OutputDeliveryPolicy.strategy(
                for: .clean,
                automaticallyInsert: true
            ),
            .automaticInsert
        )
        XCTAssertEqual(
            OutputDeliveryPolicy.strategy(
                for: .english,
                automaticallyInsert: false
            ),
            .clipboard
        )
    }

    func testXReplyNeverRequiresSelectionAtModelLayer() {
        XCTAssertTrue(InputMode.xReply.requiresSelection)
        XCTAssertFalse(InputMode.instruction.requiresSelection)
        XCTAssertFalse(InputMode.english.requiresSelection)
    }

    func testCommandInputNeverTriggersAutomaticEnter() {
        XCTAssertFalse(
            OutputDeliveryPolicy.permitsAutomaticEnter(for: .instruction)
        )
        XCTAssertFalse(
            OutputDeliveryPolicy.permitsAutomaticEnter(for: .xReply)
        )
        XCTAssertTrue(
            OutputDeliveryPolicy.permitsAutomaticEnter(for: .clean)
        )
    }

    func testDoubleTapDetectorTriggersWithinThreshold() {
        var detector = DoubleTapDetector(threshold: 0.45)
        XCTAssertFalse(detector.registerTap(at: 10))
        XCTAssertTrue(detector.registerTap(at: 10.4))
        XCTAssertNil(detector.lastTap)
    }

    func testDoubleTapDetectorRejectsSlowSecondTap() {
        var detector = DoubleTapDetector(threshold: 0.45)
        XCTAssertFalse(detector.registerTap(at: 10))
        XCTAssertFalse(detector.registerTap(at: 10.6))
        XCTAssertEqual(detector.lastTap, 10.6)
    }

    func testHotKeyPresetsExposeConflictFreeControlShiftOption() {
        XCTAssertEqual(HotKeyPreset.controlShiftSpace.title, "⌃⇧ Space")
        XCTAssertEqual(
            HotKeyPreset.controlShiftSpace.keys,
            ["⌃", "⇧", "Space"]
        )
        XCTAssertFalse(HotKeyPreset.controlShiftSpace.usesDoubleModifierTap)
        XCTAssertTrue(HotKeyPreset.doubleControl.usesDoubleModifierTap)
        XCTAssertTrue(HotKeyPreset.leftOption.usesModifierOnlyEventTap)
        XCTAssertFalse(HotKeyPreset.leftOption.usesDoubleModifierTap)
        XCTAssertTrue(HotKeyPreset.leftOption.usesOptionHybridGesture)
        XCTAssertEqual(HotKeyPreset.leftOption.keys, ["左 Option"])
    }

    @MainActor
    func testSelectedHotKeyPersists() {
        let suiteName = "OpenTypeTests.HotKey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.hotKeyPreset, .leftOption)

        configuration.hotKeyPreset = .controlShiftSpace
        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.hotKeyPreset, .controlShiftSpace)
    }

    @MainActor
    func testLegacySelectedEditModeMigratesToSmartEdit() {
        let suiteName = "OpenTypeTests.SmartEditMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(InputMode.command.rawValue, forKey: "selectedMode")

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.selectedMode, .clean)
    }

    @MainActor
    func testFeedbackSoundSettingPersists() {
        let suiteName = "OpenTypeTests.Sound.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertTrue(configuration.playFeedbackSounds)
        configuration.playFeedbackSounds = false

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertFalse(reloaded.playFeedbackSounds)
        XCTAssertTrue(reloaded.isMuted)
    }

    func testFeedbackSoundCuesCoverTheVoiceLifecycle() {
        XCTAssertEqual(
            FeedbackSoundCue.allCases.map(\.resourceName),
            [
                "OpenTypeReady",
                "OpenTypeRelease",
                "OpenTypeDone",
                "OpenTypeIssue"
            ]
        )
        XCTAssertEqual(
            Set(FeedbackSoundCue.allCases.map(\.resourceName)).count,
            FeedbackSoundCue.allCases.count
        )
        XCTAssertTrue(FeedbackSoundCue.allCases.allSatisfy { $0.volume < 0.75 })
    }

    @MainActor
    func testAgentMemorySettingPersists() {
        let suiteName = "OpenTypeTests.AgentMemorySetting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertTrue(configuration.agentMemoryEnabled)
        configuration.agentMemoryEnabled = false

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertFalse(reloaded.agentMemoryEnabled)
    }

    @MainActor
    func testColorThemeDefaultsToOceanAndPersistsSelection() {
        let suiteName = "OpenTypeTests.ColorTheme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.colorTheme, .ocean)
        configuration.colorTheme = .violet

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.colorTheme, .violet)
        XCTAssertEqual(AppColorTheme.allCases.count, 6)
        XCTAssertEqual(
            Set(AppColorTheme.allCases.map(\.title)).count,
            AppColorTheme.allCases.count
        )
    }

    @MainActor
    func testInterfaceLanguageDefaultsToChineseAndPersistsEnglish() {
        let suiteName = "OpenTypeTests.InterfaceLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            OpenTypeL10n.language = .chinese
        }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.interfaceLanguage, .chinese)
        configuration.interfaceLanguage = .english

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.interfaceLanguage, .english)
        XCTAssertEqual(InputMode.clean.title, "Smart Edit")
    }

    @MainActor
    func testAutomaticOwnerProfileUpdateSettingPersists() {
        let suiteName = "OpenTypeTests.AutoProfileSetting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertTrue(configuration.automaticOwnerProfileUpdates)
        configuration.automaticOwnerProfileUpdates = false

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertFalse(reloaded.automaticOwnerProfileUpdates)
    }

    func testAutomaticLearningNeverMutatesConfirmedProfile() {
        let profile = OwnerProfile(
            identityAndWork: "我是 Rain，正在做 AI Agent 产品。\nOpenType 自动归纳的近期任务：内容写作。",
            communicationStyle: "简洁、直接。\nOpenType 自动归纳的表达偏好：主要使用中文。",
            importantTerms: "OpenType、OpenClaw\nOpenType 自动归纳的术语：Agent。",
            preferredLanguage: .chinese,
            updatedAt: nil
        )
        let insights = MemoryInsights(
            observedTaskCount: 100,
            commonTerms: ["Agent", "的话", "Open"],
            taskDomains: ["产品与 AI 工具", "内容写作与编辑"],
            languagePattern: "主要使用中文，经常混合英文专业词",
            stylePreferences: ["自然、口语化、低 AI 味"],
            updatedAt: Date()
        )

        let updated = OwnerProfileAutoUpdater.merging(
            profile: profile,
            insights: insights,
            personalDictionary: ["Rain", "OpenType", "OpenClaw"]
        )

        XCTAssertEqual(updated.identityAndWork, "我是 Rain，正在做 AI Agent 产品。")
        XCTAssertEqual(updated.communicationStyle, "简洁、直接。")
        XCTAssertEqual(updated.importantTerms, "OpenType、OpenClaw")
        XCTAssertEqual(updated.preferredLanguage, .chinese)
        XCTAssertFalse(updated.identityAndWork.contains("自动归纳"))
        XCTAssertFalse(updated.communicationStyle.contains("主要使用中文"))
    }

    func testLegacyProfileExtractsOnlyExplicitDefaultLanguage() {
        let explicit = OwnerProfileAutoUpdater.removingLegacyManagedLines(
            from: OwnerProfile(
                identityAndWork: "AI 产品经理",
                communicationStyle: "中文为主，简洁直接。",
                importantTerms: "OpenType"
            )
        )
        XCTAssertEqual(explicit.preferredLanguage, .chinese)

        let inferredOnly = OwnerProfileAutoUpdater.removingLegacyManagedLines(
            from: OwnerProfile(
                identityAndWork: "AI 产品经理",
                communicationStyle: "OpenType 自动归纳的表达偏好：主要使用中文。",
                importantTerms: "OpenType"
            )
        )
        XCTAssertEqual(inferredOnly.preferredLanguage, .followInput)
    }

    @MainActor
    func testAutomaticLearnedPreferencesUpdateAtOneHundredWithoutRewritingProfile() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenType-AutoProfile-\(UUID().uuidString).sqlite3")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
            }
        }

        let store = AgentMemoryStore(fileURL: fileURL)
        let confirmedProfile = OwnerProfile(
            identityAndWork: "我在做 AI Agent 产品",
            communicationStyle: "简洁、直接",
            importantTerms: "OpenType",
            preferredLanguage: .chinese
        )
        XCTAssertTrue(store.updateOwnerProfile(confirmedProfile))
        let history = (0..<100).map { index in
            HistoryEntry(
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                mode: .clean,
                applicationName: "OpenType",
                transcript: "请帮我优化 OpenType 产品文案，要简洁直接",
                result: "完成 \(index)",
                contextPreview: nil
            )
        }
        store.importHistoryIfNeeded(history)

        XCTAssertEqual(store.eventCount, 100)
        XCTAssertTrue(
            store.refreshOwnerProfileIfNeeded(
                enabled: true,
                personalDictionary: ["OpenType"]
            )
        )
        XCTAssertEqual(store.lastAutomaticProfileEventCount, 100)
        XCTAssertEqual(store.ownerProfile.identityAndWork, confirmedProfile.identityAndWork)
        XCTAssertEqual(store.ownerProfile.communicationStyle, confirmedProfile.communicationStyle)
        XCTAssertEqual(store.ownerProfile.importantTerms, confirmedProfile.importantTerms)
        XCTAssertEqual(store.ownerProfile.preferredLanguage, .chinese)
        XCTAssertFalse(store.learnedPreferences.taskDomains.isEmpty)
        XCTAssertEqual(
            store.profileContextForPrompt().insights,
            store.learnedPreferences
        )
        XCTAssertFalse(
            store.refreshOwnerProfileIfNeeded(
                enabled: true,
                personalDictionary: ["OpenType"]
            )
        )

        let reloaded = AgentMemoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.ownerProfile.preferredLanguage, .chinese)
        XCTAssertEqual(reloaded.learnedPreferences, store.learnedPreferences)
    }

    func testLocalMemoryEmbeddingRoundTripPreservesVector() {
        let original: [Float] = [0.25, -0.5, 1.75, 0]
        let decoded = LocalMemoryEmbedding.decoded(
            LocalMemoryEmbedding.encoded(original)
        )
        XCTAssertEqual(decoded, original)
    }

    @MainActor
    func testMemoryRetrieverKeepsRecentContextAndFindsOlderRelevantTask() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenType-Retrieval-\(UUID().uuidString).sqlite3")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
            }
        }

        let store = AgentMemoryStore(fileURL: fileURL)
        let relevant = MemoryEvent(
            createdAt: Date(timeIntervalSince1970: 100),
            mode: .instruction,
            applicationName: "X",
            bundleIdentifier: nil,
            rawTranscript: "帮我写一条 OpenType 产品发布推文",
            effectiveInput: "帮我写一条 OpenType 产品发布推文",
            selectedContext: nil,
            result: "OpenType is live."
        )
        let unrelatedOld = MemoryEvent(
            createdAt: Date(timeIntervalSince1970: 200),
            mode: .instruction,
            applicationName: "Calendar",
            bundleIdentifier: nil,
            rawTranscript: "安排下周团队会议",
            effectiveInput: "安排下周团队会议",
            selectedContext: nil,
            result: "会议计划"
        )
        let recentOne = MemoryEvent(
            createdAt: Date(timeIntervalSince1970: 300),
            mode: .clean,
            applicationName: "Notes",
            bundleIdentifier: nil,
            rawTranscript: "整理今天的待办事项",
            effectiveInput: "整理今天的待办事项",
            selectedContext: nil,
            result: "待办清单"
        )
        let recentTwo = MemoryEvent(
            createdAt: Date(timeIntervalSince1970: 400),
            mode: .clean,
            applicationName: "Mail",
            bundleIdentifier: nil,
            rawTranscript: "回复这封感谢邮件",
            effectiveInput: "回复这封感谢邮件",
            selectedContext: nil,
            result: "感谢邮件"
        )
        [relevant, unrelatedOld, recentOne, recentTwo].forEach(store.record)

        let retrieved = store.memoriesForPrompt(
            query: "再写一条 OpenType 上线的 X 推文",
            selectedContext: nil,
            applicationName: "X",
            maximumEntries: 3
        )
        let ids = Set(retrieved.map(\.id))

        XCTAssertTrue(ids.contains(relevant.id))
        XCTAssertTrue(ids.contains(recentOne.id))
        XCTAssertTrue(ids.contains(recentTwo.id))
        XCTAssertFalse(ids.contains(unrelatedOld.id))
        XCTAssertEqual(retrieved.map(\.id), [relevant.id, recentOne.id, recentTwo.id])
    }

    @MainActor
    func testAgentMemoryPersistsStructuredTasksAndUsesChronologicalPromptOrder() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenType-AgentMemory-\(UUID().uuidString).sqlite3")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    atPath: fileURL.path + suffix
                )
            }
        }

        let store = AgentMemoryStore(fileURL: fileURL, maximumEntries: 3)
        let first = AgentTaskMemory(
            createdAt: Date(timeIntervalSince1970: 100),
            request: "先写第一条",
            outcome: "第一条结果",
            applicationName: "X",
            referencePreview: nil
        )
        let second = AgentTaskMemory(
            createdAt: Date(timeIntervalSince1970: 200),
            request: "再写第二条",
            outcome: "第二条结果",
            applicationName: "X",
            referencePreview: "参考内容"
        )
        store.add(first)
        store.add(second)

        XCTAssertEqual(store.entries.map(\.request), ["再写第二条", "先写第一条"])
        XCTAssertEqual(
            store.entriesForPrompt().map(\.request),
            ["先写第一条", "再写第二条"]
        )
        XCTAssertEqual(store.eventCount, 2)

        store.updateOwnerProfile(
            OwnerProfile(
                identityAndWork: "我在做 AI Agent 产品",
                communicationStyle: "简洁、直接、口语化",
                importantTerms: "OpenType, OpenClaw",
                preferredLanguage: .chinese,
                updatedAt: nil
            )
        )

        let reloaded = AgentMemoryStore(fileURL: fileURL, maximumEntries: 3)
        XCTAssertEqual(reloaded.entries, store.entries)
        XCTAssertEqual(
            reloaded.ownerProfile.identityAndWork,
            "我在做 AI Agent 产品"
        )
        XCTAssertEqual(reloaded.ownerProfile.preferredLanguage, .chinese)

        reloaded.clear()
        XCTAssertTrue(reloaded.entries.isEmpty)
        XCTAssertEqual(reloaded.eventCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(
            reloaded.ownerProfile.communicationStyle,
            "简洁、直接、口语化"
        )
    }

    @MainActor
    func testLegacyProfileDatabaseMigratesWithoutLosingConfirmedFields() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenType-LegacyProfile-\(UUID().uuidString).sqlite3")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
            }
        }

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fileURL.path, &database), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE owner_profile (
            id INTEGER PRIMARY KEY CHECK(id = 1),
            identity_and_work TEXT NOT NULL DEFAULT '',
            communication_style TEXT NOT NULL DEFAULT '',
            important_terms TEXT NOT NULL DEFAULT '',
            updated_at REAL
        );
        INSERT INTO owner_profile (
            id, identity_and_work, communication_style, important_terms, updated_at
        ) VALUES (
            1,
            'AI 产品经理\nOpenType 自动归纳的近期任务：写推文',
            '中文为主，简洁直接\nOpenType 自动归纳的表达偏好：口语化',
            'OpenType\nOpenType 自动归纳的术语：Mingle',
            100
        );
        """
        XCTAssertEqual(sqlite3_exec(database, legacySchema, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(database), SQLITE_OK)
        database = nil

        let migrated = AgentMemoryStore(fileURL: fileURL)

        XCTAssertTrue(migrated.databaseReady)
        XCTAssertEqual(migrated.ownerProfile.identityAndWork, "AI 产品经理")
        XCTAssertEqual(migrated.ownerProfile.communicationStyle, "中文为主，简洁直接")
        XCTAssertEqual(migrated.ownerProfile.importantTerms, "OpenType")
        XCTAssertEqual(migrated.ownerProfile.preferredLanguage, .chinese)

        let reloaded = AgentMemoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.ownerProfile.identityAndWork, "AI 产品经理")
        XCTAssertEqual(reloaded.ownerProfile.communicationStyle, "中文为主，简洁直接")
        XCTAssertEqual(reloaded.ownerProfile.importantTerms, "OpenType")
        XCTAssertEqual(reloaded.ownerProfile.preferredLanguage, .chinese)
    }

    func testMemoryInsightsLearnOnlyRepeatedSignals() {
        let events = [
            MemoryEvent(
                mode: .instruction,
                applicationName: "OpenType",
                bundleIdentifier: nil,
                rawTranscript: "帮我写一个 OpenType 产品方案，要简洁直接",
                effectiveInput: "帮我写一个 OpenType 产品方案，要简洁直接",
                selectedContext: nil,
                result: "result 1"
            ),
            MemoryEvent(
                mode: .instruction,
                applicationName: "OpenType",
                bundleIdentifier: nil,
                rawTranscript: "再写一个 OpenType Agent 的产品说明，语气简洁直接",
                effectiveInput: "再写一个 OpenType Agent 的产品说明，语气简洁直接",
                selectedContext: nil,
                result: "result 2"
            ),
            MemoryEvent(
                mode: .clean,
                applicationName: "Notes",
                bundleIdentifier: nil,
                rawTranscript: "我觉得 OpenType 这个 AI 输入工具还可以继续优化",
                effectiveInput: "我觉得 OpenType 这个 AI 输入工具还可以继续优化",
                selectedContext: nil,
                result: "result 3"
            )
        ]

        let insights = MemoryInsightsAnalyzer.analyze(events)
        XCTAssertTrue(insights.commonTerms.contains("OpenType"))
        XCTAssertTrue(insights.taskDomains.contains("产品与 AI 工具"))
        XCTAssertTrue(insights.stylePreferences.contains("简洁、直接"))
        XCTAssertFalse(insights.commonTerms.contains("方案"))
    }

    func testExplicitProfileAndInferredMemoryStaySeparatedInPrompt() {
        let request = TransformRequest(
            transcript: "帮我写一条产品介绍",
            mode: .instruction,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "Notes",
                bundleIdentifier: nil
            ),
            personalDictionary: [],
            xReplyStyle: .adaptive,
            memoryProfile: MemoryProfileContext(
                ownerProfile: OwnerProfile(
                    identityAndWork: "我在做 AI Agent 产品",
                    communicationStyle: "像和朋友说话一样直接",
                    importantTerms: "OpenType",
                    updatedAt: Date()
                ),
                insights: MemoryInsights(
                    observedTaskCount: 8,
                    commonTerms: ["OpenType", "Agent"],
                    taskDomains: ["产品与 AI 工具"],
                    languagePattern: "主要使用中文",
                    stylePreferences: ["简洁、直接"],
                    updatedAt: Date()
                )
            )
        )

        let prompt = PromptBuilder.systemPrompt(for: request)
        XCTAssertTrue(prompt.contains("EXPLICIT PROFILE"))
        XCTAssertTrue(prompt.contains("OFFLINE INFERENCES"))
        XCTAssertTrue(prompt.contains("我在做 AI Agent 产品"))
        XCTAssertTrue(prompt.contains("BEHAVIORAL HINTS, NOT USER-STATED FACTS"))
        XCTAssertTrue(prompt.contains("current request always has highest priority"))
    }

    @MainActor
    func testLiveCaptionSettingPersists() {
        let suiteName = "OpenTypeTests.LiveCaptions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertTrue(configuration.liveCaptionsEnabled)
        configuration.liveCaptionsEnabled = false

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertFalse(reloaded.liveCaptionsEnabled)
    }

    @MainActor
    func testTranscriptionLanguageSettingPersists() {
        let suiteName = "OpenTypeTests.TranscriptionLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.transcriptionLanguage, .automatic)
        configuration.transcriptionLanguage = .japanese

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.transcriptionLanguage, .japanese)
        XCTAssertEqual(reloaded.serviceSelection.transcriptionLanguage, .japanese)
    }

    func testMainstreamTranscriptionLanguagesMapAcrossProviders() {
        XCTAssertGreaterThanOrEqual(TranscriptionLanguage.allCases.count, 25)
        XCTAssertNil(TranscriptionLanguage.automatic.code(for: .dashScope))
        XCTAssertEqual(TranscriptionLanguage.chinese.code(for: .dashScope), "zh")
        XCTAssertEqual(TranscriptionLanguage.japanese.code(for: .openAI), "ja")
        XCTAssertEqual(TranscriptionLanguage.french.code(for: .elevenLabs), "fr")
        XCTAssertEqual(TranscriptionLanguage.cantonese.code(for: .dashScope), "yue")
        XCTAssertEqual(TranscriptionLanguage.cantonese.code(for: .openAI), "zh")
        XCTAssertEqual(TranscriptionLanguage.filipino.code(for: .dashScope), "fil")
        XCTAssertEqual(TranscriptionLanguage.filipino.code(for: .openAI), "tl")
        XCTAssertEqual(TranscriptionLanguage.automatic.appleLocaleIdentifier, "zh-CN")
        XCTAssertEqual(TranscriptionLanguage.japanese.appleLocaleIdentifier, "ja-JP")
        XCTAssertEqual(TranscriptionLanguage.english.appleLocaleIdentifier, "en-US")
    }

    @MainActor
    func testCustomPromptPersistsAndCanReset() {
        let suiteName = "OpenTypeTests.Prompt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        XCTAssertFalse(configuration.hasCustomPrompt(for: .clean))
        configuration.updatePrompt("My custom clean prompt", for: .clean)

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertEqual(
            reloaded.promptOverride(for: .clean),
            "My custom clean prompt"
        )

        reloaded.resetPrompt(for: .clean)
        XCTAssertFalse(reloaded.hasCustomPrompt(for: .clean))
        XCTAssertEqual(
            reloaded.promptText(for: .clean),
            PromptBuilder.defaultModePrompt(for: .clean)
        )
    }

    func testLightTranscriptionUsesMinimalCleanupAndExposesItsPrompt() {
        let prompt = PromptBuilder.defaultModePrompt(for: .raw)

        XCTAssertTrue(InputMode.raw.supportsCustomPrompt)
        XCTAssertEqual(InputMode.raw.title, "文字转写")
        XCTAssertTrue(prompt.contains("MODE: LIGHT TRANSCRIPTION"))
        XCTAssertTrue(prompt.contains("minimal cleanup, not rewriting"))
        XCTAssertTrue(prompt.contains("Preserve code-switching exactly"))
        XCTAssertTrue(prompt.contains("never translate the English into Chinese"))
        XCTAssertTrue(prompt.contains("technical terms, acronyms, capitalization"))
        XCTAssertTrue(prompt.contains("phonetic Chinese approximation"))
        XCTAssertTrue(prompt.contains("Remove only obvious speech fillers"))
        XCTAssertTrue(prompt.contains("Do not summarize, reorganize ideas"))
        XCTAssertTrue(prompt.contains("When unsure whether a word is meaningful, keep it"))
        XCTAssertTrue(InputMode.clean.supportsCustomPrompt)
        XCTAssertTrue(InputMode.instruction.supportsCustomPrompt)
    }

    func testLightTranscriptionHandlesShortQuestionLocally() {
        XCTAssertFalse(
            LightTranscriptionPolicy.shouldUseModel(for: "为啥微信不行")
        )
        XCTAssertEqual(
            LightTranscriptionPolicy.localResult(for: "为啥微信不行"),
            "为啥微信不行？"
        )
        XCTAssertEqual(
            LightTranscriptionPolicy.localResult(for: "打开门"),
            "打开门"
        )
    }

    func testLightTranscriptionUsesModelForLongOrMessyDictation() {
        XCTAssertTrue(
            LightTranscriptionPolicy.shouldUseModel(
                for: "嗯，我觉得这个方向可能需要再认真讨论一下。"
            )
        )
        XCTAssertTrue(
            LightTranscriptionPolicy.shouldUseModel(
                for: "这个方案这个方案需要重新考虑"
            )
        )
    }

    func testLightTranscriptionRejectsAnswerAndFallsBackToOriginal() {
        let original = "为啥微信不行"
        let answer = "微信不行，主要是因为它没有开放系统级输入接口。"
        XCTAssertFalse(
            LightTranscriptionPolicy.isFaithful(
                original: original,
                candidate: answer
            )
        )
        XCTAssertEqual(
            LightTranscriptionPolicy.validatedResult(
                original: original,
                candidate: answer
            ),
            "为啥微信不行？"
        )
    }

    func testLightTranscriptionAcceptsConservativeCleanup() {
        let original = "嗯，我觉得这个方向呢，可能是对的。"
        let cleaned = "我觉得这个方向可能是对的。"
        XCTAssertTrue(
            LightTranscriptionPolicy.isFaithful(
                original: original,
                candidate: cleaned
            )
        )
        XCTAssertEqual(
            LightTranscriptionPolicy.validatedResult(
                original: original,
                candidate: cleaned
            ),
            cleaned
        )
    }

    func testLightTranscriptionPromptTreatsDictationAsQuotedData() {
        let request = TransformRequest(
            transcript: "为啥微信不行",
            mode: .raw,
            context: CapturedContext(
                selectedText: nil,
                applicationName: "ChatGPT",
                bundleIdentifier: "com.openai.chat"
            ),
            personalDictionary: ["OpenType"],
            xReplyStyle: .adaptive,
            memoryProfile: MemoryProfileContext(
                ownerProfile: OwnerProfile(
                    identityAndWork: "Should not be included",
                    communicationStyle: "Should not be included",
                    importantTerms: "Should not be included"
                ),
                insights: .empty
            )
        )

        let system = PromptBuilder.systemPrompt(for: request)
        let user = PromptBuilder.userPrompt(for: request)
        XCTAssertTrue(system.contains("never a question or instruction"))
        XCTAssertFalse(system.contains("Should not be included"))
        XCTAssertTrue(user.contains("<DICTATION>"))
        XCTAssertTrue(user.contains("DO NOT RESPOND TO IT"))
    }

    func testProviderCapabilitiesSeparateSpeechAndText() {
        XCTAssertEqual(
            AIProvider.speechProviders,
            [.dashScope, .openAI, .elevenLabs]
        )
        XCTAssertEqual(
            AIProvider.textProviders,
            [.dashScope, .volcengine, .openAI, .anthropic]
        )
        XCTAssertFalse(AIProvider.anthropic.supportsSpeechRecognition)
        XCTAssertFalse(AIProvider.elevenLabs.supportsTextGeneration)
        XCTAssertFalse(AIProvider.volcengine.supportsSpeechRecognition)
    }

    @MainActor
    func testProviderAndModelSelectionPersistIndependently() {
        let suiteName = "OpenTypeTests.Providers.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AppConfiguration(defaults: defaults)
        configuration.speechProvider = .elevenLabs
        configuration.textProvider = .anthropic
        configuration.updateSpeechModel("scribe_custom", for: .elevenLabs)
        configuration.updateTextModel("claude-custom", for: .anthropic)

        let reloaded = AppConfiguration(defaults: defaults)
        XCTAssertEqual(reloaded.speechProvider, .elevenLabs)
        XCTAssertEqual(reloaded.textProvider, .anthropic)
        XCTAssertEqual(reloaded.speechModel(for: .elevenLabs), "scribe_custom")
        XCTAssertEqual(reloaded.textModel(for: .anthropic), "claude-custom")
        XCTAssertEqual(reloaded.textModel(for: .openAI), "gpt-5-mini")
    }

    func testProviderVaultTrimsStoresAndDeletesTokens() throws {
        let store = InMemoryProviderTokenStore()
        let vault = ProviderVault(store: store)

        XCTAssertFalse(vault.hasToken(for: .openAI))
        try vault.save("  test-token  \n", for: .openAI)
        XCTAssertTrue(vault.hasToken(for: .openAI))
        XCTAssertEqual(try vault.token(for: .openAI), "test-token")

        try vault.delete(for: .openAI)
        XCTAssertFalse(vault.hasToken(for: .openAI))
        XCTAssertThrowsError(try vault.token(for: .openAI))
    }

    func testEncryptedFileProviderTokenStorePersistsWithoutPlaintext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenType-ProviderVault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = EncryptedFileProviderTokenStore(directoryURL: directory)
        try store.save("super-secret-token", provider: .openAI)

        let reloaded = EncryptedFileProviderTokenStore(directoryURL: directory)
        XCTAssertEqual(
            try reloaded.read(provider: .openAI),
            "super-secret-token"
        )
        let vaultData = try Data(contentsOf: store.vaultURL)
        XCTAssertFalse(
            String(data: vaultData, encoding: .utf8)?
                .contains("super-secret-token") == true
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.vaultURL.path
        )
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)

        try reloaded.delete(provider: .openAI)
        XCTAssertNil(try reloaded.read(provider: .openAI))
    }

    func testImmutableAuditStoreAppendsWithoutRewritingEarlierEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenType-Audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let requestID = UUID()
        let timestamp = Date(
            timeIntervalSince1970: floor(Date().timeIntervalSince1970)
        )
        let first = ImmutableAuditEvent(
            requestId: requestID,
            createdAt: timestamp,
            status: .recognized,
            mode: .raw,
            rawTranscript: "为啥微信不行",
            effectiveInput: "为啥微信不行",
            selectedContext: nil,
            result: nil,
            provider: "dashScope",
            model: "qwen3-asr-flash",
            error: nil
        )
        let second = ImmutableAuditEvent(
            requestId: requestID,
            createdAt: timestamp,
            status: .completed,
            mode: .raw,
            rawTranscript: "为啥微信不行",
            effectiveInput: "为啥微信不行",
            selectedContext: nil,
            result: "为啥微信不行？",
            provider: nil,
            model: nil,
            error: nil
        )

        let store = ImmutableAuditStore(directoryURL: directory)
        try store.append(first)
        let firstBytes = try Data(contentsOf: store.fileURL)
        try store.append(second)
        let completeBytes = try Data(contentsOf: store.fileURL)

        XCTAssertTrue(completeBytes.starts(with: firstBytes))
        XCTAssertEqual(store.recent(limit: 10), [first, second])
        XCTAssertEqual(store.recent(limit: 1), [second])

        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.fileURL.path
        )
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }

    func testImmutableAuditEventMatchesSharedSchemaFieldNamesAndModeIDs() throws {
        let expectedModeIDs: [InputMode: String] = [
            .clean: "smartEdit",
            .english: "english",
            .instruction: "agent",
            .xReply: "xReply",
            .command: "selectedEdit",
            .raw: "transcribe"
        ]
        let allowedKeys: Set<String> = [
            "schemaVersion", "eventId", "requestId", "createdAt", "platform",
            "status", "mode", "rawTranscript", "effectiveInput",
            "selectedContext", "result", "provider", "model", "error",
            "supersedesEventId"
        ]

        for (mode, expectedID) in expectedModeIDs {
            let event = ImmutableAuditEvent(
                requestId: UUID(),
                status: .completed,
                mode: mode,
                rawTranscript: "原始输入",
                effectiveInput: "有效输入",
                selectedContext: nil,
                result: "结果",
                provider: "dashScope",
                model: "qwen-plus",
                error: nil
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoder.encode(event))
                    as? [String: Any]
            )

            XCTAssertNotNil(object["eventId"])
            XCTAssertNil(object["id"])
            XCTAssertEqual(object["mode"] as? String, expectedID)
            XCTAssertEqual(object["platform"] as? String, "macOS")
            XCTAssertEqual(object["schemaVersion"] as? Int, 1)
            XCTAssertTrue(Set(object.keys).isSubset(of: allowedKeys))
            XCTAssertNil(object["applicationName"])
            XCTAssertNil(object["applicationId"])
        }
    }

    func testImmutableAuditEventStillReadsLegacyMacRecords() throws {
        let eventID = UUID()
        let requestID = UUID()
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "id": "\(eventID.uuidString)",
          "requestId": "\(requestID.uuidString)",
          "createdAt": "2026-08-01T00:00:00Z",
          "platform": "macOS",
          "status": "completed",
          "mode": "raw",
          "rawTranscript": "旧记录",
          "applicationName": "Notes",
          "applicationId": "com.apple.Notes"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(
            ImmutableAuditEvent.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(event.id, eventID)
        XCTAssertEqual(event.requestId, requestID)
        XCTAssertEqual(event.mode, "raw")
        XCTAssertEqual(event.rawTranscript, "旧记录")
        XCTAssertNil(event.supersedesEventId)
    }

}

private final class InMemoryProviderTokenStore: ProviderTokenStoring {
    private var tokens: [AIProvider: String] = [:]

    func read(provider: AIProvider) throws -> String? {
        tokens[provider]
    }

    func save(_ token: String, provider: AIProvider) throws {
        tokens[provider] = token
    }

    func delete(provider: AIProvider) throws {
        tokens.removeValue(forKey: provider)
    }
}

private final class EnglishRetryURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseTexts: [String] = []
    private static var requests: [URLRequest] = []
    private static var requestBodies: [Data?] = []

    static func configure(responseTexts: [String]) {
        lock.lock()
        self.responseTexts = responseTexts
        requests = []
        requestBodies = []
        lock.unlock()
    }

    static func reset() {
        configure(responseTexts: [])
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func recordedRequestBodies() -> [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return requestBodies
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let text: String?
        let body = Self.bodyData(for: request)
        Self.lock.lock()
        Self.requests.append(request)
        Self.requestBodies.append(body)
        text = Self.responseTexts.isEmpty
            ? nil
            : Self.responseTexts.removeFirst()
        Self.lock.unlock()

        guard let text else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        let payload: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": text
                    ]
                ]
            ]
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.cannotParseResponse)
            )
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data.isEmpty ? nil : data
    }
}
