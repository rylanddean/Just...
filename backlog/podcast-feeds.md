# Podcast Feeds

**Tier:** Free  
**Effort:** L  
**Status:** Backlog

Podcast RSS feeds are added alongside article feeds. When an episode includes a transcript link — which most modern podcasts do — Just… fetches it, strips the timing metadata, and uses Apple Intelligence to render it as a prose article. The user reads it like anything else, reflects, and keeps what stayed with them in the Brain. No audio playback. Ever. Just… is a reading app.

---

## The Problem

Podcasts are the most under-read medium. An episode of Huberman Lab or Lex Fridman contains hours of dense, genuinely valuable ideas — most of which disappear from the listener's memory within 48 hours. The Ebbinghaus argument that justifies the reflect window applies here too, maybe more so. Listening is even more passive than reading.

But Just… is not Overcast. The reading loop is the product. The problem this solves is not "I want to listen to podcasts in Just…." It is: "I subscribe to podcasts I never have time to listen to, and the ideas in them never reach my Brain."

The feature works because the listening medium is irrelevant to us — the transcript is text, and text is what Just… does.

---

## Why This Is Worth the Risk

This is a genuinely difficult call. Adding podcasts risks making Just… feel like something it explicitly is not.

The counterargument: Just… already supports RSS. Podcast feeds are RSS. The experience difference is entirely in how the content is delivered. If we can silently convert an episode to readable prose, the user never encounters a media type — they encounter an article. The cognitive model does not change.

The constraint that makes it work: this only functions when a transcript exists. If there is no transcript, the episode appears in the feed with a greyed state ("No transcript available") and a link to open in a podcast app. Just… never downloads audio. Never plays audio. The moment that constraint weakens, the feature drifts and should be cut.

---

## How Transcripts Actually Work

The idea that there is an "Apple API for podcast transcripts" is worth scrutinising before building anything.

Apple has no public transcript API. What exists instead is the Podcasting 2.0 `<podcast:transcript>` RSS tag — a namespace extension that points to a transcript file hosted by the podcast itself. Apple Podcasts, Overcast, and Pocket Casts all consume this tag. As of 2024, Apple Podcasts started rendering transcripts for all shows in its directory and strongly incentivises publishers to include the tag. Spotify has required it for all hosted shows since late 2023.

A majority of high-quality, intellectually dense podcasts — the kind a Just… user is likely to subscribe to — now include it.

| Format | Notes |
|--------|-------|
| `application/x-subrip` (SRT) | Timestamps + speaker labels. Parse and strip. |
| `text/vtt` (WebVTT) | Same. Most common format from Descript, Transistor, Buzzsprout. |
| `application/json` | Varies by provider. Whisper-based tools output structured JSON with words + timestamps. |
| `text/html` | Rare. Strip tags. |

The parse step is straightforward. The VTT/SRT timestamp lines and speaker cue lines are stripped, leaving clean plain text that reads poorly on its own (short fragments, half-sentences, filler words) — which is exactly what the Apple Intelligence rewrite step resolves.

There is no backend involved. The transcript file is fetched directly from the URL in the RSS item, parsed on-device, and fed into Apple Intelligence locally. This fits the existing architecture perfectly.

---

## The Rewrite Step

The raw stripped transcript is not an article. It is a noisy, first-person, verbal transcript of a conversation. Filler words, crosstalk, false starts, "um" and "you know" — all of this degrades the reading experience.

Apple Intelligence (`FoundationModels`) rewrites it as prose using a constrained prompt:

> Rewrite this podcast transcript as a concise, readable article in the third person. Preserve the key ideas, examples, and arguments. Remove filler words, redundant exchanges, and tangents. Target 800–1200 words. Do not invent claims not present in the transcript.

The output is stored in a new `generatedContent: String?` field on `QueuedLink`. The reader displays `generatedContent` if present; otherwise falls back to the original fetched body text (for non-podcast items, this field is always nil).

The quality ceiling here is real. Apple Intelligence's prose is serviceable but not elegant. A 3-hour interview will compress to 1000 words and lose nuance. This is a known tradeoff. The feature is positioned as "the ideas from this conversation, readable" — not "a perfect transcription" or "an article the host wrote." The attribution badge enforces this.

---

## Feeds View

### Feed Type Detection

When the user taps `+` and pastes a URL, the app needs to know whether they are adding an article feed or a podcast feed — without asking them. The current `resolveTitle` function already fetches the feed to extract `<title>`. That same fetch is extended to detect type.

Detection reads the first 8KB of the response (up from 2048 bytes — still a single request, no extra network call) and looks for these signals in order of reliability:

