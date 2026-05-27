# JavaScript Reader Fallback

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

When `URLSession` returns raw HTML from a JavaScript-rendered page, the content is often absent — React and Next.js apps don't exist yet at the time the HTTP response arrives. The fix is to use the WKWebView engine already embedded in the app as a headless renderer: load the URL, let JavaScript run, extract the fully rendered DOM, then pass it through the existing strip pipeline. No new dependency. No third-party API. The browser is already here.

---

## The Problem

`ContentFetcher.fetch()` downloads raw HTML with `URLSession`. For server-rendered sites this works well. For JS-heavy sites it silently fails: the HTML payload is a shell — a `<div id="root">` and a bundle reference — and after stripping, the word count is below the 50-word floor. The reader never opens.

The example that motivated this feature: `https://leaddev.com/career-development/reality-being-principal-engineer` — a Next.js/Storyblok article. The content exists and is publicly readable in a browser. `URLSession` gets a skeleton.

This is not an edge case. Next.js, Gatsby, Remix, Ghost (some themes), Substack (reader mode), and a growing share of the modern publishing stack fall here.

---

## The Workaround

iOS ships a full browser engine as part of WebKit. `WKWebView` is already imported in `ReaderWebView.swift`. The same engine that renders Just…'s reader view can render a page off-screen, execute its JavaScript, and hand back the live DOM.

```
URLSession fetch → strip → word count ≥ 50?
    YES → done (current path)
    NO  → JSRenderer.render(url:) → evaluateJavaScript("outerHTML") → strip → done
```

This runs entirely on-device. No URL leaves the user's device to a third-party service. The WKWebView is ephemeral — created for the render, discarded after.

---

## How It Works

### JSRenderer

A new `@MainActor` service. `WKWebView` has always required the main thread; `ReaderViewModel` is already `@MainActor`, so no actor hop is needed.

```swift
@MainActor
final class JSRenderer: NSObject, WKNavigationDelegate {
    static let shared = JSRenderer()

    func render(url: URL, timeout: TimeInterval = 12) async throws -> String
}
```

Internally:

1. Allocate a `WKWebView` with `WKWebViewConfiguration` using `.nonPersistent()` data store — no cookies, no session state, no bleed from the reader session.
2. Load the URL with a standard `URLRequest`.
3. Wait for `webView(_:didFinish:)` via an `AsyncStream` / continuation pattern.
4. After `didFinish`, poll readiness: evaluate `document.readyState === 'complete' && document.body.innerText.length > 200` up to 5 times at 500ms intervals. Most SPAs finish their async data fetch within 2–3 seconds of the base navigation completing.
5. Once ready (or after polling exhausted), call `evaluateJavaScript("document.documentElement.outerHTML")`.
6. Return the rendered HTML string to the caller.
7. If the timeout elapses before readiness: throw `JSRenderError.timeout`. The reader falls through to the existing error state.
8. Deallocate the `WKWebView` immediately after extraction.

WKWebView does not require a superview to render since iOS 14. The instance is held alive by the `JSRenderer` during the async operation, then released.

### ContentFetcher.fetchWithJSFallback()

Add a new entry point that wraps the existing `fetch()` and calls `JSRenderer` on sparse results:

```swift
@MainActor
static func fetchWithJSFallback(
    urlString: String,
    cachedHTML: String? = nil,
    theme: ReaderTheme = .ember
) async throws -> FetchResult
```

Internally:

```
1. Try ContentFetcher.fetch() (existing path)
2. If result.content.estimatedWordCount >= 50 → return it
3. If word count < 50 (or fetch threw .emptyContent):
   a. JSRenderer.shared.render(url:)
   b. ContentFetcher.strip(html: renderedHTML, sourceURL: url, theme:)
   c. If word count >= 50 → return FetchResult(content, rawHTML: renderedHTML)
   d. If still < 50 → throw FetchError.emptyContent
```

The `cachedHTML` fast-path still runs first. If the cached HTML was itself JS-rendered (from a previous open), it will pass the word count check and skip re-rendering.

### ReaderViewModel integration

Replace the `ContentFetcher.fetch()` call in `load(link:context:)` with `ContentFetcher.fetchWithJSFallback()`. This is a one-line call-site change.

Add a second state flag:

```swift
var isJSRendering: Bool = false
```

Set `isJSRendering = true` before the JS fallback path executes, and `false` when it completes. The loading view reads this flag to show appropriate copy (see UX section). The flag is always reset on completion regardless of outcome.

`loadURL(_:)` (used by the preview path) gets the same treatment.

---

## UX

### Loading copy

The existing loading state in `ReaderView` shows a shimmer. When `isJSRendering` is true, add one line below the shimmer in `.mono` style, `muted` colour:

```
Extracting content.
```

No progress indicator. No dots. One calm sentence. It appears ~1 second in, after a brief delay — most pages render fast enough that users won't see it. `DM Mono`, 13pt, `muted` colour. Disappears when content loads.

### Error state — no change

If JSRenderer also fails (paywall, login wall, bot detection), the error state is the same: `FetchError.emptyContent`. The existing error view handles it. No new error copy needed. The "Open in browser" escape hatch already in the error view is the correct recovery path for gated content.

### First open delay

JS rendering adds ~1–4 seconds on first open. After first open, the rendered HTML is cached in `QueuedLink.cachedHTML` exactly as before. Subsequent opens are instant.

---

## What This Handles

| Site type | Before | After |
|-----------|--------|-------|
| Next.js SSR (LeadDev, Vercel sites) | Empty or skeleton | Full article |
| React SPA with async data fetch | Empty | Full article (if data fetches complete within timeout) |
| Ghost (some themes) | Unreliable | Full article |
| Server-rendered HTML (most news) | Works | Works (URLSession path, no change) |
| Paywalled content (NYT, FT) | Empty | Still empty — login wall renders instead |
| Sites with bot detection | Empty | May still fail — WKWebView uses a real UA but some sites detect headless patterns |

The paywall and bot-detection cases are explicitly out of scope. Just… is a reading discipline app, not a paywall bypass. Users who want to read paywalled content should subscribe to the publication.

---

## What This Doesn't Do

- **Background prefetch** — WKWebView cannot run in a `BGProcessingTask` or `BGAppRefreshTask`. The fallback only fires when the reader is open (foreground). Prefetch via `URLSession` still runs as before; if it returns sparse HTML, the reader detects this on open and renders live.
- **Per-site workarounds** — No custom JavaScript injection per publisher, no cookie injection, no header spoofing. The renderer uses default WebKit behaviour.
- **Infinite scroll** — Content that requires user interaction (scroll to load more) is not fetched. The renderer captures the DOM at first-paint readiness.
- **Login-gated content** — WKWebView uses a non-persistent data store; no session cookies means no authenticated content.

---

## Technical Notes

### WKWebView data isolation

Using `.nonPersistent()` is essential. It prevents:
- Cookies from the reader session leaking into the rendered page
- The rendered page's cookies (ad tracking, analytics) persisting after the view is deallocated
- Session state from a previous render affecting subsequent renders

### User-Agent

WKWebView sends the standard Safari UA. Do not override it — a custom UA increases fingerprinting surface and is more likely to trigger bot detection than the default.

### Memory

A single WKWebView instance rendering a complex page can briefly spike to 30–80 MB. `JSRenderer` holds one `WKWebView` at a time and deallocates it immediately after extraction. If the user opens multiple links rapidly (unlikely given the reading loop), renders are serialised through `JSRenderer.shared`.

### Main actor safety

`JSRenderer` is `@MainActor`. `ReaderViewModel` is `@MainActor`. `ContentFetcher.fetchWithJSFallback()` is `@MainActor`. The existing `fetch()` and `strip()` functions remain `nonisolated` — the JS path adds an actor constraint only at the call site, not inside the strip logic.

### Caching strategy

The rendered HTML is stored in `QueuedLink.cachedHTML` — same field, same path as the URLSession-fetched HTML. No schema change. On second open, the cache check (`if let cached = cachedHTML, !cached.isEmpty`) hits before any fetch, so re-rendering never runs on a link the user has already read.

---

## Acceptance Criteria

- [ ] Opening `https://leaddev.com/career-development/reality-being-principal-engineer` in the reader renders the full article body — at least 400 words of readable content
- [ ] URLSession-fetchable articles (word count ≥ 50) never trigger `JSRenderer` — the fallback is never called for content the existing pipeline handles
- [ ] JS-rendered HTML is cached in `QueuedLink.cachedHTML`; second open of the same link does not call `JSRenderer` or `URLSession`
- [ ] `isJSRendering = true` only while the WKWebView is active; loading view shows "Extracting content." after a 1-second delay
- [ ] `WKWebView` is deallocated after HTML extraction — confirmed via Instruments memory snapshot
- [ ] `.nonPersistent()` data store used — no cookies written to disk
- [ ] Timeout of 12 seconds: if the page does not reach readiness within this window, `JSRenderError.timeout` is thrown and the error state is shown
- [ ] Standard server-rendered articles (BBC, The Guardian, The Atlantic) continue to load via the existing URLSession path with no regression in speed or accuracy
- [ ] `loadURL(_:)` in `ReaderViewModel` also uses the JS fallback — brain entry re-reads and share extension previews benefit
- [ ] No new third-party dependency added to the project
