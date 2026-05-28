import Testing
import Foundation
@testable import JustEllipsis

@Suite("FeedURLNormaliser")
struct FeedURLNormaliserTests {

    // MARK: - Substack normalisation

    @Test func substackRootURL() {
        let result = FeedURLNormaliser.normalise("https://rdel.substack.com")
        #expect(result?.absoluteString == "https://rdel.substack.com/feed")
    }

    @Test func substackRootURLWithTrailingSlash() {
        let result = FeedURLNormaliser.normalise("https://rdel.substack.com/")
        #expect(result?.absoluteString == "https://rdel.substack.com/feed")
    }

    @Test func substackURLWithoutScheme() {
        let result = FeedURLNormaliser.normalise("rdel.substack.com")
        #expect(result?.absoluteString == "https://rdel.substack.com/feed")
    }

    @Test func substackFeedURLPassthrough() {
        let result = FeedURLNormaliser.normalise("https://rdel.substack.com/feed")
        #expect(result?.absoluteString == "https://rdel.substack.com/feed")
    }

    @Test func substackPostURLPassthrough() {
        let result = FeedURLNormaliser.normalise("https://rdel.substack.com/p/some-post")
        #expect(result?.absoluteString == "https://rdel.substack.com/p/some-post")
    }

    // MARK: - Non-Substack passthrough

    @Test func regularRSSURLPassthrough() {
        let result = FeedURLNormaliser.normalise("https://example.com/feed.xml")
        #expect(result?.absoluteString == "https://example.com/feed.xml")
    }

    @Test func urlWithoutSchemeGetsHTTPS() {
        let result = FeedURLNormaliser.normalise("example.com/feed")
        #expect(result?.scheme == "https")
    }

    @Test func invalidURLReturnsNil() {
        let result = FeedURLNormaliser.normalise("not a url !!!")
        #expect(result == nil)
    }

    @Test func whitespaceIsTrimmed() {
        let result = FeedURLNormaliser.normalise("  https://rdel.substack.com  ")
        #expect(result?.absoluteString == "https://rdel.substack.com/feed")
    }
}