| Signal | Reliability |
|--------|-------------|
| `xmlns:itunes` namespace declared in `<rss>` element | Very high — all iTunes-spec podcasts |
| `<itunes:type>episodic` or `<itunes:type>serial` | High — explicit declaration |
| `<enclosure type="audio/` | High — direct evidence of audio items |
| `xmlns:podcast` | High — Podcasting 2.0 namespace |
| `<itunes:author>` or `<itunes:summary>` | Medium — common in podcast feeds |

One signal is enough to classify as podcast. The detection function is pure and fast — no FeedKit dependency, just string scanning on the prefix.

```swift
static func detectFeedType(from prefix: String) -> FeedType {
    let lower = prefix.lowercased()
    if lower.contains("xmlns:itunes") ||
       lower.contains("xmlns:podcast") ||
       lower.contains("<enclosure type=\"audio/") ||
       lower.contains("<itunes:type>") {
        return .podcast
    }
    return .article
}
```

`FeedType` is a new `String`-backed enum stored on `RSSFeed`. SwiftData handles the lightweight migration automatically (new property, default value):

```swift
enum FeedType: String, Codable {
    case article
    case podcast
}

// On RSSFeed:
var feedType: FeedType = .article
```

The user never sees a type picker. The form label stays "Add Feed." The detected type is passed through `subscribe(url:title:category:feedType:)` and stored. If detection is ambiguous, it defaults to `.article` — the safer fallback.

### Browse Directory

Podcasts also appear in the existing `FeedDirectoryView`, integrated into the same topic-based category taxonomy as article feeds. A user browsing "Science" sees science article feeds and science podcast feeds side by side. A user browsing "Technology" sees both. No new top-level "Podcasts" category is added — media type is not a topic, and filing shows separately would make the directory less useful, not more.

The `FeedDirectoryItem` schema gains an optional `feedType` field. Existing entries default gracefully with no migration or data change needed:

```swift
struct FeedDirectoryItem: Codable, Identifiable, Sendable {
    var id: String { url }
    let name: String
    let url: String
    let category: String
    let description: String
    let feedType: FeedType?   // nil → treated as .article; explicit for podcast entries
}
```

`DirectoryRow` conditionally renders the same `waveform` SF Symbol at 13pt in `appTheme.textFaint` before the show name — identical treatment to `FeedRow` — so podcasts are immediately identifiable in browse results without any extra UI. When the user subscribes from the directory, `feedType` is passed through to `subscribe(url:title:category:feedType:)` and stored on `RSSFeed`.

