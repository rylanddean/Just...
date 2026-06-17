# Scraped Web Feeds

**Tier:** Free  
**Effort:** M  
**Status:** Done

Let users subscribe to any article-publishing web page — not just RSS feeds. Just… scrapes the page on each fetch cycle, identifies new article links, and surfaces them in FeedDetailView exactly like a real RSS feed.

---

## The Problem

RSS is wonderful, but most of the web doesn't publish it. Sports sites, game publishers, studio blogs, local news outlets, and niche hobby pages exist only as HTML. When a user pastes `https://www.pokemon.com/us/pokemon-news` into the "Add a URL" sheet today, the app fails with a parse error — even though the page has clearly structured article cards.

The fix is not to force the user to find a feed URL. The fix is to make the URL they already have work.

---

## How It Works

### URL Entry Flow (No New UI Required)

The existing "Add a URL" sheet is unchanged. The difference is what happens after the user taps Add:

1. **Try RSS/Atom/JSON Feed first** (current behaviour via FeedKit).
2. **If FeedKit fails**, fall back to `WebFeedScraper` — scrape the page as a web feed.
3. If scraping finds at least one article link, create the `RSSFeed` with `feedType: .scraped`.
4. If scraping also fails, show the existing error state.

The user never knows which path ran. It just works or it doesn't.

### Scraping Pipeline

`WebFeedScraper` fetches the page HTML and extracts article links in priority order:

**Pass 1 — Structured Data (JSON-LD)**  
Look for `<script type="application/ld+json">` blocks containing `@type: "Article"`, `"NewsArticle"`, or `"BlogPosting"`. These give the most reliable URL + title + date triples. Many news sites and CMS platforms emit these automatically.

**Pass 2 — Feed Discovery**  
Check `<link rel="alternate" type="application/rss+xml">` and similar in `<head>`. If found, hand off to FeedKit — the page itself *is* the discovery mechanism and we can get a real feed. Mark the stored `RSSFeed.url` as the discovered feed URL instead of the page URL.

**Pass 3 — Semantic HTML**  
Walk `<article>`, `<main>`, and `<section>` containers. Inside each, find `<a>` tags where the `href` looks like an article path (see filtering rules below). Use the first `<h1>`/`<h2>`/`<h3>` child as the title. Use `<time datetime="">` or `<meta property="article:published_time">` as the published date.

**Pass 4 — Link Density Heuristic**  
If none of the above yields results, scan all `<a>` tags on the page, filter by article path patterns, and return the top matches by DOM proximity to the page's primary content block (heuristic: furthest from `<header>` and `<footer>`).

### Article Link Filtering Rules

**Keep a link if:**
- It is on the same domain (or a subdomain) as the subscribed URL
- Its path matches article patterns: contains `/news/`, `/article/`, `/post/`, `/blog/`, `/p/`, a year segment (`/2024/`, `/2025/`), or a slug-looking path segment (≥ 3 words joined by hyphens)
- The anchor text is longer than 15 characters (a headline, not a button)

**Discard a link if:**
- It points to a different domain (cross-site links are navigation, not articles)
- The path is the same as the subscribed URL (homepage link in a logo)
- The path matches utility patterns: `/tag/`, `/author/`, `/category/`, `/search/`, `/login/`, `/subscribe/`
- The anchor text is a single word or looks like a label ("Read more", "View all", "Next")

### Metadata Extraction Per Article

For each discovered link, extract what's available without a per-article network fetch:

| Field | Source Priority |
|---|---|
| `title` | JSON-LD `name` → `<h2>/<h3>` sibling text → anchor text → URL slug de-slugged |
| `publishedAt` | JSON-LD `datePublished` → `<time datetime>` → `article:published_time` → current time |
| `feedDescription` | JSON-LD `description` → `<p>` first sibling → `og:description` of parent container |

Published date is the weakest field — many pages omit it from listing views. When absent, use the fetch timestamp. This means scraped feeds won't sort perfectly by publish date on the first scrape, but subsequent scrapes will have the same fallback consistently.

### Delta Detection

Scraped feeds have no `<lastBuildDate>` or Atom `<updated>`. To find new articles:

1. On each fetch, run the full scrape to get a current set of article URLs.
2. Compare against `RSSArticle` rows with matching `feedID`.
3. Only insert articles whose URLs aren't already in SwiftData.
4. Never delete scraped articles from SwiftData (unlike RSS articles which are pruned after 2 days). Scraped pages often don't re-surface old items, so once an article is known it should stay visible until the standard pruning age.

---

## Model Changes

### `RSSFeed` — add `feedType`

```swift
enum FeedType: String, Codable {
    case rss
    case atom
    case jsonFeed
    case scraped   // new
}
```

