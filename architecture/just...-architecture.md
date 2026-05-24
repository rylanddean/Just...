# Just… — Application Architecture

**Version:** 1.1  
**Author:** Ryland Dean  
**Target:** iOS 17+, SwiftUI, SwiftData — Apple Intelligence features require iOS 26+ / Apple Intelligence-capable hardware

---

## Overview

Just… is a single-target iOS application with a Share Sheet extension. The architecture is deliberately lean — no backend, no accounts, no sync in V1. All data lives on-device in SwiftData. The design philosophy mirrors the product: remove everything that isn't essential.

---

## Guiding Principles

- **No unnecessary state.** Services are pure static structs. Views own only the state they render.
- **SwiftData over CoreData.** Simpler model definitions, native `@Query` integration, less ceremony.
- **`@Observable` over `ObservableObject`.** No `@Published` boilerplate, no Combine dependency.
- **One direction of data flow.** Views read from SwiftData via `@Query`. Services mutate the store. Views never talk to services directly — they go through ViewModels where logic is needed.
- **Offline-first, always.** No network dependency for core reading or reflection. Content is fetched once and cached.
- **Testable by design.** Services have no side effects and no dependencies on UIKit or SwiftUI. They can be unit tested in isolation.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────┐
│                   JustEllipsis App               │
│                                                  │
│  ┌─────────────┐   ┌─────────────────────────┐  │
│  │    Views    │◄──│      SwiftData Store     │  │
│  │  (SwiftUI)  │   │  QueuedLink             │  │
│  └──────┬──────┘   │  BrainEntry             │  │
│         │          │  ReadingDay             │  │
│  ┌──────▼──────┐   └────────────▲────────────┘  │
│  │  ViewModels │                │               │
│  │ (@Observable)│               │               │
│  └──────┬──────┘   ┌────────────┴────────────┐  │
│         │          │        Services          │  │
│         └─────────►│  StreakEngine           │  │
│                    │  BrainEngine            │  │
│                    │  ContentFetcher         │  │
│                    │  VoiceRecognizer        │  │
│                    │  IntelligenceService    │  │
│                    └────────────▲────────────┘  │
│                                 │               │
│                    ┌────────────┴────────────┐  │
│                    │   Foundation Models      │  │
│                    │   (SystemLanguageModel)  │  │
│                    │   On-device · Private    │  │
│                    │   Offline · Free         │  │
│                    └─────────────────────────┘  │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│              Share Sheet Extension               │
│  AddLinkIntent → writes QueuedLink to shared     │
│  App Group container                            │
└─────────────────────────────────────────────────┘
```

---

## Project Structure

```
JustEllipsis/
├── App/
│   ├── JustEllipsisApp.swift        # Entry point, ModelContainer setup
│   └── AppTheme.swift               # Colour tokens, typography scale
│
├── Models/
│   ├── QueuedLink.swift             # @Model — link queue entries
│   ├── BrainEntry.swift             # @Model — completed reads + reflections
│   └── ReadingDay.swift             # @Model — logical reading days (streak)
│
├── Views/
│   ├── HomeView.swift               # Root tab: streak header + link queue
│   ├── ReaderView.swift             # Stripped reading experience
│   ├── ReflectView.swift            # 60s countdown + type/voice input
│   ├── BrainView.swift              # Brain entry list + rank display
│   └── AddLinkView.swift            # Bottom sheet: paste or share URL
│
├── ViewModels/
│   ├── ReaderViewModel.swift        # Content fetch, read state, cache
│   ├── ReflectViewModel.swift       # Countdown timer, input state, save
│   └── BrainViewModel.swift        # Rank calculation, entry filtering
│
├── Components/
│   ├── LinkCard.swift               # Queue row: title, domain, sort handle
│   ├── StreakHeader.swift           # Streak count + danger state display
│   ├── BrainOrb.swift              # Animated rank orb visual
│   ├── CountdownRing.swift          # Circular timer for reflect window
│   ├── ReaderWebView.swift          # WKWebView wrapper (UIViewRepresentable)
│   └── VoiceInputButton.swift       # Mic toggle, waveform indicator
│
├── Services/
│   ├── StreakEngine.swift           # Pure static: streak calc, logical day
│   ├── BrainEngine.swift           # Pure static: rank, size, next threshold
│   ├── ContentFetcher.swift         # Fetch HTML, strip, cache
│   ├── VoiceRecognizer.swift        # SFSpeechRecognizer wrapper
│   └── IntelligenceService.swift    # Foundation Models: summary, prompt, digest
│
└── Extensions/
    ├── ShareExtension/
    │   ├── ShareViewController.swift
    │   └── AddLinkIntent.swift      # Writes to App Group store
    └── WidgetExtension/ (V1.1)
        └── JustWidget.swift
