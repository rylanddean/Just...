import Foundation
import SwiftSoup

struct WebFeedScraper {

    struct ScrapedFeed: Sendable {
        let title: String
        let articles: [ParsedArticle]
        let discoveredFeedURL: String?
    }

    static func scrape(urlString: String) async -> ScrapedFeed? {
        guard let pageURL = URL(string: urlString) else { return nil }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        guard let (data, _) = try? await URLSession(configuration: config).data(from: pageURL) else { return nil }
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard !html.isEmpty else { return nil }
        return await Task.detached(priority: .background) {
            parse(html: html, pageURL: pageURL)
        }.value
    }

    // MARK: - Core parsing (off main thread, pure)

    private static func parse(html: String, pageURL: URL) -> ScrapedFeed? {
        guard let doc = try? SwiftSoup.parse(html, pageURL.absoluteString) else { return nil }
        let title = extractPageTitle(doc: doc)

        // Pass 2: alternate feed link in <head>
        if let feedURL = discoverAlternateFeed(doc: doc) {
            return ScrapedFeed(title: title, articles: [], discoveredFeedURL: feedURL)
        }

        // Pass 1: JSON-LD structured data
        var articles = extractJSONLD(doc: doc, baseURL: pageURL)

        // Pass 3: semantic HTML containers
        if articles.isEmpty { articles = extractSemantic(doc: doc, baseURL: pageURL) }

        // Pass 4: link density across the full document
        if articles.isEmpty { articles = extractByLinkDensity(doc: doc, baseURL: pageURL) }

        guard !articles.isEmpty else { return nil }
        return ScrapedFeed(title: title, articles: articles, discoveredFeedURL: nil)
    }

    // MARK: - Pass 2: Alternate feed discovery

    private static func discoverAlternateFeed(doc: Document) -> String? {
        guard let links = try? doc.select("link[rel~=alternate]") else { return nil }
        for link in links {
            let type = (try? link.attr("type")) ?? ""
            guard type.contains("rss") || type.contains("atom") || type.contains("feed") else { continue }
            let href = (try? link.attr("abs:href")) ?? ""
            guard !href.isEmpty else { continue }
            return href
        }
        return nil
    }

    // MARK: - Pass 1: JSON-LD

