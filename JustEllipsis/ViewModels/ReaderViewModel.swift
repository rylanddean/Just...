import Foundation
import SwiftData
import Observation
import os

@Observable
@MainActor
final class ReaderViewModel {

    var content: StrippedContent?
    var isLoading: Bool = true
    var isJSRendering: Bool = false
    var error: Error?
    var readProgress: Double = 0.0   // 0.0–1.0, driven by WKWebView scroll position
    var generatedPrompt: String? = nil
    var generatedDNA: String? = nil

    func load(link: QueuedLink, context: ModelContext) async {
        error = nil
        isLoading = true
        isJSRendering = false

        // Capture primitives before any await so we don't send the model object
        // across the actor boundary.
        let urlString = link.url
        let cachedHTML = link.cachedHTML
        let themeRaw = UserDefaults.standard.string(forKey: ReaderTheme.defaultsKey) ?? "ember"
        let theme = ReaderTheme(rawValue: themeRaw) ?? .ember

        do {
            let result = try await fetchContent(urlString: urlString, cachedHTML: cachedHTML, theme: theme)
            content = result.content

            // Write back to model on @MainActor (we're already here)
            if link.title == nil || link.title!.isEmpty {
                link.title = result.content.title
            }
            if link.domain == nil || link.domain!.isEmpty {
                link.domain = result.content.domain
            }
            if link.cachedHTML != result.rawHTML {
                link.cachedHTML = result.rawHTML
                link.prefetchState = .ready
            }

            // Backfill accurate read time on any matching RSSArticle.
            let articleURL = urlString
            let readMins = result.content.estimatedReadingMinutes
            let articleDescriptor = FetchDescriptor<RSSArticle>(
                predicate: #Predicate { $0.url == articleURL }
            )
            if let article = try? context.fetch(articleDescriptor).first,
               article.estimatedReadingMinutes == nil {
                article.estimatedReadingMinutes = readMins
            }

            try? context.save()

            if #available(iOS 26, *), IntelligenceService.isAvailable {
                await generateSummary(for: result.content.body)
            }
        } catch let fetchError as ContentFetcher.FetchError {
            if case .emptyContent = fetchError {
                // Cached HTML was too sparse — clear it so "Try again" fetches fresh.
                link.cachedHTML = nil
                link.prefetchState = .pending
                try? context.save()
            }
            self.error = fetchError
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadURL(_ urlString: String) async {
        error = nil
        isLoading = true
        isJSRendering = false
        let themeRaw = UserDefaults.standard.string(forKey: ReaderTheme.defaultsKey) ?? "ember"
        let theme = ReaderTheme(rawValue: themeRaw) ?? .ember
        do {
            let result = try await fetchContent(urlString: urlString, cachedHTML: nil, theme: theme)
            content = result.content
        } catch {
            self.error = error
        }
        isLoading = false
    }

    // MARK: - Private

    private static let log = Logger(subsystem: "com.rylandean.justellipsis", category: "ReaderViewModel")

    private func fetchContent(
        urlString: String,
        cachedHTML: String?,
        theme: ReaderTheme
    ) async throws -> FetchResult {
        do {
            return try await ContentFetcher.fetch(urlString: urlString, cachedHTML: cachedHTML, theme: theme)
        } catch ContentFetcher.FetchError.emptyContent {
            guard let url = URL(string: urlString) else { throw ContentFetcher.FetchError.invalidURL }
            Self.log.debug("fetchContent: URLSession returned emptyContent — trying JSRenderer for \(urlString)")
            isJSRendering = true
            do {
                let renderedHTML = try await JSRenderer.shared.render(url: url)
                let stripped = try ContentFetcher.strip(html: renderedHTML, sourceURL: url, theme: theme)
                Self.log.debug("fetchContent: JSRenderer words=\(stripped.estimatedWordCount)")
                guard stripped.estimatedWordCount >= 50 else {
                    Self.log.error("fetchContent: JSRenderer also returned sparse content — emptyContent")
                    throw ContentFetcher.FetchError.emptyContent
                }
                return FetchResult(content: stripped, rawHTML: renderedHTML)
            } catch let jsError as JSRenderer.JSRenderError {
                Self.log.error("fetchContent: JSRenderer failed — \(String(describing: jsError))")
                throw jsError
            }
        }
    }

    func markAsRead(link: QueuedLink, context: ModelContext) {
        // Reset the RSS article's queued flag so it can be re-added from the feed
        // if the brain entry is later deleted.
        let url = link.url
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.url == url }
        )
        if let article = try? context.fetch(descriptor).first {
            article.isQueued = false
        }
        context.delete(link)
        try? context.save()
    }

    @available(iOS 26, *)
    private func generateSummary(for body: String) async {
        async let summaryTask = IntelligenceService.summarize(body)
        async let dnaTask = IntelligenceService.extractDNA(from: body)

        if let summary = try? await summaryTask {
            generatedPrompt = try? await IntelligenceService.reflectPrompt(for: summary)
        }
        generatedDNA = try? await dnaTask
    }
}
