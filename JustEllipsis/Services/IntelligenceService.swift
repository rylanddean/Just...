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
struct ArticleTopics {
    @Guide(description: """
        2–4 specific, recognizable topic labels for the article.
        Title-cased nouns or noun phrases only. No verbs, no sentences.
        Aim for the level of a Wikipedia article title: specific enough to be meaningful,
        not so specific it names a single piece of news, not so broad it means nothing.
        Good: "iOS", "Nintendo", "OpenAI", "Climate Policy", "Rust", "Machine Learning",
              "Housing", "SpaceX", "React", "NBA", "Nutrition", "Kubernetes"
        Bad: "Technology" (too broad), "iPhone 16 battery fix" (too narrow), "interesting" (not a topic)
        Return as a comma-separated list with no extra punctuation.
        """)
    var labels: String
}

@available(iOS 26, *)
@Generable
struct ArticleQualityAssessment {
    @Guide(description: """
        Grade this article for a reader who values original thinking and focused attention.

        strong — makes an original argument, challenges assumptions, or reveals something
        the reader couldn't have found by reasoning from common knowledge alone.
        Reserved for genuinely distinctive work. Most articles are NOT strong.

        worthIt — informative and competently written, but not essential reading.
        Covers ground that exists elsewhere or adds incremental value.

        noise — aggregated takes, listicles, press releases, event recaps, promotional
        content, opinion without supporting argument, or too brief to be substantive.
        If the content could have been auto-generated or is obviously SEO-driven, it is noise.
        When uncertain between worthIt and noise, prefer noise.

        Return exactly one of: strong, worthIt, noise.
        """)
    var grade: String
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
struct TitleAssessment {
    @Guide(description: """
        Assess this article headline for sensationalism, emotional manipulation,
        or information withholding designed to drive clicks.
        If it is clickbait: rewrite as a neutral, factual headline under 15 words.
        If it is not clickbait: return exactly the string "CLEAN".
        No quotation marks. No punctuation beyond what the headline requires.
        """)
    var result: String
}

@available(iOS 26, *)
@Generable
struct FeedCategoryAssessment {
    @Guide(description: """
        Return exactly one category label from the allowed categories list.
        Do not invent new categories.
        """)
    var category: String
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

    // MARK: Article Topics

    static func extractTopics(title: String) async throws -> [String] {
        let session = LanguageModelSession()
        let response = try await session.respond(
            to: "Categorise this article title into topic labels:\n\n\(title)",
            generating: ArticleTopics.self
        )
        return response.content.labels
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: Article Quality Grading

    static func gradeQuality(title: String, description: String, source: String? = nil) async -> ArticleQualityGrade? {
        var parts: [String] = []
        parts.append("Title: \(title)")
        if let source { parts.append("Source: \(source)") }
        if !description.isEmpty { parts.append("Content:\n\(String(description.prefix(2000)))") }
        let input = parts.joined(separator: "\n")
        let session = LanguageModelSession()

        // Wrap in a 20 s timeout: safety-guardrail hangs never stall the grading pipeline.
        let rawGrade = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let r = try? await session.respond(
                    to: "Grade this article:\n\n\(input)",
                    generating: ArticleQualityAssessment.self
                )
                return r?.content.grade
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }

        let raw = rawGrade?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        switch raw {
        case "strong":  return .strong
        case "worthit": return .worthIt
        case "noise":   return .noise
        default:        return nil
        }
    }

    // MARK: Article Relevance Scoring

    // Returns a 0.0–1.0 relevance score for a title against a set of Brain DNA concepts.
    // Uses keyword overlap — no AI required, fast enough to score all Digest articles on appear.
    static func scoreRelevance(title: String, concepts: [String]) -> Double {
        guard !concepts.isEmpty else { return 0 }
        let titleWords = Set(title.lowercased().split(separator: " ").map(String.init))
        let matched = concepts.filter { concept in
            let c = concept.lowercased()
            return titleWords.contains(c) || titleWords.contains(where: { $0.contains(c) || c.contains($0) })
        }
        return Double(matched.count) / Double(concepts.count)
    }

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

    // MARK: Feed Category Classification

    static func classifyFeedCategory(
        feedURL: String,
        feedTitle: String,
        feedPreview: String,
        allowedCategories: [String]
    ) async -> String? {
        let normalized = allowedCategories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return nil }

        let categoryList = normalized.joined(separator: ", ")
        let prompt = """
        Pick the best category for this RSS feed.

        Allowed categories:
        \(categoryList)

        Feed URL: \(feedURL)
        Feed title: \(feedTitle)
        Feed preview:
        \(feedPreview.prefix(1800))
        """

        let session = LanguageModelSession()
        let response = try? await session.respond(
            to: prompt,
            generating: FeedCategoryAssessment.self
        )

        let raw = response?.content.category.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.first { $0.caseInsensitiveCompare(raw) == .orderedSame }
    }

    // MARK: Title Rewriting

    // Returns a rewritten title if the original is clickbait, nil if it's clean.
    static func rewriteTitle(_ title: String) async -> String? {
        let session = LanguageModelSession()
        let response = try? await session.respond(
            to: "Assess this headline: \(title)",
            generating: TitleAssessment.self
        )
        let result = response?.content.result ?? "CLEAN"
        return result == "CLEAN" ? nil : result
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
