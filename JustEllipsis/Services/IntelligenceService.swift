import Foundation
import FoundationModels

// Foundation Models is only available on iOS 26+ / Apple Intelligence hardware.
// All public entry points check isAvailable before calling into this service.

struct IntelligenceService: Sendable {

    static var isAvailable: Bool {
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }
}

// MARK: - Generable output types

@available(iOS 26, *)
@Generable
struct ArticleSummary {
    @Guide(description: """
        2–3 calm, direct sentences summarising the article's key idea.
        No bullet points. No preamble. No "This article…" opener.
        """)
    var text: String
}

@available(iOS 26, *)
@Generable
struct FeedItemSummary {
    @Guide(description: """
        Exactly two calm, direct sentences summarising the article snippet.
        No bullet points. No preamble. No "This article…" opener.
        Plain prose only.
        """)
    var text: String
}

@available(iOS 26, *)
@Generable
struct ReflectPrompt {
    @Guide(description: """
        One short reflection prompt, under 10 words, calm tone.
        No question mark at the end.
        Examples: "What would you do differently", "Does this change how you think about focus"
        """)
    var question: String
}

@available(iOS 26, *)
@Generable
struct ArticleDNA {
    @Guide(description: """
        Exactly 3 lowercase concept words that capture the core ideas of the article.
        Abstract nouns only — no verbs, no adjectives, no proper nouns.
        Separate with " · " (space · space).
        Examples: "attention · solitude · cost", "language · power · silence"
        """)
    var concepts: String
}

@available(iOS 26, *)
@Generable
struct RelevanceScore {
    @Guide(description: """
        A single integer from 0 to 10 representing how relevant the article is to the reader.
        0 = completely irrelevant. 10 = perfectly matched. Nothing else.
        """)
    var score: Int
}

@available(iOS 26, *)
@Generable
struct PodcastArticle {
    @Guide(description: """
        A readable prose article rewritten from a podcast transcript.
        800–1200 words. Third person. No filler words. No preamble like "In this episode…".
        Plain paragraphs only — no headers, no bullet points.
        """)
    var body: String
}

@available(iOS 26, *)
@Generable
struct ChunkSummary {
    @Guide(description: """
        3–5 sentences capturing the main ideas from this transcript chunk.
        No preamble. No "In this section…" opener. Plain prose.
        """)
    var text: String
}

// MARK: - iOS 26 AI Features

@available(iOS 26, *)
extension IntelligenceService {

    // MARK: Article Summary

    static func summarize(_ body: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(
            to: "Summarize this article:\n\n\(String(body.prefix(4000)))",
            generating: ArticleSummary.self
        )
        return response.content.text
    }

    // MARK: Feed Item Summary (two sentences, shown in FeedDetailView)

    static func summarizeFeedItem(title: String, description: String) async throws -> String {
        let input = description.isEmpty ? title : "\(title)\n\n\(description)"
        let session = LanguageModelSession()
        let response = try await session.respond(
            to: "Summarize this article snippet:\n\n\(String(input.prefix(2000)))",
            generating: FeedItemSummary.self
        )
        return response.content.text
    }

    // MARK: Contextual Reflect Prompt

    static func reflectPrompt(for summary: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(
            to: "Write one short reflection prompt for this article summary:\n\n\(summary)",
            generating: ReflectPrompt.self
        )
        return response.content.question
    }

    // MARK: Article DNA

    static func extractDNA(from body: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(
            to: "Extract the Article DNA from this text:\n\n\(String(body.prefix(3000)))",
            generating: ArticleDNA.self
        )
        return response.content.concepts
    }

    // MARK: Article Relevance Scoring (used by RSSRecommendationEngine)

    // Returns a relevance score from 0–10 for an article title against a reader profile.
    // Profile is the newline-joined string of "title: reflection" pairs from last 30 Brain entries.
    static func scoreRelevance(articleTitle: String, readerProfile: String) async -> Int {
        let session = LanguageModelSession()
        let response = try? await session.respond(
            to: """
            Score how relevant this article is to the reader's interests (0–10):

            Reader's interests:
            \(readerProfile.prefix(3000))

            Article title: "\(articleTitle)"
            """,
            generating: RelevanceScore.self
        )
        return response?.content.score ?? 5
    }

    // MARK: Podcast Article Generation

    // Rewrites a stripped transcript as a readable prose article.
    // Uses a two-pass approach for transcripts over 12,000 words:
    //   Pass 1 — summarise each ~3,000-word chunk independently.
    //   Pass 2 — synthesise chunk summaries into a final article.
    @available(iOS 26, *)
    static func generateArticle(
        from transcript: String,
        episodeTitle: String,
        showName: String
    ) async throws -> String {
        let words = transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.count > 12_000 {
            return try await generateArticleTwoPass(
                transcript: transcript,
                words: words,
                episodeTitle: episodeTitle,
                showName: showName
            )
        }
        return try await generateArticleSinglePass(
            transcript: transcript,
            episodeTitle: episodeTitle,
            showName: showName
        )
    }

    @available(iOS 26, *)
    private static func generateArticleSinglePass(
        transcript: String,
        episodeTitle: String,
        showName: String
    ) async throws -> String {
        let session = LanguageModelSession()
        let prompt = """
        Rewrite this podcast transcript as a concise, readable article in the third person. \
        Preserve the key ideas, examples, and arguments. Remove filler words, redundant exchanges, \
        and tangents. Target 800–1200 words. Do not invent claims not present in the transcript.

        Show: \(showName)
        Episode: \(episodeTitle)

        Transcript:
        \(transcript.prefix(16_000))
        """
        let response = try await session.respond(to: prompt, generating: PodcastArticle.self)
        return response.content.body
    }

    @available(iOS 26, *)
    private static func generateArticleTwoPass(
        transcript: String,
        words: [String],
        episodeTitle: String,
        showName: String
    ) async throws -> String {
        let chunkSize = 3_000
        let chunks = stride(from: 0, to: words.count, by: chunkSize).map { start -> String in
            let end = min(start + chunkSize, words.count)
            return words[start..<end].joined(separator: " ")
        }

        var chunkSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let session = LanguageModelSession()
            let prompt = """
            Summarise this portion of a podcast transcript in 3–5 sentences. \
            Capture the main ideas and arguments. No filler, no preamble.

            Chunk \(index + 1) of \(chunks.count):
            \(chunk)
            """
            if let result = try? await session.respond(to: prompt, generating: ChunkSummary.self) {
                chunkSummaries.append(result.content.text)
            }
        }

        let combinedSummaries = chunkSummaries.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n\n")

        let synthesisSession = LanguageModelSession()
        let synthesisPrompt = """
        Using these summaries of a podcast episode, write a single coherent article in the third person. \
        Preserve the key ideas, examples, and arguments. Target 800–1200 words. \
        Do not invent claims not present in the summaries.

        Show: \(showName)
        Episode: \(episodeTitle)

        Summaries:
        \(combinedSummaries)
        """
        let response = try await synthesisSession.respond(
            to: synthesisPrompt,
            generating: PodcastArticle.self
        )
        return response.content.body
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
