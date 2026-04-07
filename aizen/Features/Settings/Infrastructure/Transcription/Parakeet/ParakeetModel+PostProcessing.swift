import Foundation
#if arch(arm64)

// MARK: - Post Processing

nonisolated func tokensToSentences(_ tokens: [AlignedToken]) -> [AlignedSentence] {
    guard !tokens.isEmpty else { return [] }

    var sentences: [AlignedSentence] = []
    var currentTokens: [AlignedToken] = []

    for token in tokens {
        currentTokens.append(token)

        // Simple sentence boundary detection (you might want to improve this)
        if token.text.contains(".") || token.text.contains("!") || token.text.contains("?") {
            sentences.append(AlignedSentence(tokens: currentTokens))
            currentTokens = []
        }
    }

    if !currentTokens.isEmpty {
        sentences.append(AlignedSentence(tokens: currentTokens))
    }

    return sentences
}

nonisolated func sentencesToResult(_ sentences: [AlignedSentence]) -> AlignedResult {
    AlignedResult(sentences: sentences)
}

nonisolated func mergeLongestContiguous(
    _ tokens1: [AlignedToken],
    _ tokens2: [AlignedToken],
    overlapDuration: Float
) throws -> [AlignedToken] {
    let cutoffTime = tokens1.last?.end ?? 0.0 - overlapDuration
    let filteredTokens1 = tokens1.filter { $0.end <= cutoffTime }
    let filteredTokens2 = tokens2.filter { $0.start >= cutoffTime }
    return filteredTokens1 + filteredTokens2
}

#endif
