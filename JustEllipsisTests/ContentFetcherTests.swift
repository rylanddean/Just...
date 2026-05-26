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

    let linkedPostHTML = """
    <html>
    <head><title>Link Post</title></head>
    <body>
      <dl class="linkedlist">
        <dt><a href="https://external.example.com/full-article">A full article</a></dt>
        <dd>
          <p>Short commentary excerpt with context.</p>
        </dd>
      </dl>
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

    @Test("Strip removes inline SVG icons")
    func stripRemovesInlineSVGIcons() throws {
        let url = URL(string: "https://example.com/article")!
        let html = """
        <html><body>
          <article>
            <h1>Title</h1>
            <p>This paragraph is long enough to be picked as real article content by the extractor.</p>
            <svg><path d="M0 0h10v10z"></path></svg>
          </article>
        </body></html>
        """
        let result = try ContentFetcher.strip(html: html, sourceURL: url)
        #expect(!result.body.contains("<svg"))
        #expect(!result.body.contains("<path"))
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

    @Test("extractPrimaryOutboundURL prefers external linked post URL")
    func extractPrimaryOutboundURLFindsLinkedTarget() throws {
        let sourceURL = URL(string: "https://daringfireball.net/linked/2014/01/29/haynes-aapl")!
        let resolved = ContentFetcher.extractPrimaryOutboundURL(from: linkedPostHTML, sourceURL: sourceURL)
        #expect(resolved?.absoluteString == "https://external.example.com/full-article")
    }

    @Test("extractPrimaryOutboundURL ignores same-host links")
    func extractPrimaryOutboundURLIgnoresSameHost() throws {
        let sourceURL = URL(string: "https://daringfireball.net/linked/2014/01/29/haynes-aapl")!
        let html = """
        <html><body>
          <dl class="linkedlist">
            <dt><a href="https://www.daringfireball.net/archives">Archive</a></dt>
          </dl>
        </body></html>
        """
        let resolved = ContentFetcher.extractPrimaryOutboundURL(from: html, sourceURL: sourceURL)
        #expect(resolved == nil)
    }

    @Test("isValidOutboundTarget rejects non-http links")
    func isValidOutboundTargetRejectsNonHTTP() throws {
        let sourceURL = URL(string: "https://daringfireball.net/linked/2014/01/29/haynes-aapl")!
        let mailtoURL = URL(string: "mailto:someone@example.com")!
        #expect(ContentFetcher.isValidOutboundTarget(mailtoURL, sourceURL: sourceURL) == false)
    }
}
