import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ReaderViewModel {

    var content: StrippedContent?
    var isLoading: Bool = true
    var error: Error?
    var readProgress: Double = 0.0   // 0.0–1.0, driven by WKWebView scroll position
    var generatedPrompt: String? = nil

    func load(link: QueuedLink, context: ModelContext) async {
        error = nil
        isLoading = true

        // Capture primitives before any await so we don't send the model object
        // across the actor boundary.
        let urlString = link.url
        let cachedHTML = link.cachedHTML
        let themeRaw = UserDefaults.standard.string(forKey: ReaderTheme.defaultsKey) ?? "ember"
        let theme = ReaderTheme(rawValue: themeRaw) ?? .ember

        do {
            let result = try await ContentFetcher.fetch(urlString: urlString, cachedHTML: cachedHTML, theme: theme)
            content = result.content

            // Write back to model on @MainActor (we're already here)
            if link.title == nil || link.title!.isEmpty {
                link.title = result.content.title
            }
            if link.domain == nil || link.domain!.isEmpty {
                link.domain = result.content.domain
            }
            if link.cachedHTML == nil {
                link.cachedHTML = result.rawHTML
                link.prefetchState = .ready
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
        let themeRaw = UserDefaults.standard.string(forKey: ReaderTheme.defaultsKey) ?? "ember"
        let theme = ReaderTheme(rawValue: themeRaw) ?? .ember
        do {
            let result = try await ContentFetcher.fetch(urlString: urlString, theme: theme)
            content = result.content
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func markAsRead(link: QueuedLink, context: ModelContext) {
        context.delete(link)
        try? context.save()
    }

    // MARK: - Private

    @available(iOS 26, *)
    private func generateSummary(for body: String) async {
        guard let summary = try? await IntelligenceService.summarize(body) else { return }
        generatedPrompt = try? await IntelligenceService.reflectPrompt(for: summary)
    }
}
