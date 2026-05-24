import Foundation
import SwiftData
import SwiftSoup

struct StrippedContent: Sendable {
    let title: String
    let body: String               // cleaned HTML for WKWebView injection
    let domain: String
    let estimatedWordCount: Int
    let estimatedReadingMinutes: Int
}

struct FetchResult: Sendable {
    let content: StrippedContent
    let rawHTML: String       // the unstripped HTML, suitable for caching
}

struct ContentFetcher: Sendable {

    // MARK: - Reader CSS (injected into WKWebView)

    static func readerCSS(for theme: ReaderTheme) -> String {
        let codeBg = theme.isLight ? "rgba(0,0,0,0.06)" : "rgba(255,255,255,0.05)"
        let colorScheme = theme.isLight ? "light" : "dark"
        return """
        :root {
          --bg: \(theme.bgHex);
          --text: \(theme.textHex);
          --accent: \(theme.accentHex);
          color-scheme: \(colorScheme);
        }
        * { box-sizing: border-box; }
        body {
          background: var(--bg);
          color: var(--text);
          font-family: 'Georgia', serif;
          font-size: 20px;
          line-height: 1.85;
          max-width: 680px;
          margin: 0 auto;
          padding: 32px 24px 80px;
        }
        h1, h2, h3, h4 { color: \(theme.headingHex); font-weight: 600; }
        a { color: var(--accent); text-decoration: none; }
        blockquote {
          border-left: 2px solid var(--accent);
          padding-left: 20px;
          margin-left: 0;
          opacity: 0.8;
        }
        pre, code { background: \(codeBg); border-radius: 4px; padding: 2px 6px; }
        img, video, figure, picture { display: none; }
        """
    }

    // MARK: - Fetch

    /// Fetch and strip a URL. Pass `cachedHTML` if the raw HTML is already stored on disk.
    /// Returns the stripped content AND the raw HTML to cache (the caller writes it back to the model).
    static func fetch(urlString: String, cachedHTML: String? = nil, theme: ReaderTheme = .ember) async throws -> FetchResult {
        guard let url = URL(string: urlString) else { throw FetchError.invalidURL }
        let domain = extractDomain(from: url)

        if let cached = cachedHTML, !cached.isEmpty {
            let content = try strip(html: cached, sourceURL: url, knownDomain: domain, theme: theme)
            return FetchResult(content: content, rawHTML: cached)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let content = try strip(html: html, sourceURL: url, knownDomain: domain, theme: theme)
        return FetchResult(content: content, rawHTML: html)
    }

    // MARK: - Strip

    static func strip(html: String, sourceURL: URL, knownDomain: String? = nil, theme: ReaderTheme = .ember) throws -> StrippedContent {
        let doc = try SwiftSoup.parse(html, sourceURL.absoluteString)

        let pageTitle = (try? doc.title()) ?? sourceURL.host ?? "Untitled"
        let domain = knownDomain ?? extractDomain(from: sourceURL)

        // Remove noise elements
        let noiseSelectors = [
            "img", "video", "figure", "picture", "iframe",
            "nav", "header", "footer", "aside",
            "script", "style", "noscript",
            "[class*=ad]", "[class*=banner]", "[class*=social]",
            "[class*=comment]", "[class*=related]", "[class*=share]",
            "[class*=subscribe]", "[class*=newsletter]",
            "[id*=ad]", "[id*=sidebar]", "[id*=comments]"
        ]
        for sel in noiseSelectors {
            if let elements = try? doc.select(sel) {
                try? elements.remove()
            }
        }

        // Find the content subtree with highest paragraph density
        let body = try doc.body() ?? doc
        let candidate = findContentElement(in: body)
        let articleHTML = (try? candidate.html()) ?? (try? body.html()) ?? ""

        // Wrap in full HTML document with injected CSS
        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>\(readerCSS(for: theme))</style>
        </head>
        <body>\(articleHTML)</body>
        </html>
        """

        let plainText = (try? SwiftSoup.parse(articleHTML).text()) ?? ""
        let words = plainText.split(separator: " ").count
        let readingMinutes = max(1, words / 238)

        return StrippedContent(
            title: pageTitle,
            body: fullHTML,
            domain: domain,
            estimatedWordCount: words,
            estimatedReadingMinutes: readingMinutes
        )
    }

    static func extractDomain(from url: URL) -> String {
        guard var host = url.host else { return url.absoluteString }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    // MARK: - Private Helpers

    private static func findContentElement(in root: Element) -> Element {
        guard let paragraphs = try? root.select("p"), !paragraphs.isEmpty() else {
            return root
        }

        var scoredElements: [(element: Element, score: Int)] = []

        for para in paragraphs.array() {
            guard let text = try? para.text(), text.count > 40 else { continue }
            var parent = para.parent()
            var depth = 0
            while let p = parent, depth < 4 {
                let existing = scoredElements.first(where: { $0.element == p })
                let score = text.count / 10
                if existing == nil {
                    scoredElements.append((p, score))
                } else if let idx = scoredElements.firstIndex(where: { $0.element == p }) {
                    scoredElements[idx] = (p, scoredElements[idx].score + score)
                }
                parent = p.parent()
                depth += 1
            }
        }

        return scoredElements.max(by: { $0.score < $1.score })?.element ?? root
    }

    // MARK: - Errors

    enum FetchError: Error {
        case invalidURL
        case emptyContent
    }
}
