import Testing
import Foundation
@testable import JustEllipsis

@Suite("ContentFetcher")
struct ContentFetcherTests {

    let sampleHTML = """
    <html>
    <head><title>Test Article</title></head>
    <body>
      <nav>Navigation noise</nav>
      <header>Site header</header>
      <article>
        <h1>The Main Heading</h1>
        <p>This is the first paragraph with enough content to be considered for extraction.</p>
        <p>Second paragraph adds more substance to the article body text.</p>
        <p>Third paragraph for completeness. The more paragraphs, the better the extraction works.</p>
        <img src="hero.jpg" alt="">
      </article>
      <aside>Related links</aside>
      <footer>Site footer</footer>
      <script>alert('noise')</script>
    </body>
    </html>
    """

    @Test("Strip removes noise elements")
    func stripRemovesNoise() throws {
        let url = URL(string: "https://example.com/article")!
        let result = try ContentFetcher.strip(html: sampleHTML, sourceURL: url)

        #expect(!result.body.contains("<nav>"))
        #expect(!result.body.contains("<header>"))
        #expect(!result.body.contains("<footer>"))
        #expect(!result.body.contains("<aside>"))
        #expect(!result.body.contains("<script>"))
        #expect(!result.body.contains("<img"))
    }

    @Test("Strip preserves article paragraphs")
    func stripPreservesParagraphs() throws {
        let url = URL(string: "https://example.com/article")!
        let result = try ContentFetcher.strip(html: sampleHTML, sourceURL: url)
        #expect(result.body.contains("first paragraph"))
    }

    @Test("Strip extracts page title")
    func stripExtractsTitle() throws {
        let url = URL(string: "https://example.com/article")!
        let result = try ContentFetcher.strip(html: sampleHTML, sourceURL: url)
        #expect(result.title == "Test Article")
    }

    @Test("extractDomain strips www prefix")
    func extractDomainStripsWWW() {
        let url = URL(string: "https://www.nytimes.com/article")!
        #expect(ContentFetcher.extractDomain(from: url) == "nytimes.com")
    }

    @Test("extractDomain handles bare domain")
    func extractDomainBareDomain() {
        let url = URL(string: "https://medium.com/article")!
        #expect(ContentFetcher.extractDomain(from: url) == "medium.com")
    }

    @Test("Word count is positive for non-empty content")
    func wordCountPositive() throws {
        let url = URL(string: "https://example.com/article")!
        let result = try ContentFetcher.strip(html: sampleHTML, sourceURL: url)
        #expect(result.estimatedWordCount > 0)
    }

    @Test("Reading time is at least 1 minute")
    func readingTimeMinimum() throws {
        let url = URL(string: "https://example.com/article")!
        let result = try ContentFetcher.strip(html: sampleHTML, sourceURL: url)
        #expect(result.estimatedReadingMinutes >= 1)
    }

    @Test("Cached HTML path returns same content")
    func cachedHTMLPath() async throws {
        let url = URL(string: "https://example.com/article")!
        let stripResult = try ContentFetcher.strip(html: sampleHTML, sourceURL: url)
        // Simulate cached path by passing the raw HTML back in
        let fetchResult = try await ContentFetcher.fetch(urlString: url.absoluteString, cachedHTML: sampleHTML)
        #expect(fetchResult.content.title == stripResult.title)
    }
}