Add `var feedType: FeedType = .rss` to `RSSFeed`. Existing feeds default to `.rss` (migration is non-breaking — SwiftData default values handle this).

The `feedType` drives two behaviours:
- `RSSFetchService`: routes scraped feeds to `WebFeedScraper` instead of FeedKit
- `FeedDetailView`: shows a small "~" indicator in the feed header to signal it's a scraped approximation (see UX section)

---

## Service Changes

### New: `WebFeedScraper`

```swift
actor WebFeedScraper {
    func scrape(url: String) async throws -> ScrapedFeed
}

struct ScrapedFeed: Sendable {
    let title: String           // from <title> or og:title
    let articles: [ParsedArticle]
    let discoveredFeedURL: String? // if Pass 2 found a real feed
}
```

`ParsedArticle` is already defined in `RSSFetchService` — reuse it.

Dependencies: **SwiftSoup** (already referenced in the newsletter-import backlog for HTML parsing; same dependency).

### `RSSFetchService` — fallback routing

In `parseFeed(urlString:)`, wrap the existing FeedKit call in a `do/catch`. On failure, call `WebFeedScraper.scrape(url:)`. If that returns a `discoveredFeedURL`, retry FeedKit with that URL and update the stored feed URL. Otherwise proceed with the scraped articles.

In `fetchSingle()` (called after subscribing to a new feed), use the same fallback. If the scrape succeeds, update the `RSSFeed` record's `feedType` to `.scraped` and `title` to the scraped page title before returning.

---

## UX Details

### FeedDetailView — Scraped Feed Indicator

When `feed.feedType == .scraped`, show a subtle label beneath the feed title: *"Scraped from web — article dates may be approximate."* Use the same secondary text style as the existing subtitle text. No icon needed — the message is self-explanatory.

### Add URL Sheet — No Change

No new UI. The fallback is invisible to the user. If scraping fails, the existing error message ("Couldn't find a feed at that URL") is accurate and sufficient.

### Rename Sheet — No Change

Scraped feeds can be renamed the same as any other feed.

---

## What This Doesn't Do

- **Per-article full-page fetches** — we do not fetch each discovered article URL to extract better metadata. The cost (N network requests per feed per fetch cycle) is too high. AI summarization already runs after the article is opened in the reader; that's the right place for enrichment.
- **JavaScript-rendered pages** — `URLSession` fetches raw HTML; pages that render article lists via JavaScript (React SPAs, etc.) will yield no results. This is acceptable for V1. Most news/blog sites serve fully rendered HTML for SEO reasons.
- **Custom CSS selectors per site** — no per-site configuration. Heuristics cover the common case. Power users who need precision should find the site's actual RSS feed.
- **Scraping frequency control** — scraped feeds run on the same daily schedule as RSS feeds. No separate rate limiting.

---

## Technical Notes

### SwiftSoup

Add `SwiftSoup` as a Swift Package dependency (same one referenced in newsletter-import). It is a pure Swift HTML parser with no networking — safe to run inside `RSSFetchActor`.

### Background Task Compatibility

`WebFeedScraper` uses `URLSession` for the initial page fetch, which is compatible with `BGProcessingTask`. No change needed to the background job scheduler.

### URL Normalisation

Before comparing scraped article URLs against existing `RSSArticle` records, normalise: strip query parameters that are tracking tokens (`utm_*`, `ref=`, `source=`), strip trailing slashes, lower-case the scheme and host. Use the same normalisation in both the insert check and the stored `url` field.

---

## Acceptance Criteria

- [ ] Pasting `https://www.pokemon.com/us/pokemon-news` into the Add URL sheet subscribes successfully and populates articles in FeedDetailView
- [ ] A page with a discoverable `<link rel="alternate" type="application/rss+xml">` in its `<head>` is stored as a standard RSS feed, not a scraped feed — the real feed URL is used
- [ ] Scraped articles are not deleted after 2 days (standard pruning skips `.scraped` feeds)
- [ ] Repeated fetches of a scraped feed only insert articles with URLs not already stored — no duplicates
- [ ] URL normalisation strips `utm_*` and `ref=` params before deduplication
- [ ] FeedDetailView shows the "Scraped from web" notice for `.scraped` feeds
- [ ] A page that fails both FeedKit and scraping shows the existing "Couldn't find a feed" error
- [ ] Adding an already-valid RSS URL still works exactly as before — the scrape fallback is never triggered
- [ ] Scraped feed fetch runs in `RSSFetchActor` (background-safe, no main thread work)
- [ ] Feed title auto-populated from `og:title` or `<title>` of the scraped page
