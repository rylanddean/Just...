# JavaScript Reader Fallback

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

When `URLSession` returns sparse HTML from a JavaScript-rendered page, the content is often absent — React and Next.js apps don't exist yet at the time the HTTP response arrives. The fix is to use the WKWebView engine already embedded in the app as a headless renderer: load the URL, let JavaScript execute, extract the fully rendered DOM, then pass it through the existing strip pipeline. No new dependency. No third-party API.

---

## Why

`ContentFetcher.fetch()` downloads raw HTML with `URLSession`. For server-rendered sites this works well. For JS-heavy sites it silently fails: the HTML payload is a shell — a `<div id="root">` and a bundle reference — and after stripping, the word count falls below the threshold for a readable article.

This is not an edge case. Next.js, Gatsby, Remix, Ghost (some themes), and a growing share of the modern publishing stack fall here. A user who saves an article from a Vercel-hosted blog has no idea why Just… shows an empty reader — and has no path to fix it.

---

## Experience

### Loading State

The existing loading shimmer plays. When the JS fallback path activates (~1s after the initial fetch fails the word-count check), one calm line appears below the shimmer:

```
Extracting content.
```

DM Mono, 13pt, `muted` colour. No progress dots. Disappears when content loads.

Most articles render within 2–3 seconds. Fast enough that many users will never see this line.

### Error State — Unchanged

If the JS renderer also fails (paywall, login wall, bot detection), the error state is identical to the current one. The "Open in browser" button is the correct recovery path for gated content. No new error copy.

---

## Technical Approach

### JSRenderer

A new `@MainActor` service. `WKWebView` requires the main thread; `ReaderViewModel` is already `@MainActor`, so no actor hop is needed.

```swift
@MainActor
final class JSRenderer: NSObject, WKNavigationDelegate {
    static let shared = JSRenderer()
    private var continuation: CheckedContinuation<String, Error>?
    private var webView: WKWebView?

    func render(url: URL, timeout: TimeInterval = 12) async throws -> String
}
```

Internally:
1. Allocate a `WKWebView` with `.nonPersistent()` data store — no cookies, no session bleed.
2. Load the URL via a standard `URLRequest`.
3. Await `webView(_:didFinish:)` via a `CheckedContinuation`.
4. After `didFinish`, poll readiness: evaluate `document.body.innerText.length > 200` up to 5× at 500ms intervals.
5. Call `evaluateJavaScript("document.documentElement.outerHTML")` and return the result.
6. Deallocate the `WKWebView` immediately after extraction.
7. On timeout: throw `JSRenderError.timeout`.

WKWebView does not require a superview to render since iOS 14.

### ContentFetcher.fetchWithJSFallback()

A new entry point wrapping the existing `fetch()`:

```swift
@MainActor
static func fetchWithJSFallback(for link: QueuedLink) async throws -> StrippedContent
```

Logic:

```
1. Try ContentFetcher.fetch() (existing path — checks cachedHTML first)
2. If word count ≥ 50 → return it
3. If word count < 50:
   a. JSRenderer.shared.render(url:)
   b. ContentFetcher.strip(html: rendered, sourceURL:)
   c. If word count ≥ 50 → cache in QueuedLink.cachedHTML → return
   d. If still < 50 → throw FetchError.emptyContent
```

### ReaderViewModel Integration

Replace the `ContentFetcher.fetch()` call in `load(link:)` with `fetchWithJSFallback(for:)`. One call-site change.

Add:
```swift
var isJSRendering: Bool = false
```

Set `true` before the fallback executes, `false` on completion. `ReaderView` reads this flag to show or hide "Extracting content."

### Data Isolation

`.nonPersistent()` is non-negotiable. It prevents:
- Cookies from the reader session contaminating the rendered page
- Ad tracking cookies from the rendered page persisting after deallocation

### Memory

A single WKWebView rendering a complex page can spike to 30–80 MB briefly. `JSRenderer` holds one instance at a time, deallocates immediately after extraction. Rapid queue-opening serialises through `JSRenderer.shared` — no parallel renders.

---

## What This Handles

| Site type | Before | After |
|---|---|---|
| Next.js SSR / Vercel-hosted blogs | Empty reader | Full article |
| React SPA with async data fetch | Empty reader | Full article (if data fetches complete within 12s) |
| Standard server-rendered HTML | Works | Works — URLSession path unchanged |
| Paywalled content (NYT, FT) | Empty reader | Still empty — login wall renders instead |

Paywalled and bot-detected content is explicitly out of scope.

---

## Acceptance Criteria

- [ ] Opening a Next.js-rendered article in the reader renders the full article body
- [ ] URLSession-fetchable articles (word count ≥ 50) never trigger `JSRenderer`
- [ ] JS-rendered HTML is cached in `QueuedLink.cachedHTML`; second open skips both URLSession and JSRenderer
- [ ] "Extracting content." copy appears after a ~1s delay when JS fallback is active; disappears on load
- [ ] `isJSRendering` flag is set to `false` on all exit paths, including error
- [ ] `WKWebView` is deallocated after extraction — no persistent instance
- [ ] `.nonPersistent()` data store used — no cookies written to disk
- [ ] Timeout of 12 seconds: renders that exceed this throw and show the standard error state
- [ ] Standard server-rendered articles continue to load via the existing URLSession path with no regression
- [ ] No new third-party dependency
