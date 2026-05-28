# Substack Feeds

**Tier:** Free  
**Effort:** XS  
**Status:** Backlog

Resolve a Substack publication URL — the kind a reader already has bookmarked — into a working RSS feed automatically. The user pastes what they know; Just… figures out the rest.

---

## The Problem

Substack is where a meaningful share of the best long-form writing lives today. Every Substack publication has a native RSS feed at `[publication].substack.com/feed`. But readers know the publication URL (`rdel.substack.com`), not the feed URL. When they paste the publication URL into the "Add a URL" sheet today, FeedKit fails — the home page is not a feed.

The fix is not to teach readers about `/feed`. The fix is to make the URL they already have work.

---

## How It Works

### URL Normalisation (Invisible to the User)

The existing "Add a URL" sheet is unchanged. The difference is what happens before FeedKit runs:

1. The URL passes through `FeedURLNormaliser`.
2. If the host matches `*.substack.com` and the path is `/` or empty, append `/feed`.
3. The normalised URL is passed to FeedKit as if the user had typed it directly.
4. FeedKit parses the Atom feed and creates the `RSSFeed` with `feedType: .atom`.

The user never knows a normalisation step ran. The feed appears in `FeedsView` like any other.

### Normalisation Rules

| Input | Normalised |
|---|---|
| `https://rdel.substack.com` | `https://rdel.substack.com/feed` |
| `https://rdel.substack.com/` | `https://rdel.substack.com/feed` |
| `rdel.substack.com` | `https://rdel.substack.com/feed` |
| `https://rdel.substack.com/p/some-post` | unchanged — individual post URL, not a publication |
| `https://rdel.substack.com/feed` | unchanged — already the feed URL |

Individual post URLs (`/p/...`) are not normalised. They fall through to the standard URL flow: the reader opens the post directly.

---

## Experience

### Adding a Substack

The user taps **+** in the Feeds tab, selects **RSS Feed**, and pastes:

```
https://rdel.substack.com
```

Just… normalises to `https://rdel.substack.com/feed`, parses the Atom feed, and navigates to the new feed card in `FeedsView`. The publication name comes from the feed's `<title>` element — no manual naming required.

No new sheet, no new flow. It works the same way adding `rdel.substack.com/feed` would — because that is exactly what happened.

### If the Publication Does Not Exist

FeedKit returns a 404 or parse failure. The existing error state surfaces:

```
Couldn't add that feed. Check the URL and try again.
```

No Substack-specific error copy — the user already knows what they typed.

---

## Technical Approach

### `FeedURLNormaliser`

```swift
struct FeedURLNormaliser {
    static func normalise(_ raw: String) -> URL? {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.hasPrefix("http") { string = "https://\(string)" }
        guard var components = URLComponents(string: string) else { return nil }

        if let host = components.host, host.hasSuffix(".substack.com") {
            let path = components.path
            if path.isEmpty || path == "/" {
                components.path = "/feed"
            }
        }

        return components.url
    }
}
```

`normalise(_:)` is called once in `AddFeedViewModel.submit()`, before the FeedKit fetch. It is pure — no network calls, no side effects, testable without a simulator.

Adding support for another platform (Ghost, Buttondown) later is a single `else if` branch.

### No Model Changes

Substack feeds are stored as `feedType: .atom` — which is exactly what they are. No new `FeedType` case. No migration.

---

## Relationship to `newsletter-feeds.md`

Newsletter Feeds (Kill the Newsletter) handles publications that publish **only** by email — no RSS exists. Substack is the opposite: native Atom, no email subscription needed.

| Publication type | Right path |
|---|---|
| Substack, Ghost, Buttondown | **Substack Feeds** — RSS normalisation |
| Email-only (Stratechery, The Browser) | **Newsletter Feeds** — Kill the Newsletter |

The two paths are complementary and can coexist. The `+` sheet does not need to distinguish them — normalisation runs first, email fallback runs if normalisation yields no feed.

---

## Brand Alignment

| Principle | Check |
|---|---|
| No new UI | ✅ — existing sheet, existing error state |
| No new backend | ✅ — normalisation is local, FeedKit fetches directly |
| All data on-device | ✅ — feed stored in SwiftData; polled on-device |
| Calm, invisible UX | ✅ — the user pastes a URL and it works |
| Honest failure | ✅ — error copy unchanged, no false promises |

---

## Copy Reference

No new copy is required. The existing "Add a URL" sheet strings cover this path exactly.

| Moment | Copy |
|---|---|
| Sheet prompt | "Paste a URL." |
| Error state | "Couldn't add that feed. Check the URL and try again." |

---

## Acceptance Criteria

- [ ] `FeedURLNormaliser.normalise(_:)` converts `*.substack.com` root URLs to `*.substack.com/feed`
- [ ] Normalisation runs before FeedKit in `AddFeedViewModel.submit()`
- [ ] Pasting `https://rdel.substack.com` adds the feed and navigates to it in `FeedsView`
- [ ] Pasting `https://rdel.substack.com/p/some-post` is not normalised — falls through to standard flow
- [ ] Pasting `https://rdel.substack.com/feed` directly still works — normaliser is a no-op
- [ ] Feed name is populated from the Atom `<title>` element — no manual entry required
- [ ] Feed is stored with `feedType: .atom` — no new FeedType case
- [ ] `FeedURLNormaliser` is unit-tested for all normalisation rules in the table above
- [ ] No new colours, typefaces, or navigation destinations introduced