```

---

## Data Layer

### SwiftData Models

#### `QueuedLink`

Represents a link in the reading queue. Ordered by `sortOrder` for manual reordering.

```swift
@Model
final class QueuedLink {
    var id: UUID = UUID()
    var url: String
    var title: String?           // fetched on add via OpenGraph/title tag
    var domain: String?          // e.g. "nytimes.com", extracted from URL
    var addedAt: Date = Date()
    var sortOrder: Int           // ascending — lower reads first
    var isRead: Bool = false
    var cachedHTML: String?      // stripped HTML, stored after first fetch
}
```

#### `BrainEntry`

A completed read with optional reflection. Created when the user saves or skips the reflect window.

```swift
@Model
final class BrainEntry {
    var id: UUID = UUID()
    var url: String
    var title: String
    var domain: String
    var readAt: Date = Date()
    var reflection: String?      // nil if skipped
    var reflectionMode: String?  // "typed" | "voice" | nil
    var reflectionSeconds: Int   // seconds spent in reflect window
    var wordCount: Int           // estimated from stripped body text
    var aiSummary: String?       // on-device summary, nil if unavailable
}
```

#### `ReadingDay`

One record per logical reading day. Created on first completed read of the day. Powers the streak.

```swift
@Model
final class ReadingDay {
    var id: UUID = UUID()
    var year: Int
    var month: Int
    var day: Int                 // logical day — 3AM grace window applied
    var linksRead: Int = 0
}
```

### ModelContainer Setup

```swift
// JustEllipsisApp.swift
@main
struct JustEllipsisApp: App {
    let container: ModelContainer = {
        let schema = Schema([QueuedLink.self, BrainEntry.self, ReadingDay.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
    }
}
```

---

## Services Layer

All services are pure static structs with no stored state. They receive inputs and return outputs. No UIKit, no SwiftUI, no side effects. Fully unit testable.

### `StreakEngine`

Calculates streak from `ReadingDay` records. Shared pattern with Just Reps.

```swift
struct StreakEngine {

    // Convert a real Date to the logical reading day.
    // Dates between midnight and 3AM belong to the previous calendar day.
    static func logicalDay(for date: Date = Date()) -> (year: Int, month: Int, day: Int)

    // Calculate current and longest streak from the set of reading days.
    static func calculateStreak(from days: [ReadingDay]) -> (current: Int, longest: Int)

    // True if today's logical day has a ReadingDay entry with linksRead > 0.
    static func hasReadToday(days: [ReadingDay]) -> Bool

    // True if yesterday's logical day has no ReadingDay entry.
    static func isStreakAtRisk(days: [ReadingDay]) -> Bool
}
```

**3AM grace window:** A user reading at 1AM on Tuesday is still "reading Monday." This prevents streak breaks for late-night reading sessions.

---

### `BrainEngine`

Calculates Brain rank and progress from `BrainEntry` count.

```swift
struct BrainEngine {

    static func rank(for entryCount: Int) -> BrainRank

    static func nextRankThreshold(for entryCount: Int) -> Int

    static func entriesUntilNextRank(for entryCount: Int) -> Int

    static func progressToNextRank(for entryCount: Int) -> Double  // 0.0–1.0
}

enum BrainRank: String, CaseIterable {
    case curious   = "Curious"    // 0–25
    case reader    = "Reader"     // 26–100
    case thinker   = "Thinker"    // 101–300
    case scholar   = "Scholar"    // 301–750
    case polymath  = "Polymath"   // 751–2000
    case luminary  = "Luminary"   // 2001+

    var threshold: Int {
        switch self {
        case .curious:  return 0
        case .reader:   return 26
        case .thinker:  return 101
        case .scholar:  return 301
        case .polymath: return 751
        case .luminary: return 2001
        }
    }
}
```

---

### `ContentFetcher`

Fetches a URL's raw HTML, strips it to readable text, and returns a `StrippedContent` value type. Results are cached in `QueuedLink.cachedHTML` so content is only fetched once.

```swift
struct StrippedContent {
    let title: String
    let body: String             // cleaned HTML for WKWebView injection
    let domain: String
    let estimatedWordCount: Int
    let estimatedReadingMinutes: Int
}

struct ContentFetcher {

    // Fetch and strip. Returns cached content if available.
    static func fetch(for link: QueuedLink) async throws -> StrippedContent

    // Strip raw HTML using SwiftSoup.
    static func strip(html: String, sourceURL: URL) throws -> StrippedContent

    // Extract domain from URL. e.g. "www.nytimes.com" → "nytimes.com"
    static func extractDomain(from url: URL) -> String
}
```

**Strip selectors removed:** `img`, `video`, `figure`, `picture`, `iframe`, `nav`, `header`, `footer`, `aside`, `script`, `style`, `[class*=ad]`, `[class*=banner]`, `[class*=social]`, `[class*=comment]`, `[class*=related]`

**Content extraction strategy:** Parse all `<p>` tags. Find the ancestor element containing the highest density of paragraph text. Use that subtree as the article body. This handles most article layouts including those without explicit `<article>` tags.

**Reader CSS injected into WKWebView:**

```css
:root {
  --bg: #0C0A08;
  --text: #C8B898;
  --accent: #E8A83E;
}

body {
  background: var(--bg);
  color: var(--text);
  font-family: 'Georgia', serif;
  font-size: 20px;
  line-height: 1.85;
  max-width: 680px;
  margin: 0 auto;
  padding: 32px 24px 80px;
}

h1, h2, h3 { color: #F5ECD7; }
a { color: var(--accent); text-decoration: none; }
blockquote { border-left: 2px solid var(--accent); padding-left: 20px; opacity: 0.8; }
```

---

### `VoiceRecognizer`

Wraps `SFSpeechRecognizer` and `AVAudioEngine` for live transcription during the reflect window. On-device recognition only — no audio is ever sent to Apple's servers.

```swift
@Observable
final class VoiceRecognizer {
    var transcript: String = ""
    var isListening: Bool = false
    var isAvailable: Bool = false   // false on pre-A12 devices or if permission denied

    // Call on app launch to determine whether to show mic button at all.
    // Sets isAvailable = false permanently on unsupported hardware.
    static func deviceSupportsOnDeviceRecognition() -> Bool

    func requestPermission() async -> Bool
    func startListening() throws    // uses requiresOnDeviceRecognition = true
    func stopListening()
    func reset()
}
```

**Permission flow:** `SFSpeechRecognizer` requires both Speech Recognition and Microphone permissions. Requested lazily — only when the user taps the mic button for the first time. If denied, the mic button is hidden; the typed path remains fully functional.

**On-device only:** Just… performs no server-side operations of any kind. Voice transcription uses on-device recognition exclusively (`SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`). Devices that do not support on-device recognition (pre-A12 chip) do not show the mic button. The typed path is always available regardless of device capability.

**Locale:** Defaults to `Locale.current`. No language selection in V1.

---

## View Layer

### Navigation Structure

Just… uses a simple two-tab structure. No deep navigation stacks.

```
TabView
├── Tab 1: Home (queue icon)
│   ├── HomeView
│   │   ├── StreakHeader
│   │   └── LinkQueue (list of LinkCards)
│   │       └── [tap] → ReaderView (full screen cover)
│   │           └── [finish] → ReflectView (full screen cover)
│   └── [+] → AddLinkView (bottom sheet)
│
└── Tab 2: Brain (brain/orb icon)
    └── BrainView
        ├── BrainOrb (rank + size)
        └── BrainEntryList (entries, reverse chronological)
```

### `HomeView`

Root view. Owns the link queue display and streak header.

```swift
struct HomeView: View {
    @Query(sort: \QueuedLink.sortOrder) var queue: [QueuedLink]
    @Query var readingDays: [ReadingDay]
    @State private var showAddLink = false
    @State private var activeLink: QueuedLink?

    // streak derived from readingDays via StreakEngine
    // activeLink drives fullScreenCover to ReaderView
}
```

### `ReaderView`

Full-screen cover presented over HomeView. Contains `ReaderWebView` (WKWebView wrapper) and a thin progress indicator. Minimal chrome — domain label and estimated read time only. Navigation bar hidden during reading.

```swift
struct ReaderView: View {
    let link: QueuedLink
    @StateObject private var viewModel: ReaderViewModel
    @State private var showReflect = false

    // On appear: viewModel fetches/loads content
    // "Done reading" button → sets showReflect = true
    // fullScreenCover → ReflectView
}
```

### `ReflectView`

The most important screen. Full-screen cover presented from ReaderView on completion.

```swift
struct ReflectView: View {
    let entry: BrainEntry        // pre-created with article metadata
    @StateObject private var viewModel: ReflectViewModel
    @StateObject private var voiceRecognizer: VoiceRecognizer

    // CountdownRing animates from 60 → 0
    // Timer pauses when viewModel.isTyping || voiceRecognizer.isListening
    // VoiceInputButton toggles mic, feeds transcript into text field
    // Skip button: muted, bottom-right, always visible
    // On save or timeout: viewModel.save(entry) → dismiss both covers
}
```

### `BrainView`

Displays Brain size, rank, progress to next rank, and all entries in reverse chronological order.

```swift
struct BrainView: View {
    @Query(sort: \BrainEntry.readAt, order: .reverse) var entries: [BrainEntry]

    // BrainOrb shows rank + animated size
    // Entry list: title, domain, date, reflection preview (if any)
    // Search available in V1.1
}
```

---

## ViewModels

### `ReaderViewModel`

```swift
@Observable
final class ReaderViewModel {
    var content: StrippedContent?
    var isLoading: Bool = false
    var error: Error?
    var readProgress: Double = 0.0   // 0.0–1.0, driven by WKWebView scroll

    func load(link: QueuedLink, context: ModelContext) async
    func markAsRead(link: QueuedLink, context: ModelContext)
}
```

### `ReflectViewModel`

```swift
@Observable
final class ReflectViewModel {
    var text: String = ""
    var secondsRemaining: Int = 60
    var isTyping: Bool = false
    var isSaved: Bool = false

    func startCountdown()
    func pauseCountdown()
    func resumeCountdown()
    func save(entry: BrainEntry, mode: ReflectionMode, context: ModelContext)
    func skip(entry: BrainEntry, context: ModelContext)
}

enum ReflectionMode: String {
    case typed = "typed"
    case voice = "voice"
}
```

---

## Share Sheet Extension

The primary path for adding links. Users share a URL from Safari (or any app) directly into the Just… queue.

```
Share Sheet Extension
├── ShareViewController.swift     # UI-less extension, reads shared URL
├── AddLinkIntent.swift           # Writes QueuedLink to App Group container
└── Info.plist                    # NSExtensionActivationRule: public.url
```

**App Group:** Both the main app and the extension share a SwiftData store via an App Group container identifier (`group.com.rylandean.justellipsis`). The extension writes a new `QueuedLink`; the main app reads it on next launch or foreground.

**Metadata prefetch:** On add, the extension fetches the page title and domain in the background before the user opens the app, so the queue always shows human-readable titles immediately.

---

## Content Caching Strategy

| Content | Storage | TTL |
|---------|---------|-----|
| Stripped HTML body | `QueuedLink.cachedHTML` (SwiftData) | Permanent until link is removed |
| Page title + domain | `QueuedLink.title`, `.domain` | Permanent |
| Reader CSS | Bundled in app | App version |
| WKWebView process pool | Shared singleton | App session |

No external cache layer. No `NSCache`. Content is stored directly on the model so it survives app restarts and works fully offline.

---

## Streak Engine — Logic Detail

```
Logical day calculation:
  given: Date()
  if hour < 3:
    subtract 1 calendar day
  return (year, month, day) of adjusted date

Streak calculation:
  sort ReadingDay records descending by date
  if today has no entry → current streak = 0 (or 1 if yesterday exists — grace)
  walk backwards from most recent day:
    if consecutive days exist → increment streak
    if gap found → stop
  longest streak = max run found across all records
```

**Streak at risk:** Evaluated after 8PM local time. If today's logical day has no `ReadingDay` entry, a notification is scheduled (if permitted). The notification fires at 9PM: "Your streak is at risk. Still time."

---

## Notification Strategy

Just… uses a single, opt-in notification. No onboarding push permission prompt — permission is requested the first time the user's streak reaches 3 days, with an explanation.

| Trigger | Time | Copy |
|---------|------|------|
| No reading today, streak ≥ 1 | 9PM local | "Your streak is at risk. Still time." |
| Streak lost | Next morning 8AM | "Your streak ended. Start again." |
| Brain rank up | Immediate | "Your Brain is now a [Rank]." |

All notifications are local (`UNUserNotificationCenter`). No push infrastructure in V1.

---

## Premium Unlock

Premium is a one-time StoreKit 2 purchase. No server-side receipt validation in V1 — StoreKit 2's `Transaction.currentEntitlements` is queried on app launch.

```swift
enum PremiumFeature: CaseIterable {
    case unlimitedBrain     // Brain capped at 50 free
    case brainSearch        // Full-text search of Brain entries
    case brainExport        // Export to Markdown
    case readerThemes       // Sepia, high contrast
    case homeWidget         // WidgetKit (V1.1)
}

struct PremiumStore {
    static func isPremium() async -> Bool
    static func purchase() async throws
    static func restore() async throws
}
```

**Free tier Brain cap:** When `BrainEntry` count reaches 50, the reflect window still appears after reading, but saving is gated behind a premium prompt. The article is still logged (without reflection) so the streak is maintained. The Brain does not silently stop working — the user is told clearly and given the option to unlock.

---

## V1.1 — Widget Extension

A WidgetKit extension surfacing streak count and Brain rank on the home screen. Small and medium sizes only.

```swift
struct JustWidget: Widget {
    // Small: streak count + amber flame icon
    // Medium: streak + Brain rank title + entries count
}
```

Widget reads from the shared App Group SwiftData store — no IPC, no network.

---

## Apple Intelligence

Just… uses the Foundation Models framework (iOS 26+) for four on-device, offline, zero-cost AI features. All are gated behind an availability check — the app degrades gracefully on devices without Apple Intelligence support.

### Availability Gate

Every AI feature checks `SystemLanguageModel.default.availability` before running. On unsupported devices, the fallback experience is clearly defined and fully functional.

```swift
import FoundationModels

struct IntelligenceService {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
}
```

---

### 1. Article Summary — "In Brief"

**When:** After content is fetched and stripped, before the reader is presented.  
**Where:** Displayed as a quiet 2–3 sentence block at the top of `ReaderView`, labelled "In brief".  
**Fallback:** Block is simply absent. No placeholder, no error.

The summary gives the reader context before they begin, which research shows improves comprehension. It is generated once and cached in `BrainEntry.aiSummary` so it is never regenerated.

```swift
extension IntelligenceService {

    static func summarize(_ body: String) async throws -> String {
        let session = LanguageModelSession()
        let prompt = """
        Summarize this article in 2–3 calm, direct sentences.
        No bullet points. No preamble. No "This article..." opener.
        Just the key idea.

        Article:
        \(body.prefix(4000))
        """
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
```

**Privacy note:** The article body is passed to the on-device model only. Nothing leaves the device.

---

### 2. Contextual Reflect Prompt

**When:** Reflect window opens, before the user starts typing or speaking.  
**Where:** Displayed as the placeholder prompt in `ReflectView`.  
**Fallback:** One of the static rotating prompts ("What stayed with you?", "One thought.", etc.)

Instead of a generic prompt, the model generates a single question specific to the article just read. The prompt disappears the moment the user starts typing or speaking — it is never intrusive.

```swift
@Generable
struct ReflectPrompt {
    @Guide(description: """
        One short, open question about this specific article.
        Under 10 words. Calm tone. No question marks at the end.
        Examples: "What would you do differently", "Does this change how you think about focus"
        """)
    var question: String
}

extension IntelligenceService {

    static func reflectPrompt(for summary: String) async throws -> String {
        let session = LanguageModelSession()
        let prompt = """
        Given this article summary, write one short reflection prompt.
        Follow the @Guide instructions exactly.

        Summary: \(summary)
        """
        let result = try await session.respond(
            to: prompt,
            generating: ReflectPrompt.self
        )
        return result.question
    }
}
```

---

### 3. Brain Search — Semantic Query (V1.1 Premium)

**When:** User types a query in `BrainView` search.  
**Where:** Replaces the V1 keyword-only search.  
**Fallback:** Standard string matching on title, domain, and reflection text.

Natural language search against Brain entries. The model classifies the query intent and scores entries by relevance — so "things I read about attention" surfaces articles even when the word "attention" doesn't appear in the reflection.

```swift
@Generable
struct SearchScore {
    @Guide(description: "Relevance score from 0–10. 10 = highly relevant.")
    var score: Int

    @Guide(description: "One-sentence reason for the score.")
    var reason: String
}

extension IntelligenceService {

    static func rankEntries(
        _ entries: [BrainEntry],
        for query: String
    ) async throws -> [BrainEntry] {
        let session = LanguageModelSession()
        var scored: [(entry: BrainEntry, score: Int)] = []

        for entry in entries {
            let context = [entry.title, entry.domain, entry.reflection ?? ""]
                .compactMap { $0 }
                .joined(separator: " · ")

            let prompt = """
            Query: "\(query)"
            Entry: "\(context)"
            Score the relevance of this Brain entry to the query.
            """
            let result = try await session.respond(
                to: prompt,
                generating: SearchScore.self
            )
            scored.append((entry, result.score))
        }

        return scored
            .sorted { $0.score > $1.score }
            .filter { $0.score >= 4 }
            .map { $0.entry }
    }
}
```

---

### 4. Weekly Brain Digest (V1.1 Premium)

**When:** Once per week, triggered by a local notification background task.  
**Where:** Delivered as a local notification; full digest readable in `BrainView`.  
**Fallback:** Feature simply absent on non-Apple Intelligence devices.

The last 7 Brain entries are passed to the model, which produces a short digest: recurring themes, a standout idea, and a single line about how the Brain grew that week. Entirely on-device, entirely private.

```swift
@Generable
struct WeeklyDigest {
    @Guide(description: """
        2–3 sentences. Themes from this week's reading.
        Calm, unhurried tone. No exclamation points.
        """)
    var summary: String

    @Guide(description: "One idea worth revisiting. Under 15 words.")
    var revisit: String
}

extension IntelligenceService {

    static func weeklyDigest(from entries: [BrainEntry]) async throws -> WeeklyDigest {
        let session = LanguageModelSession()

        let entrySummaries = entries.map { entry in
            "— \(entry.title): \(entry.reflection ?? "(no reflection)")"
        }.joined(separator: "\n")

        let prompt = """
        Here are this week's Brain entries:
        \(entrySummaries)

        Write a weekly digest following the @Guide instructions exactly.
        """
        return try await session.respond(
            to: prompt,
            generating: WeeklyDigest.self
        ).content
    }
}
```

The digest is stored as a new `DigestEntry` SwiftData model (V1.1) so it can be viewed later in BrainView without regenerating.

---

### Writing Tools — Free in the Reflect Window

No code required. Since `ReflectView` uses a standard `TextEditor`, Writing Tools are available automatically on iOS 18+ — users can proofread, rewrite, or expand their reflection via the system popover. This is worth calling out in the App Store description.

Just… does not expose Writing Tools for the reader body — the stripped article text is rendered in WKWebView, which is outside the Writing Tools system. This is intentional: the article is not the user's text to edit.

---

### Intelligence Feature Matrix

| Feature | Phase | Premium | iOS Minimum | Fallback |
|---------|-------|---------|-------------|---------|
| Article summary ("In brief") | V1 | No — free for all | iOS 26 / AI hardware | Block absent |
| Contextual reflect prompt | V1 | No — free for all | iOS 26 / AI hardware | Static rotating prompts |
| Writing Tools in reflect | V1 | No — system feature | iOS 18 | Standard TextEditor |
| Semantic Brain search | V1.1 | Yes | iOS 26 / AI hardware | Keyword string match |
| Weekly Brain digest | V1.1 | Yes | iOS 26 / AI hardware | Feature absent |

---

### Project Structure Addition

```
├── Services/
│   └── IntelligenceService.swift
│       ├── isAvailable: Bool
│       ├── summarize(_:) → String
│       ├── reflectPrompt(for:) → String
│       ├── rankEntries(_:for:) → [BrainEntry]      // V1.1
│       └── weeklyDigest(from:) → WeeklyDigest      // V1.1
```

---



## Dependencies

| Dependency | Purpose | Source |
|------------|---------|--------|
| **SwiftSoup** | HTML parsing and stripping | Swift Package Manager |
| **SwiftData** | On-device persistence | Apple (iOS 17+) |
| **FoundationModels** | On-device AI: summary, reflect prompt, semantic search, weekly digest | Apple (iOS 26+ / AI hardware) |
| **SFSpeechRecognizer** | On-device voice-to-text in reflect window (`requiresOnDeviceRecognition = true`) | Apple (iOS 16+ / A12+) |
| **WKWebView** | Stripped article rendering | Apple |
| **StoreKit 2** | One-time premium purchase | Apple (iOS 15+) |
| **WidgetKit** | Home screen widget (V1.1) | Apple (iOS 14+) |

No third-party analytics, no crash reporting SDK, no ad SDKs. Ever.

---

## Testing Strategy

### Unit Tests (`JustEllipsisTests`)

| Target | What to test |
|--------|-------------|
| `StreakEngine` | Logical day calculation, streak counting, 3AM boundary, at-risk detection |
| `BrainEngine` | Rank thresholds, progress calculation, edge cases (0 entries, 2001+ entries) |
| `ContentFetcher.strip()` | Strip selectors, content extraction, domain parsing, word count estimation |
| `IntelligenceService` | Availability gate returns correct value; fallback paths invoked when unavailable |

### UI Tests (`JustEllipsisUITests`)

| Flow | Covered |
|------|---------|
| Add link → appears in queue | Yes |
| Open link → reader loads | Yes |
| "In brief" summary shown when AI available | Yes |
| "In brief" absent when AI unavailable | Yes |
| Finish reading → reflect window appears | Yes |
| Contextual prompt shown when AI available | Yes |
| Static prompt shown when AI unavailable | Yes |
| Type reflection → save → Brain entry created | Yes |
| Skip reflect → Brain entry created without reflection | Yes |
| Voice → transcript appears in text field | Yes |
| Streak increments after completing first read of day | Yes |

### Manual Test Checklist (pre-release)

- [ ] Share Sheet adds link from Safari
- [ ] Share Sheet adds link from Chrome
- [ ] Reader renders correctly on all iPhone sizes
- [ ] Reader renders correctly in Dynamic Type (large and accessibility sizes)
- [ ] "In brief" summary appears above article on AI-capable device
- [ ] "In brief" block absent on non-AI device — no error, no placeholder
- [ ] Contextual reflect prompt generated per article on AI-capable device
- [ ] Static prompt shown on non-AI device
- [ ] Writing Tools available in reflect text field (iOS 18+)
- [ ] Countdown pauses while typing
- [ ] Countdown pauses while voice is active
- [ ] Voice permission denied → mic button hidden, type path unaffected
- [ ] Brain cap reached → premium prompt shown, streak unaffected
- [ ] StoreKit purchase → cap removed immediately
- [ ] StoreKit restore → cap removed on subsequent launches

---

## Known Constraints & Future Considerations

| Constraint | Note |
|------------|------|
| No iCloud sync in V1 | Brain entries live on one device. iCloud sync is V1.1 via `ModelConfiguration` with `cloudKitDatabase`. |
| No paywalled content | The content fetcher cannot handle articles behind login walls (NYT, WSJ, etc.). A future version could support a Safari extension path for passing authenticated page content. |
| SwiftSoup accuracy | Content extraction works well for standard article layouts. Custom CMS layouts may produce poor results. A fallback to Safari Reader Mode via WKWebView is the V1.1 solution. |
| On-device voice only | `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` requires iOS 16+ and an A12+ chip. Devices that don't meet this threshold show the typed path only — no server fallback, no degraded experience. |
| Apple Intelligence hardware | Foundation Models requires iOS 26+ and Apple Intelligence-capable hardware (iPhone 15 Pro or newer). All AI features degrade gracefully — the app is fully functional without them. |
| Foundation Models token limit | The on-device model has a context window limit. Article bodies are capped at 4000 characters for summarisation. Long-form content is truncated from the end. |
| Single language | V1 targets English only. Localisation deferred. |
| No analytics or crash reporting | No third-party SDKs. All data stays on-device. |
