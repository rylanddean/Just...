# Offline Queue Prefetch

**Tier:** Free  
**Effort:** S  
**Status:** Backlog — Original Feature

In the background, silently fetch and strip cached HTML for all queued links that don't yet have a `cachedHTML` value. When the user opens an article, it renders instantly — no loading spinner, even without internet. Designed for commuters, travellers, and anyone who saves links at home to read on the go.

As part of prefetch, validate that each link actually resolved to readable content. Links that fail — dead URLs, paywalls, empty pages — are flagged directly in the queue so the user isn't surprised when they tap them.

---

## Why

Just… is explicitly a "read this thing you saved" app. Saving typically happens on a good connection (home WiFi, office). Reading typically happens on a worse one (commute, train, airplane). Today, the reader fetches on-demand — a slow or absent connection means a spinner or an error, which breaks the reading habit at exactly the wrong moment.

Pre-fetching closes this gap entirely. The architecture already caches stripped HTML in `QueuedLink.cachedHTML` and the reader already short-circuits the fetch when it's present. This feature is the bridge that gets the cache populated before the user asks for it.

---

## Experience

**Invisible by design.** No UI, no progress indicator, no "downloading" label. When a link is added to the queue, the app schedules a background fetch. The next time the user opens that article, the reader renders immediately. Nothing to tap, nothing to configure.

**Failure — transient (no connectivity, timeout):** The link retains `cachedHTML = nil` and `prefetchState = .pending`. The prefetcher will retry on the next foreground or background pass. Nothing shown to the user.

**Failure — permanent (dead URL, paywall, empty content):** The link is flagged with `prefetchState = .invalid`. A warning indicator appears on its `LinkCard` in the queue — a small muted icon (e.g. `exclamationmark.circle`) in the card's trailing edge with a tooltip: *"This link may not load."* The card remains in the queue; the user decides whether to remove it or try opening it anyway. No automatic deletion — Just… never removes content without the user's action.

**What counts as invalid:**
- HTTP 4xx / 5xx response
- Redirect to a login or paywall page (detected by checking stripped word count < 50 after parsing)
- Empty or near-empty body after stripping (`estimatedWordCount < 50`)
- URL resolves to a non-HTML resource (PDF, image, binary)

**Data usage:** Background fetches are gated behind iOS's standard "Background App Refresh" system setting — the same control users already know. No additional settings required in Just….

---

## Technical Approach

### Model Change

Add a `prefetchState` field to `QueuedLink`:

```swift
enum PrefetchState: String, Codable {
    case pending    // not yet attempted
    case ready      // cachedHTML populated, content valid
    case invalid    // fetched but content failed validation
    case retrying   // transient failure, will retry
}

// QueuedLink gains:
var prefetchState: PrefetchState = .pending
```

### Background Task

Register `BGAppRefreshTask` with identifier `com.rylandean.justellipsis.prefetch` in `JustEllipsisApp`. When the system fires the task:
1. Fetch all `QueuedLink` records where `prefetchState == .pending || .retrying`.
2. Process up to 3 links (BGAppRefreshTask has ~30s; 3 is safe).
3. For each, call `ContentFetcher.fetch(urlString:)` and run content validation.
4. Write result back — `cachedHTML` + `prefetchState` — and save.
5. Call `task.setTaskCompleted(success: true)`.

### Validation Logic

```swift
enum PrefetchResult {
    case ready(html: String, content: StrippedContent)
    case invalid(reason: InvalidReason)
    case transientFailure
}

enum InvalidReason {
    case httpError(statusCode: Int)
    case tooShort           // stripped word count < 50
    case nonHTMLResource
    case paywall            // word count < 50 after strip (paywall heuristic)
}

static func validate(urlString: String) async -> PrefetchResult {
    // 1. Make the request — capture HTTP status code
    // 2. Check Content-Type header is text/html
    // 3. Strip and check estimatedWordCount >= 50
    // 4. On network errors / timeouts → .transientFailure
    // 5. On 4xx/5xx or short content → .invalid(reason:)
}
```

Transient failures (`URLError.notConnectedToInternet`, `.timedOut`, etc.) set `prefetchState = .retrying`. Permanent failures set `prefetchState = .invalid`.

### In-Process Prefetch

When `scenePhase == .active`, trigger prefetch for up to 2 links with `prefetchState == .pending`. Runs on a detached `Task`, never on the main actor.

### LinkCard Flag

`LinkCard` reads `link.prefetchState`. When `.invalid`, show a small `Image(systemName: "exclamationmark.circle")` in `AppTheme.textFaint` at the card's trailing edge. No colour, no animation — muted and non-alarming. Tapping the icon does nothing in V1; a future version could show a popover with the reason.

### URLSession Configuration

`URLSessionConfiguration.default` with `waitsForConnectivity = false` for prefetch — skip links gracefully if offline rather than holding the background task open. Timeout: 12s per link.

---

## Acceptance Criteria

**Prefetch**
- [ ] Links with `prefetchState == .pending` are prefetched in background
- [ ] Article renders instantly (no loading spinner) when `prefetchState == .ready`
- [ ] No more than 3 links fetched per background task
- [ ] In-process prefetch triggers on app foreground for up to 2 links
- [ ] Background task respects iOS Background App Refresh system setting
- [ ] `title` and `domain` are populated as a side-effect of prefetch

**Validation**
- [ ] HTTP 4xx / 5xx response sets `prefetchState = .invalid`
- [ ] Non-HTML `Content-Type` sets `prefetchState = .invalid`
- [ ] Stripped word count < 50 sets `prefetchState = .invalid` (paywall / empty page heuristic)
- [ ] Network errors and timeouts set `prefetchState = .retrying` — retried on next pass
- [ ] A `prefetchState == .ready` link with valid `cachedHTML` is never re-fetched

**LinkCard Flag**
- [ ] `exclamationmark.circle` icon visible on cards where `prefetchState == .invalid`
- [ ] Icon is muted (`AppTheme.textFaint`) — not alarming, not prominent
- [ ] No flag shown on `.pending`, `.retrying`, or `.ready` cards
- [ ] Flagged cards remain in the queue — user decides to remove or open anyway
- [ ] Opening a flagged card attempts a fresh on-demand fetch as normal