**Curation.** The directory is bundled in `feeds.json` — no runtime API, no backend. Podcast entries are added to the same file manually. The source for RSS URLs is the [Podcast Index](https://podcastindex.org), an open database that underpins Apple Podcasts, Overcast, and Pocket Casts.

One rule before any podcast entry is added to the directory: verify the show's feed includes `<podcast:transcript>` tags on recent episodes. A show listed in the directory without transcript support will produce only "No transcript." episode cards — a confusing first impression for a feature that depends on transcripts. Every entry must be tested before inclusion.

A starting set of 20–30 shows across the existing categories — dense, interview-driven podcasts from publishers known to include transcripts (Huberman Lab, Lex Fridman Podcast, The Knowledge Project, Ezra Klein Show, Hardcore History, We Study Billionaires, etc.) — is enough for launch. Volume is not the goal. Each podcast entry should be something a Just… user would actually sit with.

### FeedRow Visual Differentiation

Podcast feeds and article feeds live in the same list — no section headers, no separate tabs. The sort order stays alphabetical. The only visual difference is a `waveform` SF Symbol at 13pt in `appTheme.textFaint` to the left of the title on podcast rows.

This is intentionally minimal. A single icon is enough to let a user scan the list and know what kind of content each feed delivers. Labelling it with a "PODCAST" pill would be redundant with the icon and adds clutter.

```
┌─────────────────────────────────────────┐
│  ≋  The Knowledge Project          ●  3  │  ← podcast
│     Self Improvement · 2 hours ago       │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Stratechery                       ●  1  │  ← article (no icon)
│     Technology · 1 hour ago             │
└─────────────────────────────────────────┘
```

The `waveform` glyph sits at 13pt, rendered in `appTheme.textFaint` — not accent. It marks the type without competing with the article count badge, which is the more important piece of data on the row. On paused podcast feeds, the glyph renders at the same reduced opacity as the title.

Implementation: `FeedRow` reads `feed.feedType` and conditionally prepends the icon to the title `HStack`:

```swift
HStack(spacing: 6) {
    if feed.feedType == .podcast {
        Image(systemName: "waveform")
            .font(.system(size: 13))
            .foregroundStyle(feed.isPaused ? appTheme.textFaint.opacity(0.4) : appTheme.textFaint)
    }
    Text(feed.title)
        .font(AppTheme.sansSerif(15, weight: .medium))
        .foregroundStyle(feed.isPaused ? appTheme.textFaint : appTheme.heading)
        .lineLimit(1)
    // ... PAUSED badge
}
```

### Queue Card

Podcast episode cards carry a small `EPISODE` badge in the top-right corner, replacing the domain label. It follows the same pattern as the existing `PAUSED` badge: DM Mono, all-caps, `appTheme.textFaint` foreground on `appTheme.surface` background, `Capsule` clip shape. The rest of the card is identical to an article card.

Episodes where the transcript is being fetched and rewritten show a brief loading state: the card is present but the title fades slightly with a shimmer tinted `appTheme.accentFaint`. Tapping it while generating blocks with a quiet "Still thinking." state — no spinner, just that line in `.mono` style.

Episodes where no transcript tag exists display the card in a muted state (title at `.muted` colour) with a secondary label: "No transcript." Tapping opens an action sheet: "Open in Podcasts" or "Remove from queue."

### Reader Attribution

At the very top of the generated article, before the first paragraph, a single line:

```
GENERATED FROM EPISODE — [Show Name]
```

DM Mono, all-caps, `appTheme.textFaint` colour. This does not disappear on scroll. It is not dismissible. The user must always know they are reading an AI rendering of a conversation, not the author's original prose.

No summary card, no "AI wrote this" modal. One line. Clear and present, never intrusive.

---

## What Could Go Wrong

**Quality variance is high.** An interview podcast with two people, clear sentences, and good mic discipline will generate a solid article. A loosely structured roundtable or a show with heavy banter will produce something harder to read. This is unavoidable given the input quality variance. The mitigation is: users curate their own feeds — they choose to add a podcast they already know and respect.

**Long episodes hit Apple Intelligence token limits.** A 3-hour Joe Rogan transcript could be 80,000 words. Foundation Models cannot process that in one shot. The approach: chunk the transcript into ~4000-token segments, summarise each chunk, then run a second-pass synthesis pass across the summaries. Two-pass generation is slower (potentially 20–40 seconds on older supported hardware) and must be clearly communicated: the shimmer loading state stays for the full generation duration.

**Transcript lag.** Many podcasts publish the transcript 24–48 hours after the episode drops. If the user's RSS refresh catches the episode before the transcript is available, it will initially appear as "No transcript." A periodic re-check (once every 6 hours for the 48 hours after first seen) should resolve this silently — the card upgrades from muted to available without user action.

**Scope creep.** The second this feature ships, someone will ask for playback. The backlog answer should always be no. Just… is not a podcast app. If that answer becomes hard to defend, the podcast feed feature has drifted from its intent.

---

## Technical Approach

```
RSSFeed (model)
  └─ var feedType: FeedType = .article   // new stored property

FeedType (enum, String-backed Codable)
  └─ .article | .podcast

FeedsView / addFromURL()
  └─ fetches 8KB prefix (up from 2KB) for title + type detection in one request
  └─ detectFeedType(from:) → FeedType
  └─ subscribe(url:title:category:feedType:) stores type on RSSFeed

FeedDirectoryItem
  └─ var feedType: FeedType?   // new optional field; nil = .article

FeedDirectoryView / onSubscribe callback
  └─ passes item.feedType ?? .article through subscribe(url:title:category:feedType:)

DirectoryRow
  └─ reads item.feedType; conditionally renders waveform icon before name (same as FeedRow)

FeedRow
  └─ reads feed.feedType; conditionally renders waveform icon before title

RSSFetchActor / extract(feed:)
  └─ detects audio enclosures → skips item or flags as episode (FeedType.podcast)
  └─ parses <podcast:transcript> URL + format per item

PodcastTranscriptService  (new)
  └─ fetch(url: URL, format: TranscriptFormat) async -> String
  └─ strip(rawTranscript: String) -> String   // removes timestamps, cue lines

IntelligenceService
  └─ generateArticle(from transcript: String, episodeTitle: String, showName: String) async throws -> String
  └─ two-pass for transcripts > 12,000 words

QueuedLink
  └─ var generatedContent: String?   // nil for all non-podcast items
  └─ var transcriptState: TranscriptState   // .unavailable | .generating | .ready
```

Generation is triggered when the episode enters the queue, not on first tap. By the time the user opens it, the article should be ready. If generation is still running when they tap, the shimmer state holds.

Requires iOS 26+ / Apple Intelligence devices. Podcast feeds can be added on any device; the article generation step simply does not run on unsupported hardware, leaving the episode in a permanent "No transcript." muted state. This is an honest degradation — the feature requires the hardware.

---

## Brand Alignment Check

| Principle | Assessment |
|-----------|------------|
| No backend | ✅ Transcript fetch is direct URL; generation is on-device |
| Offline-first | ⚠️ Transcript fetch requires network; generated article is cached locally after |
| All data on-device | ✅ Generated article stored in SwiftData |
| Reading discipline, not consumption | ✅ No audio, no playback, no episode count stats |
| Honest about AI | ✅ Attribution line is permanent and non-dismissible |
| One-thing focus | ⚠️ Podcast feeds are additive — risk of queue flooding if the user adds high-volume shows |
| Not a read-later archive | ⚠️ Same risk as RSS generally — mitigated by Brain limit (free tier) and the daily habit framing |
| Calm, no hype | ✅ The loading state is "Still thinking." — unhurried |
| Theme compliance | ✅ All colours via `@Environment(\.appTheme)` tokens — no hardcoded hex values. Works correctly across all six `ReaderTheme` variants (Ember, Slate, Dusk, Sage, Sepia, Paper) |

The biggest risk is not technical. It is that podcast feeds make the queue feel like a media inbox. The mitigation is the same as for RSS feeds generally: the Brain entry limit on the free tier creates natural friction. A user who subscribes to 5 high-volume podcast feeds and never reflects will fill their Brain and have to confront what the app actually is.

---

## Acceptance Criteria

### Feeds View
- [ ] `RSSFeed.feedType` persisted in SwiftData with default `.article`; existing feeds unaffected by migration
- [ ] Podcast feed rows display a `waveform` SF Symbol at 13pt in `textFaint` before the title
- [ ] Article feed rows display no type icon
- [ ] On paused podcast feeds, the waveform icon renders at the same reduced opacity as the title
- [ ] Feed list remains a single alphabetically-sorted list — no section headers, no separate tab
- [ ] `FeedRow` PAUSED badge behaviour is unchanged for both feed types

### Add Feed Form
- [ ] Tapping `+` shows the same "Add Feed" form regardless of feed type — no type picker, no type question
- [ ] URL fetch reads 8KB prefix (single request; same request used for title resolution)
- [ ] `detectFeedType(from:)` classifies as `.podcast` on any of: `xmlns:itunes`, `xmlns:podcast`, `<enclosure type="audio/`, `<itunes:type>`
- [ ] Ambiguous or undetected feeds default to `.article`
- [ ] Detected `feedType` stored on `RSSFeed` at subscribe time
- [ ] Feed row appears immediately after subscribing with the correct type icon (no refresh required)

### Browse Directory
- [ ] `FeedDirectoryItem` decodes optional `feedType` field; existing entries without it default to `.article`
- [ ] Podcast entries in `feeds.json` carry `"feedType": "podcast"`
- [ ] `DirectoryRow` renders the `waveform` icon at 13pt `appTheme.textFaint` before the show name when `feedType == .podcast`
- [ ] Subscribing from the directory passes `feedType` through to `RSSFeed`; subscribed row in FeedsView immediately shows the correct icon
- [ ] Podcast entries are distributed across existing topic categories — no new "Podcasts" category added
- [ ] All directory podcast entries verified to have `<podcast:transcript>` on recent episodes before inclusion in `feeds.json`
- [ ] Directory search works for podcast entries (name and description match) using the existing `searchable` modifier

### Transcript & Article Generation
- [ ] `<podcast:transcript>` tag parsed per episode; URL and format extracted
- [ ] Transcript fetched and stripped on-device; no transcript content sent to any external server
- [ ] Apple Intelligence rewrites transcript as prose article; stored in `QueuedLink.generatedContent`
- [ ] Two-pass generation used when transcript exceeds 12,000 words
- [ ] `GENERATED FROM EPISODE — [Show Name]` attribution line appears at top of reader; persists on scroll; is not dismissible
- [ ] Episode cards carry `EPISODE` badge matching the existing `PAUSED` badge pattern: `appTheme.textFaint` on `appTheme.surface`, DM Mono, all-caps
- [ ] Cards with no transcript appear muted with "No transcript." label
- [ ] Tapping a no-transcript card offers "Open in Podcasts" or "Remove from queue"
- [ ] Loading state shows amber shimmer with no spinner; "Still thinking." text on tap during generation
- [ ] Re-check for transcript runs every 6 hours for 48 hours after episode first seen without one
- [ ] No audio is ever downloaded, buffered, or played
- [ ] Feature absent (generation step skipped, episode always muted) on non-Apple Intelligence devices
- [ ] Existing article feeds are entirely unaffected
