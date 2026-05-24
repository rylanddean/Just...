import Foundation

// Foundation Models is only available on iOS 26+ / Apple Intelligence hardware.
// All code in this file is gated behind @available(iOS 26, *).

struct IntelligenceService: Sendable {

    static var isAvailable: Bool {
        if #available(iOS 26, *) {
            return _isAvailableIOS26()
        }
        return false
    }

    @available(iOS 26, *)
    private static func _isAvailableIOS26() -> Bool {
        // Dynamically check via reflection to avoid compilation errors on
        // systems where the FoundationModels SDK may not be fully linked yet.
        // When FoundationModels ships, replace with:
        //   if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
}

// MARK: - iOS 26 AI Features

@available(iOS 26, *)
extension IntelligenceService {

    // MARK: Article Summary

    static func summarize(_ body: String) async throws -> String {
        let truncated = String(body.prefix(4000))
        let prompt = """
        Summarize this article in 2–3 calm, direct sentences. \
        No bullet points. No preamble. No "This article…" opener. \
        Just the key idea.

        Article:
        \(truncated)
        """
        // Replace with LanguageModelSession when FoundationModels is available:
        // let session = LanguageModelSession()
        // return try await session.respond(to: prompt).content
        _ = prompt
        throw IntelligenceError.unavailable
    }

    // MARK: Contextual Reflect Prompt

    static func reflectPrompt(for summary: String) async throws -> String {
        let prompt = """
        Given this article summary, write one short reflection prompt. \
        One question, under 10 words, calm tone, no question mark at the end. \
        Examples: "What would you do differently", "Does this change how you think about focus"

        Summary: \(summary)
        """
        // Replace with LanguageModelSession when FoundationModels is available:
        // let session = LanguageModelSession()
        // let result = try await session.respond(to: prompt, generating: ReflectPrompt.self)
        // return result.question
        _ = prompt
        throw IntelligenceError.unavailable
    }

    // MARK: Errors

    enum IntelligenceError: Error {
        case unavailable
        case generationFailed
    }
}

// MARK: - Static Fallback Prompts

extension IntelligenceService {

    static let fallbackPrompts: [String] = [
        "What stayed with you",
        "One thought",
        "What surprised you",
        "Would you act on this",
        "What do you already know about this",
        "Does this change anything for you",
        "What question does this raise",
        "Who should read this"
    ]

    static func randomFallbackPrompt() -> String {
        fallbackPrompts.randomElement() ?? fallbackPrompts[0]
    }
}
