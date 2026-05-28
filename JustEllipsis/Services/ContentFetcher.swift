import Foundation
import SwiftData
import SwiftSoup
import os

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

enum ReaderLineSpacing {
    static let defaultsKey = "reader.lineSpacing"
    static let defaultValue = 1.85
    static let minValue = 1.3
    static let maxValue = 2.5
}

struct ContentFetcher: Sendable {
    private static let wrapperFallbackWordThreshold = 320
    private static let log = Logger(subsystem: "com.rylandean.justellipsis", category: "ContentFetcher")

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
          --reader-line-height: \(ReaderLineSpacing.defaultValue);
          color-scheme: \(colorScheme);
        }
        /* !important wins over inline email styles (bgcolor attrs, style="color:...") */
        * { box-sizing: border-box; color: inherit !important; background-color: transparent !important; background-image: none !important; }
        html, body { background: var(--bg) !important; color: var(--text) !important; }
        body {
          font-family: 'Georgia', serif;
          font-size: var(--reader-font-size);
          line-height: var(--reader-line-height);
          max-width: 680px;
          margin: 0 auto;
          padding: 32px 24px 80px;
        }
        h1, h2, h3, h4 { color: \(theme.headingHex) !important; font-weight: 600; }
        a { color: var(--accent) !important; text-decoration: var(--link-decoration, none); }
        blockquote {
          border-left: 2px solid var(--accent);
          padding-left: 20px;
          margin-left: 0;
          opacity: 0.8;
        }
        pre, code { background: \(codeBg) !important; border-radius: 4px; padding: 2px 6px; }
        img, video, figure, picture { display: none; }
        table { max-width: 100%; border-collapse: collapse; }
        p, li { line-height: var(--reader-line-height) !important; margin-bottom: 1em !important; }
        """
    }

    // MARK: - Fetch

    // Match the WKWebView UA so bot-detection treats URLSession requests the same as browser renders.
    static let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Fetch and strip a URL. Pass `cachedHTML` if the raw HTML is already stored on disk.
    /// Returns the stripped content AND the raw HTML to cache (the caller writes it back to the model).
    static func fetch(urlString: String, cachedHTML: String? = nil, theme: ReaderTheme = .ember) async throws -> FetchResult {
        guard let url = URL(string: urlString) else { throw FetchError.invalidURL }
        let domain = extractDomain(from: url)

        if let cached = cachedHTML, !cached.isEmpty {
            log.debug("fetch: cache hit for \(domain) (\(cached.count) bytes)")
            var content = try strip(html: cached, sourceURL: url, knownDomain: domain, theme: theme)
            var rawHTML = cached

            if let upgraded = try await attemptWrapperUpgrade(
                from: cached,
                sourceURL: url,
                current: content,
                theme: theme
            ) {
                log.debug("fetch: wrapper upgrade accepted from cache")
                content = upgraded.content
                rawHTML = upgraded.rawHTML
            }

            log.debug("fetch: cache path words=\(content.estimatedWordCount) — \(content.estimatedWordCount < 50 ? "FAIL (emptyContent)" : "OK")")
            if content.estimatedWordCount < 50 {
                throw FetchError.emptyContent
            }
            return FetchResult(content: content, rawHTML: rawHTML)
        }

        log.debug("fetch: fresh URLSession for \(urlString)")
        var request = URLRequest(url: url)
        request.setValue(ContentFetcher.safariUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        log.debug("fetch: HTTP \(statusCode) — \(data.count) bytes from \(domain)")
        if statusCode >= 400 {
            log.error("fetch: HTTP error \(statusCode) for \(urlString)")
            throw FetchError.httpError(statusCode)
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
            log.debug("fetch: wrapper upgrade accepted from fresh HTML")
            content = upgraded.content
            rawHTML = upgraded.rawHTML
        }

        log.debug("fetch: fresh path words=\(content.estimatedWordCount) — \(content.estimatedWordCount < 50 ? "FAIL (emptyContent)" : "OK")")
        if content.estimatedWordCount < 50 {
            throw FetchError.emptyContent
        }
        return FetchResult(content: content, rawHTML: rawHTML)
    }

    // MARK: - Strip

    static func strip(html: String, sourceURL: URL, knownDomain: String? = nil, theme: ReaderTheme = .ember) throws -> StrippedContent {
        // Pre-strip <script>, <style>, and <svg> blocks at the text level before
        // SwiftSoup parses the document. SwiftSoup's HTML5 tokenizer can misplace
        // elements that follow large JS or SVG blocks — removing them first prevents
        // content paragraphs from being absorbed into noise nodes.
        let cleanedHTML = Self.preStripScriptsAndStyles(from: html)
        log.debug("strip: pre-stripped \(html.count)→\(cleanedHTML.count) bytes (scripts+styles+svgs removed)")
        let doc = try SwiftSoup.parse(cleanedHTML, sourceURL.absoluteString)

        let pageTitle = (try? doc.title()) ?? sourceURL.host ?? "Untitled"
        let domain = knownDomain ?? extractDomain(from: sourceURL)

        // Remove noise elements.
        // Prefer [class*=specificword] (substring) for ad/tracker selectors rather than
        // [class~=ad] (word-boundary) — SwiftSoup's ~= selector appears to behave as
        // substring matching in some parse contexts, which caused it to kill article
        // paragraphs on sites like LeadDev. Ad containers are covered by [class*=advert],
        // [class*=adsense], and [class*=adsbygoogle] which are specific enough to be safe.
        // [class*=icon] is intentionally omitted: it's too broad (matches "blaize-icon",
        // "favicon", any wrapper with "icon" in its name) and SVG icons are already
        // pre-stripped before SwiftSoup sees the document.
        let noiseSelectors = [
            "img", "video", "figure", "picture", "iframe",
            "svg", "canvas", "form", "input", "button", "select", "textarea",
            "nav", "header", "footer", "aside",
            "noscript",
            "[class*=advert]", "[class*=adsense]", "[class*=adsbygoogle]",
            "[class*=social]",
            "[class*=comment]", "[class*=related]",
            "[class*=subscribe]",
            "[id*=advertisement]", "[id*=adsense]", "[id*=sidebar]", "[id*=comments]"
        ]
        var pCountBefore = (try? doc.select("p").array().count) ?? 0
        for sel in noiseSelectors {
            if let elements = try? doc.select(sel) {
                try? elements.remove()
            }
            let pCountAfter = (try? doc.select("p").array().count) ?? 0
            if pCountAfter < pCountBefore {
                log.debug("strip: noise '\(sel)' removed \(pCountBefore - pCountAfter) <p> (was \(pCountBefore), now \(pCountAfter))")
                pCountBefore = pCountAfter
            }
        }

        // Find the content subtree with highest paragraph density
        let body = try doc.body() ?? doc
        let candidate = findContentElement(in: body)
        let candidateTag = (try? candidate.tagName()) ?? "?"
        let candidateClass = (try? candidate.className()) ?? ""
        log.debug("strip: selected element <\(candidateTag)> class=\"\(candidateClass.prefix(80))\"")
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

        log.debug("strip: words=\(words) title=\"\(pageTitle.prefix(60))\"")
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

    // Strips <script>, <style>, and <svg> blocks from raw HTML before SwiftSoup parses it.
    // SwiftSoup's HTML5 tokenizer can misplace elements that follow large JS blocks
    // when the JavaScript contains HTML-like strings — removing them first ensures
    // the article paragraphs land in the correct position in the parsed DOM.
    // SVGs are also pre-stripped because large inline SVGs (e.g. social-share icons
    // with many <path> elements) can cause SwiftSoup to silently misparse surrounding
    // DOM structure, swallowing article paragraphs into noise elements.
    // Uses a simple string scan rather than NSRegularExpression to avoid regex
    // backreference quirks with very large script blocks.
    private static func preStripScriptsAndStyles(from html: String) -> String {
        var result = html
        for tag in ["script", "style", "svg"] {
            let open = "<\(tag)"
            let close = "</\(tag)>"
            var pieces: [String] = []
            var cursor = result.startIndex

            while cursor < result.endIndex {
                if let openRange = result.range(of: open, options: .caseInsensitive, range: cursor..<result.endIndex) {
                    pieces.append(String(result[cursor..<openRange.lowerBound]))
                    if let closeRange = result.range(of: close, options: .caseInsensitive, range: openRange.lowerBound..<result.endIndex) {
                        cursor = closeRange.upperBound
                    } else {
                        cursor = result.endIndex
                    }
                } else {
                    pieces.append(String(result[cursor...]))
                    cursor = result.endIndex
                }
            }

            result = pieces.joined()
        }
        return result
    }

    private static func findContentElement(in root: Element) -> Element {
        let totalParas = (try? root.select("p").array().count) ?? 0
        let substantialParas = (try? root.select("p").array().filter {
            ((try? $0.text().count) ?? 0) > 35
        }.count) ?? 0
        log.debug("strip: root has \(totalParas) <p> total, \(substantialParas) with >35 chars after noise removal")

        if let preferred = findPreferredContentElement(in: root) {
            return preferred
        }

        guard let paragraphs = try? root.select("p"), !paragraphs.isEmpty() else {
            log.debug("strip: no <p> elements found in body — returning body as-is")
            return root
        }

        var scoredElements: [(element: Element, score: Int)] = []

        for para in paragraphs.array() {
            guard let text = try? para.text(), text.count > 40 else { continue }
            var parent = para.parent()
            var depth = 0
            while let p = parent, depth < 12 {
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

        // Exclude table-structural tags — they tie with their content children on score
        // but make poor content containers. Prefer div/td/article/section/main.
        let structuralTags: Set<String> = ["tr", "tbody", "thead", "tfoot", "html"]
        let candidates = scoredElements.filter {
            let tag = (try? $0.element.tagName()) ?? ""
            return !structuralTags.contains(tag)
        }
        return candidates.max(by: { $0.score < $1.score })?.element ?? root
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
                let tag = (try? element.tagName()) ?? "?"
                let cls = (try? element.className()) ?? ""
                log.debug("strip: selector '\(selector)' → <\(tag)> class='\(cls.prefix(60))' score=\(score)")
                guard score >= 120 else { continue }
                if best == nil || score > best!.score {
                    best = (element, score)
                }
            }
            if best != nil {
                log.debug("strip: preferred selector matched \"\(selector)\" score=\(best!.score)")
                break
            }
        }

        if best == nil {
            log.debug("strip: no preferred selector matched — falling back to paragraph scoring")
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
            log.debug("wrapperUpgrade: skipped (words=\(current.estimatedWordCount) > threshold=\(wrapperFallbackWordThreshold))")
            return nil
        }
        guard let targetURL = extractPrimaryOutboundURL(from: html, sourceURL: sourceURL) else {
            log.debug("wrapperUpgrade: no outbound URL found in \(sourceURL.host ?? "?")")
            return nil
        }
        log.debug("wrapperUpgrade: trying \(targetURL.absoluteString.prefix(120))")

        // Treat any outbound-fetch failure as a non-fatal miss — return nil so the
        // caller falls back to the original content rather than surfacing a misleading error.
        var outboundRequest = URLRequest(url: targetURL)
        outboundRequest.setValue(ContentFetcher.safariUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: outboundRequest),
              (response as? HTTPURLResponse).map({ $0.statusCode < 400 }) ?? true else {
            log.debug("wrapperUpgrade: outbound fetch failed or returned HTTP error — skipping")
            return nil
        }
        let targetHTML = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard let stripped = try? strip(html: targetHTML, sourceURL: targetURL, theme: theme) else {
            log.debug("wrapperUpgrade: strip failed on outbound page")
            return nil
        }

        let threshold = max(150, current.estimatedWordCount * 2)
        let hasMeaningfulGain = stripped.estimatedWordCount >= threshold
        log.debug("wrapperUpgrade: outbound words=\(stripped.estimatedWordCount) need=\(threshold) gain=\(hasMeaningfulGain)")
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
