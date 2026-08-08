import Foundation
import NaturalLanguage

struct IndexedMemoryEvent {
    let event: MemoryEvent
    let embedding: [Float]?
}

enum LocalMemoryEmbedding {
    private static let maximumDocumentCharacters = 2_400

    static func vector(for event: MemoryEvent) -> [Float]? {
        vector(for: document(for: event))
    }

    static func vector(for text: String) -> [Float]? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let embedding = NLEmbedding.sentenceEmbedding(
            for: .simplifiedChinese
        ) else { return nil }
        return embedding.vector(
            for: String(normalized.prefix(maximumDocumentCharacters))
        )?.map(Float.init)
    }

    static func encoded(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decoded(_ data: Data) -> [Float]? {
        guard !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Float>.size) else {
            return nil
        }
        var values = [Float](
            repeating: 0,
            count: data.count / MemoryLayout<Float>.size
        )
        _ = values.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        return values
    }

    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            dot += left * right
            lhsMagnitude += left * left
            rhsMagnitude += right * right
        }
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return nil }
        return dot / sqrt(lhsMagnitude * rhsMagnitude)
    }

    private static func document(for event: MemoryEvent) -> String {
        [
            event.effectiveInput,
            event.selectedContext.map { String($0.prefix(800)) },
            String(event.result.prefix(1_000))
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}

enum LocalMemoryRetriever {
    static func retrieve(
        from candidates: [IndexedMemoryEvent],
        query: String,
        selectedContext: String?,
        applicationName: String,
        maximumEntries: Int = 8,
        recentEntryCount: Int = 2
    ) -> [MemoryEvent] {
        guard maximumEntries > 0, !candidates.isEmpty else { return [] }

        let queryText = [query, selectedContext]
            .compactMap { $0 }
            .joined(separator: "\n")
        let queryFeatures = lexicalFeatures(in: queryText)
        let queryEmbedding = LocalMemoryEmbedding.vector(for: queryText)

        let recentLimit = min(recentEntryCount, maximumEntries, candidates.count)
        let recent = Array(candidates.prefix(recentLimit))
        let recentIDs = Set(recent.map { $0.event.id })
        let relevantLimit = maximumEntries - recent.count

        let ranked = candidates.enumerated()
            .filter { !recentIDs.contains($0.element.event.id) }
            .map { index, candidate in
                (
                    candidate: candidate,
                    score: relevanceScore(
                        candidate,
                        index: index,
                        queryText: queryText,
                        queryFeatures: queryFeatures,
                        queryEmbedding: queryEmbedding,
                        applicationName: applicationName
                    )
                )
            }
            .filter { $0.score >= 1.0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.candidate.event.createdAt > rhs.candidate.event.createdAt
            }
            .prefix(relevantLimit)
            .map(\.candidate)

        // Priority order is relevant memories first, followed by guaranteed
        // recent continuity. The caller applies the prompt character budget and
        // sorts the final small set chronologically for the model.
        return (Array(ranked) + recent).map(\.event)
    }

    private static func relevanceScore(
        _ candidate: IndexedMemoryEvent,
        index: Int,
        queryText: String,
        queryFeatures: Set<String>,
        queryEmbedding: [Float]?,
        applicationName: String
    ) -> Double {
        let event = candidate.event
        let candidateText = [
            event.effectiveInput,
            event.rawTranscript,
            event.selectedContext ?? "",
            String(event.result.prefix(1_200))
        ].joined(separator: "\n")
        let candidateFeatures = lexicalFeatures(in: candidateText)
        let overlap = queryFeatures.intersection(candidateFeatures).count
        let denominator = sqrt(
            Double(max(1, queryFeatures.count * candidateFeatures.count))
        )

        var score = Double(overlap) * 1.4
            + (Double(overlap) / denominator) * 12

        if let queryEmbedding,
           let candidateEmbedding = candidate.embedding,
           let similarity = LocalMemoryEmbedding.cosineSimilarity(
               queryEmbedding,
               candidateEmbedding
           ) {
            score += max(0, similarity - 0.70) * 12
        }

        let normalizedApplication = applicationName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !normalizedApplication.isEmpty,
           normalizedApplication != "unknown app",
           event.applicationName.lowercased() == normalizedApplication {
            score += 1.6
        }
        if event.mode == .instruction {
            score += 0.45
        }

        let compactQuery = compact(queryText)
        let compactCandidate = compact(candidateText)
        if compactQuery.count >= 6,
           (compactCandidate.contains(compactQuery)
                || compactQuery.contains(compactCandidate)) {
            score += 4
        }

        // A small recency tie-breaker keeps equally relevant memories stable
        // without allowing recent but unrelated records to dominate.
        score += 0.6 / (1 + Double(index) / 40)
        return score
    }

    private static func lexicalFeatures(in text: String) -> Set<String> {
        let normalized = text.lowercased()
        var result: Set<String> = []
        var latinRun = ""
        var hanRun: [Character] = []

        func flushLatin() {
            if latinRun.count >= 2 {
                result.insert("w:\(latinRun)")
            }
            latinRun = ""
        }

        func flushHan() {
            guard hanRun.count >= 2 else {
                hanRun.removeAll(keepingCapacity: true)
                return
            }
            for length in 2...min(3, hanRun.count) {
                for start in 0...(hanRun.count - length) {
                    result.insert(
                        "c:" + String(hanRun[start..<(start + length)])
                    )
                }
            }
            hanRun.removeAll(keepingCapacity: true)
        }

        for character in normalized {
            let scalars = character.unicodeScalars
            if scalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) {
                flushHan()
                latinRun.append(character)
            } else if scalars.allSatisfy({ (0x4E00...0x9FFF).contains(Int($0.value)) }) {
                flushLatin()
                hanRun.append(character)
            } else {
                flushLatin()
                flushHan()
            }
        }
        flushLatin()
        flushHan()
        return result
    }

    private static func compact(_ text: String) -> String {
        String(
            text.lowercased().unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
                    || (0x4E00...0x9FFF).contains(Int($0.value))
            }
        )
    }
}
