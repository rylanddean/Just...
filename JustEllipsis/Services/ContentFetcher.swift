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

enum ReaderTextSize {
    static let defaultsKey = "reader.textSize"
    static let defaultValue = 20.0
    static let minValue = 16.0
    static let maxValue = 28.0
}

struct ContentFetcher: Sendable {
    private static let wrapperFallbackWordThreshold = 320

    // MARK: - Reader CSS (injected into WKWebView)

    static func readerCSS(for theme: ReaderTheme) -> String {
        let codeBg = theme.isLight ? "rgba(0,0,0,0.06)" : "rgba(255,255,255,0.05)"
        let colorScheme = theme.isLight ? "light" : "dark"
        return """
        :root {
          --bg: \(theme.bgHex);
          --text: \(theme.textHex);
          --accent: \(theme.accentHex);
          --reader-font-size: \(ReaderTextSize.defaultValue)px;
          color-scheme: \(colorScheme);
        }
        * { box-sizing: border-box; }
        html { background: var(--bg); }
        body {
          background: var(--bg);
          color: var(--text);
          font-family: 'Georgia', serif;
          font-size: var(--reader-font-size);
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
            var content = try strip(html: cached, sourceURL: url, knownDomain: domain, theme: theme)
            var rawHTML = cached

            if let upgraded = try await attemptWrapperUpgrade(
                from: cached,
                sourceURL: url,
                current: content,
                theme: theme
            ) {
                content = upgraded.content
                rawHTML = upgraded.rawHTML
            }

            if content.estimatedWordCount < 50 {
                throw FetchError.emptyContent
            }
            return FetchResult(content: content, rawHTML: rawHTML)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw FetchError.httpError(http.statusCode)
        }
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        var content = try strip(html: html, sourceURL: url, knownDomain: domain, theme: theme)
        var rawHTML = html

        if let upgraded = try await attemptWrapperUpgrade(
            from: html,
            sourceURL: url,
            current: content,
            theme: theme
        ) {
            content = upgraded.content
            rawHTML = upgraded.rawHTML
        }

        if content.estimatedWordCount < 50 {
            throw FetchError.emptyContent
        }
        return FetchResult(content: content, rawHTML: rawHTML)
    }

    // MARK: - Strip

    static func strip(html: String, sourceURL: URL, knownDomain: String? = nil, theme: ReaderTheme = .ember) throws -> StrippedContent {
        let doc = try SwiftSoup.parse(html, sourceURL.absoluteString)

        let pageTitle = (try? doc.title()) ?? sourceURL.host ?? "Untitled"
        let domain = knownDomain ?? extractDomain(from: sourceURL)

        // Remove noise elements.
        // Use [class~=word] (whitespace-delimited word match) not [class*=word]
        // (substring match) to avoid false positives — e.g. [class*=ad] would
        // strip "leading-relaxed", "shadow-md", "gradient-*", "headline", etc.
        let noiseSelectors = [
            "img", "video", "figure", "picture", "iframe",
            "svg", "canvas", "form", "input", "button", "select", "textarea",
            "nav", "header", "footer", "aside",
            "script", "style", "noscript",
            "[class~=ad]", "[class*=advert]", "[class*=adsense]", "[class*=adsbygoogle]",
            "[class*=banner]", "[class*=social]",
            "[class*=icon]",
            "[class*=comment]", "[class*=related]", "[class*=share]",
            "[class*=subscribe]", "[class*=newsletter]",
            "[id*=advertisement]", "[id*=adsense]", "[id*=sidebar]", "[id*=comments]"
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
        if let preferred = findPreferredContentElement(in: root) {
            return preferred
        }

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

    private static func findPreferredContentElement(in root: Element) -> Element? {
        let selectors = [
            "article [itemprop=articleBody]",
            "[itemprop=articleBody]",
            "article .post-content",
            "article .entry-content",
            "main article",
            "article",
            "main"
        ]

        var best: (element: Element, score: Int)?
        for selector in selectors {
            guard let elements = try? root.select(selector), !elements.isEmpty() else { continue }
            for element in elements.array() {
                let score = contentScore(for: element)
                guard score >= 120 else { continue }
                if best == nil || score > best!.score {
                    best = (element, score)
                }
            }
            if best != nil { break }
        }

        return best?.element
    }

    private static func contentScore(for element: Element) -> Int {
        guard let paragraphs = try? element.select("p"), !paragraphs.isEmpty() else {
            return 0
        }

        var score = 0
        for para in paragraphs.array() {
            guard let text = try? para.text() else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 35 else { continue }
            score += min(trimmed.count, 300)
        }
        return score
    }

    private static func attemptWrapperUpgrade(
        from html: String,
        sourceURL: URL,
        current: StrippedContent,
        theme: ReaderTheme
    ) async throws -> FetchResult? {
        guard current.estimatedWordCount <= wrapperFallbackWordThreshold else {
            return nil
        }
        guard let targetURL = extractPrimaryOutboundURL(from: html, sourceURL: sourceURL) else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: targetURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw FetchError.httpError(http.statusCode)
        }
        let targetHTML = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let stripped = try strip(html: targetHTML, sourceURL: targetURL, theme: theme)

        let hasMeaningfulGain = stripped.estimatedWordCount >= max(150, current.estimatedWordCount * 2)
        guard hasMeaningfulGain else { return nil }
        return FetchResult(content: stripped, rawHTML: targetHTML)
    }

    static func extractPrimaryOutboundURL(from html: String, sourceURL: URL) -> URL? {
        guard let doc = try? SwiftSoup.parse(html, sourceURL.absoluteString) else {
            return nil
        }

        // Prefer known "link-post title" anchors first, then broader content anchors.
        let selectors = [
            "dl.linkedlist dt > a[href]",
            "article h1 a[href]",
            "article h2 a[href]",
            "main h1 a[href]",
            "main h2 a[href]",
            "main p a[href]",
            "article p a[href]"
        ]

        for selector in selectors {
            guard let links = try? doc.select(selector) else { continue }
            for link in links.array() {
                guard let href = try? link.attr("href"),
                      let candidate = URL(string: href, relativeTo: sourceURL)?.absoluteURL,
                      isValidOutboundTarget(candidate, sourceURL: sourceURL) else { continue }
                return candidate
            }
        }
        return nil
    }

    static func isValidOutboundTarget(_ target: URL, sourceURL: URL) -> Bool {
        guard let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let normalizedSource = normalizeHost(sourceURL.host)
        let normalizedTarget = normalizeHost(target.host)
        if normalizedSource == nil || normalizedTarget == nil { return false }
        if normalizedSource == normalizedTarget { return false }

        // Avoid obvious non-article utility endpoints.
        let lowerPath = target.path.lowercased()
        if lowerPath.hasSuffix(".jpg")
            || lowerPath.hasSuffix(".jpeg")
            || lowerPath.hasSuffix(".png")
            || lowerPath.hasSuffix(".gif")
            || lowerPath.hasSuffix(".svg")
            || lowerPath.hasSuffix(".pdf")
            || lowerPath.hasSuffix(".xml")
            || lowerPath.hasSuffix(".rss") {
            return false
        }

        return true
    }

    private static func normalizeHost(_ host: String?) -> String? {
        guard var value = host?.lowercased(), !value.isEmpty else { return nil }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }
        return value
    }

    // MARK: - Errors

    enum FetchError: Error {
        case invalidURL
        case emptyContent
        case httpError(Int)
    }
}
