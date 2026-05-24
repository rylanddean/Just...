# Offline Queue Prefetch

**Tier:** Free  
**Effort:** S  
**Status:** Backlog — Original Feature

In the background, silently fetch and strip cached HTML for all queued links that don't yet have a `cachedHTML` value. When the user opens an article, it renders instantly — no loading spinner, even without internet. Designed for commuters, travellers, and anyone who saves links at home to read on the go.

---

## Why

Just… is explicitly a "read this thing you saved" app. Saving typically happens on a good connection (home WiFi, office). Reading typically happens on a worse one (commute, train, airplane). Today, the reader fetches on-demand — a slow or absent connection means a spinner or an error, which breaks the reading habit at exactly the wrong moment.

Pre-fetching closes this gap entirely. The architecture already caches stripped HTML in `QueuedLink.cachedHTML` and the reader already short-circuits the fetch when it's present. This feature is the bridge that gets the cache populated before the user asks for it.

---

## Experience

**Invisible by design.** No UI, no progress indicator, no "downloading" label. When a link is added to the queue, the app schedules a background fetch. The next time the user opens that article, the reader renders immediately. Nothing to tap, nothing to configure.

**Failure:** If the background fetch fails (no connectivity, server error, paywall), the link retains `cachedHTML = nil`. The reader falls back to its normal on-demand fetch path. No error is ever surfaced to the user for this silent path.

**Data usage:** Background fetches are gated behind iOS's standard "Background App Refresh" system setting — the same control users already know. No additional settings required in Just….

---

## Technical Approach

**Background task:** Register `BGAppRefreshTask` with identifier `com.rylandean.justellipsis.prefetch` in `JustEllipsisApp`. When the system fires the task:
1. Fetch all `QueuedLink` records where `cachedHTML == nil`.
2. Process up to 3 links (BGAppRefreshTask has ~30s; 3 is safe).
3. Call `ContentFetcher.fetch(urlString:)` for each.
4. Write back `cachedHTML`, `title`, and `domain` if not already set.
5. Call `task.setTaskCompleted(success: true)`.

**In-process prefetch:** When `scenePhase == .active` (app foregrounded), trigger a lightweight prefetch for up to 2 links with `cachedHTML == nil`. Runs on a detached `Task` — never on the main actor.

**URLSession configuration:** Use `URLSessionConfiguration.default` with `waitsForConnectivity = true` — gracefully waits for a connection rather than failing immediately. Timeout: 15s per link.

**No duplicate fetches:** Check `cachedHTML != nil` before fetching. If the user opens the article while a background fetch is in-flight, `ContentFetcher` fetches in-process and wins — both paths are idempotent writes to `cachedHTML`.

---

## Acceptance Criteria

- [ ] Links with `cachedHTML == nil` are prefetched in background
- [ ] Article renders instantly (no loading spinner) when `cachedHTML` is populated
- [ ] Fetch failure leaves `cachedHTML = nil`; on-demand reader path is unaffected
- [ ] No more than 3 links fetched per background task
- [ ] In-process prefetch triggers on app foreground
- [ ] No UI for this feature — entirely invisible to the user
- [ ] Background task respects iOS Background App Refresh system setting
- [ ] `title` and `domain` are populated as a side-effect of prefetch