    private static func extractJSONLD(doc: Document, baseURL: URL) -> [ParsedArticle] {
        guard let scripts = try? doc.select("script[type=application/ld+json]") else { return [] }
        let articleTypes: Set<String> = ["Article", "NewsArticle", "BlogPosting", "TechArticle"]
        var seen = Set<String>()
        var results: [ParsedArticle] = []

        for script in scripts {
            guard let jsonText = try? script.html(),
                  let data = jsonText.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }

            let candidates: [[String: Any]] = {
                if let arr = obj as? [[String: Any]] { return arr }
                if let single = obj as? [String: Any] {
                    if let graph = single["@graph"] as? [[String: Any]] { return graph }
                    return [single]
                }
                return []
            }()

            for candidate in candidates {
                guard let typeField = candidate["@type"] as? String,
                      articleTypes.contains(typeField) else { continue }

                let rawURL: String? = candidate["url"] as? String
                    ?? candidate["mainEntityOfPage"] as? String
                    ?? (candidate["mainEntityOfPage"] as? [String: Any])?["@id"] as? String

                guard let raw = rawURL,
                      let normURL = normalise(raw, base: baseURL),
                      seen.insert(normURL).inserted else { continue }

                let ldTitle = ((candidate["headline"] as? String) ?? (candidate["name"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !ldTitle.isEmpty else { continue }

                let desc = candidate["description"] as? String
                let publishedAt: Date = {
                    if let s = candidate["datePublished"] as? String {
                        return ISO8601DateFormatter().date(from: s) ?? Date()
                    }
                    return Date()
                }()

                results.append(ParsedArticle(url: normURL, title: ldTitle,
                                             publishedAt: publishedAt, feedDescription: desc))
            }
        }
        return results
    }

    // MARK: - Pass 3: Semantic HTML

    private static func extractSemantic(doc: Document, baseURL: URL) -> [ParsedArticle] {
        let containers: Elements? = {
            if let arts = try? doc.select("article"), arts.size() > 0 { return arts }
            if let main = try? doc.select("main"), main.size() > 0 { return main }
            return try? doc.select("section")
        }()
        guard let containers else { return [] }

        var seen = Set<String>()
        var results: [ParsedArticle] = []

        for container in containers {
            guard let links = try? container.select("a[href]") else { continue }
            for link in links {
                let href = (try? link.attr("abs:href")) ?? ""
                guard let normURL = normalise(href, base: baseURL),
                      seen.insert(normURL).inserted,
                      isArticlePath(URL(string: normURL), baseURL: baseURL) else { continue }
                let title = titleFor(link: link) ?? deSlug(normURL)
                guard !title.isEmpty else { continue }
                let date = nearbyDate(for: link) ?? Date()
                results.append(ParsedArticle(url: normURL, title: title,
                                             publishedAt: date, feedDescription: nil))
            }
        }
        return results
    }

    // MARK: - Pass 4: Link density

    private static func extractByLinkDensity(doc: Document, baseURL: URL) -> [ParsedArticle] {
        guard let links = try? doc.select("a[href]") else { return [] }
        var seen = Set<String>()
        var results: [ParsedArticle] = []

        for link in links {
            let href = (try? link.attr("abs:href")) ?? ""
            guard let normURL = normalise(href, base: baseURL),
                  seen.insert(normURL).inserted,
                  isArticlePath(URL(string: normURL), baseURL: baseURL) else { continue }
            let title = titleFor(link: link) ?? deSlug(normURL)
            guard !title.isEmpty else { continue }
            results.append(ParsedArticle(url: normURL, title: title,
                                         publishedAt: Date(), feedDescription: nil))
        }
        return results
    }

    // MARK: - Helpers

    private static func extractPageTitle(doc: Document) -> String {
        if let og = try? doc.select("meta[property=og:title]").first()?.attr("content"), !og.isEmpty {
            return og
        }
        return (try? doc.title()) ?? ""
    }

    private static func titleFor(link: Element) -> String? {
        // Heading inside the link (most common pattern)
        if let h = try? link.select("h1, h2, h3, h4").first(),
           let text = try? h.text() {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > 10 { return t }
        }
        // Image alt text (used by sites like pokemon.com where the card image carries the title)
        if let img = try? link.select("img[alt]").first(),
           let alt = try? img.attr("alt") {
            let t = alt.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > 10 { return t }
        }
        // aria-label on the link itself
        if let label = try? link.attr("aria-label") {
            let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > 10 { return t }
        }
        // Plain anchor text as a last resort
        let text = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 10 ? text : nil
    }

    private static func nearbyDate(for element: Element) -> Date? {
        // Walk up two levels looking for a <time datetime="...">
        var node: Element? = element.parent()
        for _ in 0..<3 {
            guard let n = node else { break }
            if let time = try? n.select("time[datetime]").first(),
               let dateStr = try? time.attr("datetime"), !dateStr.isEmpty,
               let date = ISO8601DateFormatter().date(from: dateStr) {
                return date
            }
            node = n.parent()
        }
        return nil
    }

    // MARK: - URL helpers

    private static func isArticlePath(_ url: URL?, baseURL: URL) -> Bool {
        guard let url, let host = url.host, let baseHost = baseURL.host else { return false }
        guard rootDomain(host) == rootDomain(baseHost) else { return false }

        let path = url.path.lowercased()
        guard !path.isEmpty, path != "/", path != baseURL.path.lowercased() else { return false }

        let rejectPatterns = ["/tag/", "/tags/", "/author/", "/authors/", "/category/",
                              "/categories/", "/search", "/login", "/subscribe", "/signup",
                              "/rss", "/feed", "/sitemap", "/about", "/contact", "/privacy",
                              "/terms", "/page/", "/cdn-cgi/", "/comment"]
        if rejectPatterns.contains(where: { path.contains($0) }) { return false }

        let articlePatterns = ["/news/", "/article/", "/articles/", "/post/", "/posts/",
                               "/blog/", "/p/", "/story/", "/stories/", "/entry/", "/read/"]
        if articlePatterns.contains(where: { path.contains($0) }) { return true }

        // Year segment: /2024/ /2025/ etc.
        if path.range(of: #"/20\d\d/"#, options: .regularExpression) != nil { return true }

        // Slug-like last segment: three or more hyphen-separated words
        let segments = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if let last = segments.last, last.components(separatedBy: "-").count >= 3 { return true }

        return false
    }

    private static func deSlug(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "" }
        let segments = url.path.components(separatedBy: "/").filter { !$0.isEmpty }
        guard let slug = segments.last, !slug.isEmpty else { return "" }
        let base = slug.components(separatedBy: ".").first ?? slug  // strip file extension
        return base
            .components(separatedBy: CharacterSet(charactersIn: "-_"))
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func rootDomain(_ host: String) -> String {
        let parts = host.components(separatedBy: ".")
        return parts.count > 2 ? parts.suffix(2).joined(separator: ".") : host
    }

    private static func normalise(_ urlString: String, base: URL) -> String? {
        guard let url = URL(string: urlString, relativeTo: base)?.absoluteURL else { return nil }
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: true)
        comps?.fragment = nil  // strip #comments, #respond, etc.
        let trackingPrefixes = ["utm_", "fbclid", "gclid", "mc_cid", "mc_eid"]
        let filtered = comps?.queryItems?.filter { item in
            !trackingPrefixes.contains(where: { item.name.lowercased().hasPrefix($0) })
        }
        comps?.queryItems = filtered?.isEmpty == true ? nil : filtered
        guard var result = comps?.url?.absoluteString else { return nil }
        if result.hasSuffix("/") { result = String(result.dropLast()) }
        return result
    }
}
