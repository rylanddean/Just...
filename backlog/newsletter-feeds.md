# Newsletter Feeds

**Tier:** Free  
**Effort:** S  
**Status:** Backlog

Follow any email newsletter as a feed. Just… generates a private reading address, the user subscribes once, and new editions appear automatically in the queue — no inbox required, no credentials, no backend.

---

## The Problem

The best writing on the internet lives in email. Stratechery, Dense Discovery, The Browser, Lenny's Newsletter — none of these publish RSS. Right now a Just… user who subscribes to them has to open their mail app, find something worth reading, and manually add it. That is three extra steps for a habit that is supposed to feel effortless.

The share extension (see `newsletter-import.md`) solves this partially — the user can share an email into the queue — but it is still manual. Newsletter feeds make it automatic: subscribe once, and new editions arrive ready to read, exactly like an RSS feed.

---

## How It Works

### The Mechanism (Invisible to the User)

[Kill the Newsletter](https://kill-the-newsletter.com) is a free, MIT-licensed service that converts any email newsletter into an Atom feed. It exposes a JSON API endpoint — `POST /feeds` — that accepts a feed name and returns a unique email address and a feed URL. No account, no API key.

Just… calls this API when the user adds a newsletter. The user gets a reading address scoped to that newsletter. Just… stores the feed URL and polls it on the same daily schedule as RSS feeds. The mechanism is completely invisible — the user sees a newsletter, not a third-party service.

---

## Experience

### Adding a Newsletter

The user taps **+** in the Feeds tab and selects **Newsletter** (alongside the existing RSS option).

A sheet appears:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Follow a newsletter.

You'll get a reading address. Subscribe
to any newsletter with it. New editions
appear here automatically.

  Newsletter name
  ┌─────────────────────────────┐
  │ e.g. Dense Discovery        │
  └─────────────────────────────┘

                       [ Continue ]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- Sheet background: `surface`
- Headline in `.title` style, Playfair Display
- Body copy in `.mono`, `muted`
- Text field bordered in `amberDim`, text in `cream`
- "Continue" in `amber` — primary CTA

The name field accepts anything — it is a label the user gives this newsletter, not a URL. It populates the newsletter's name in the Feeds list.

---

### The Reading Address

After the user taps **Continue**, Just… calls the Kill the Newsletter API (one POST request, ~300ms). A second screen appears:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
YOUR READING ADDRESS

  abc123xyz@kill-the-newsletter.com   ⧉

Paste this into the subscription form
for Dense Discovery. New editions will
appear in your queue automatically.

                            [ Done ]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **"YOUR READING ADDRESS"** — `.label` style: DM Mono, all-caps, amber, letter-spaced
- The address itself in `.mono`, `cream`, full-width tap target that copies to clipboard
- Copy glyph (⧉) in `amberDim` — indicates tappability without explaining it
- On tap: address copies, glyph briefly fills amber (no toast, no banner — the colour change is enough)
- Body copy in `.mono`, `muted`
- **"Done"** dismisses the sheet and navigates to the new newsletter in `FeedsView`

If the API call fails (network error, service unavailable), the screen shows:

```
Couldn't create a reading address. Check your connection and try again.
```

With a **Retry** link in amber below. No technical detail exposed.

---

### The Newsletter in Feeds

The new newsletter appears in `FeedsView` alongside RSS feeds. Its card is identical to an RSS feed card but carries a small envelope glyph — the same visual language as the envelope glyph on auto-imported links in `newsletter-import.md`.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✉  Dense Discovery
   Waiting for first edition.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Subtitle copy states:
- Before first edition arrives: `"Waiting for first edition."`
- After at least one edition: `"Last edition [relative date]."` e.g. `"Last edition 2 days ago."`

Both in `.mono`, `subtle`.

---

### Reading a Newsletter Edition

When a new newsletter edition arrives, it appears in the queue as a single reading item attributed to the newsletter:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Dense Discovery № 237

✉ Dense Discovery · 12 min

[ADD TO QUEUE]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- Title from the newsletter edition's subject line (via Atom `<title>`)
- Source label: `✉ [Newsletter Name]` — the envelope glyph distinguishes newsletters from RSS in the queue
- The reader strips the newsletter HTML exactly like any other article — images, formatting, sidebars removed, body text rendered in Playfair Display

---

### Managing Newsletters

Long-press or swipe-to-delete on a newsletter in `FeedsView` removes it. The reading address becomes unreachable — any future editions sent to it are silently dropped by Kill the Newsletter. No cleanup required on the user's side.

Tapping a newsletter in `FeedsView` opens the standard `FeedDetailView` showing past editions in the Atom feed.

---

## Technical Approach

### API Call

```swift
struct KillTheNewsletterService {
    static func createFeed(title: String) async throws -> NewsletterFeed
}

struct NewsletterFeed: Sendable {
    let title: String
    let email: String     // the reading address shown to the user
    let feedURL: String   // the Atom feed URL polled by Just…
}
```

`POST https://kill-the-newsletter.com/feeds`  
Body: `title=<url-encoded-name>` (`application/x-www-form-urlencoded`)  
Header: `Accept: application/json`

Response:
```json
{ "feedId": "abc123", "email": "abc123@kill-the-newsletter.com", "feed": "https://kill-the-newsletter.com/feeds/abc123.xml" }
```

No authentication. Timeout: 10s. Retry once on network failure; surface error to user on second failure.

---

### Model Change — `RSSFeed`

Extend `FeedType` (from `scraped-web-feeds.md`) with a new case:

```swift
enum FeedType: String, Codable {
    case rss
    case atom
    case jsonFeed
    case scraped
    case newsletter  // new — Kill the Newsletter Atom feed
}
```

Add one field to `RSSFeed`:

```swift
var newsletterEmail: String? = nil  // the reading address; nil for non-newsletter feeds
```

This is the only model migration. Existing feeds are unaffected — `newsletterEmail` defaults to `nil` and `feedType` defaults to `.rss`.

---

### Feed Polling

Newsletter feeds are polled on the same `BGProcessingTask` schedule as RSS feeds — once daily. `RSSFetchService` routes `.newsletter` feeds through FeedKit's Atom parser. The feed format is standard Atom; no special handling needed.

Newsletter editions are stored as `RSSArticle` rows with `feedID` matching the newsletter's `RSSFeed`. Deduplication is by URL, same as RSS.

---

### Fetching the Reading Address Back

The user may want to retrieve their reading address after setup (e.g., to subscribe to a second newsletter list). `FeedDetailView` for a newsletter feed shows the address:

```
YOUR READING ADDRESS
abc123xyz@kill-the-newsletter.com   ⧉
```

Sourced from `feed.newsletterEmail`. Tappable to copy — same behaviour as setup.

---

## Relationship to `newsletter-import.md`

That backlog item covers two user-initiated import paths:

- **V1 (Share Extension):** User manually shares a newsletter email into Just…. One-time, manual.
- **V2 (IMAP):** Just… polls a mailbox with stored credentials. Automatic, but requires credential trust.

Newsletter Feeds is the automated, zero-credential path that sits between them. All three can coexist — they serve different comfort levels:

| Path | Setup friction | Ongoing effort | Privacy surface |
|---|---|---|---|
| Share Extension | None | Manual each edition | None |
| **Newsletter Feeds** | **One subscribe per newsletter** | **Zero** | **Reading address only** |
| IMAP | Credential setup | Zero | Keychain credentials |

Newsletter Feeds is the recommended starting point. The share extension catches anything the user doesn't want to formally subscribe.

---

## Brand Alignment

| Principle | Check |
|---|---|
| No backend (Just… side) | ✅ — Kill the Newsletter is the backend; Just… only makes one API call |
| All data on-device | ✅ — Atom feed polled directly from device; no Just… server |
| User controls what enters the queue | ✅ — Editions surface as reading items; user still chooses to queue |
| Not a read-later archive | ✅ — Same pruning as RSS; old editions don't accumulate |
| Calm onboarding | ✅ — Two screens, one field, one copy tap |
| No credentials stored | ✅ — Only the feed URL and email address stored in SwiftData |
| Privacy-first | ✅ — The reading address is a dead-drop; no real email involved |

One honest tradeoff: Kill the Newsletter is a third-party dependency maintained by a solo developer. If the service goes down, newsletter feeds stop updating. Migration path: self-host the open-source codebase on Cloudflare Workers + Email Routing (free tier) — the same Atom feed format is preserved, only the base URL changes.

---

## Copy Reference

| Moment | Copy |
|---|---|
| Sheet headline | "Follow a newsletter." |
| Sheet subhead | "You'll get a reading address. Subscribe to any newsletter with it. New editions appear here automatically." |
| Name field placeholder | "e.g. Dense Discovery" |
| Address screen label | "YOUR READING ADDRESS" |
| Address screen subhead | "Paste this into the subscription form for [Name]. New editions will appear in your queue automatically." |
| Before first edition | "Waiting for first edition." |
| After first edition | "Last edition [relative date]." |
| API error | "Couldn't create a reading address. Check your connection and try again." |
| Delete confirmation | "Remove [Name]? Future editions will stop arriving." |

---

## Acceptance Criteria

- [ ] Tapping + in FeedsView offers "Newsletter" as an option alongside RSS feed
- [ ] AddNewsletterSheet accepts a free-text name and calls `KillTheNewsletterService.createFeed(title:)`
- [ ] On success, reading address is displayed and copies to clipboard on tap — no toast, colour change only
- [ ] Reading address is stored in `RSSFeed.newsletterEmail` in SwiftData
- [ ] Feed URL is stored and polled on the same BGProcessingTask schedule as RSS feeds
- [ ] Newsletter editions appear as `RSSArticle` rows in SwiftData; deduplication by URL
- [ ] Newsletter cards in FeedsView show a small envelope glyph and correct subtitle copy
- [ ] `FeedDetailView` for newsletter feeds shows the reading address, copyable
- [ ] Swipe-to-delete or long-press removes the newsletter feed and all its episodes from SwiftData
- [ ] API error state shown with Retry — no technical detail exposed to user
- [ ] `FeedType.newsletter` added; existing feeds unaffected (default `.rss`)
- [ ] All colours use `AppTheme.Colors` tokens — no hardcoded hex
- [ ] No new tab or navigation destination introduced — newsletter lives inside existing Feeds tab
