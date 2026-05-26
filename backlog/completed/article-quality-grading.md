# Article Quality Grading

**Tier:** Free (Apple Intelligence hardware required)
**Effort:** M
**Status:** Backlog — Original Feature

Before a user queues an article, they have one signal: the title and a feed name. Quality grading gives them a second signal — a quiet three-dot indicator that tells them whether this article is likely worth focused reading time. The grade is assigned by on-device AI before the user opens anything, shown on every card in the Digest and Feed Detail views, and optionally used to hide low-quality articles from the Digest entirely. Grading is opt-in: it is off by default and requires the user to enable it in Settings. A small spinner appears on each card while its grade is being computed, then resolves to the dots.

---

## Why

The Digest surfaces everything the subscribed feeds published in the last 48 hours. The user's job is to decide what to queue. That decision is currently made on title alone — which can't distinguish a short-form essay from a listicle wearing the same headline. Quality grading shifts that decision from instinct to signal.

This is not a rating the user assigns after reading. It is a pre-read assessment: does this article earn focused attention? That question aligns directly with what Just… is for — a reading discipline app, not a read-later pile.

---

## Feasibility Gate

This feature requires Apple Foundation Models (`FoundationModels`, iOS 26+). Before implementation:

- **Verify** that the existing `IntelligenceService` calls (`extractDNA`, `scoreRelevance`, `summarizeFeedItem`) complete within an acceptable time window when triggered in the background after an RSS fetch.
- **If background grading is consistently under ~3 seconds per article on a representative device:** proceed.
- **If it creates visible lag, battery pressure, or queue thrashing similar to past audio-processing work:** do not implement. The feature should not ship with a degraded experience. Silence is better than a slow indicator.

Grading runs from `title + summary/feedDescription` only — no additional HTTP fetch. This is the same content footprint as `summarizeFeedItem`, which already runs in this context.

---

## The Rubric

Three grades, assessed by on-device AI from the article's title and available description:

| Grade | Dots | Meaning |
|-------|------|---------|
| **Strong** | `●●●` | Original thinking, substantive argument, earns focused attention. Essays, analysis, long-form, primary-source reporting. |
| **Worth it** | `●●○` | Informative and reasonably written. News explainers, solid profiles, useful synthesis — not essential, but worth a slot. |
| **Noise** | `●○○` | Aggregated, promotional, listicle, clickbait, or so brief it adds little. The kind of article you finish and feel nothing. |

No grade is shown while assessment is pending when grading is disabled. When grading is enabled and an article is actively being assessed, the card shows a small spinner in place of the dots. Once the grade resolves, the spinner is replaced by the dot indicator.

**AI prompt guide:**

```
Grade this article as a read for someone who values original thinking 
and focused attention:

- "strong": substantive, original argument or insight that earns 
  undivided attention. Long-form essays, analysis, primary reporting.
- "worthIt": informative and well-written but not essential. 
  Explainers, profiles, useful synthesis.
- "noise": aggregated, promotional, listicle, clickbait, 
  or too brief to leave a thought.

Return exactly one of: strong, worthIt, noise.
```

---

## Experience

### Grade indicator on cards

The indicator occupies a fixed slot at the trailing end of the metadata row. Its state depends on whether grading is enabled and whether a grade has been computed:

**Grading off / non-Apple-Intelligence / grading not yet triggered:**
```
┌─────────────────────────────────────────────┐
│ ○  The Attention Merchants           [ + ]  │
│    Aeon · 3h ago                            │
└─────────────────────────────────────────────┘
```
Card is pixel-identical to today. No slot reserved.

**Grading enabled, actively computing:**
```
┌─────────────────────────────────────────────┐
│ ○  The Attention Merchants           [ + ]  │
│    Aeon · 3h ago  ·  ⟳                     │
└─────────────────────────────────────────────┘
```
A `ProgressView()` spinner, scaled to match the dot height (~10pt), tinted `AppTheme.Colors.muted` — it is a loading state, not a grade, so it does not use amber.

**Grading complete, Strong:**
```
┌─────────────────────────────────────────────┐
│ ○  The Attention Merchants           [ + ]  │
│    Aeon · 3h ago  ·  ●●●                   │
└─────────────────────────────────────────────┘
```

**Grading complete, Worth it:**
```
┌─────────────────────────────────────────────┐
│ ○  The Attention Merchants           [ + ]  │
│    Aeon · 3h ago  ·  ●●○                   │
└─────────────────────────────────────────────┘
```

**Grading complete, Noise:**
```
┌─────────────────────────────────────────────┐
│ ○  The Attention Merchants           [ + ]  │
│    Aeon · 3h ago  ·  ●○○                   │
└─────────────────────────────────────────────┘
```

- Dots are rendered as `Circle()` shapes at 5×5pt
- Filled dot: `AppTheme.Colors.amber`
- Empty dot: `AppTheme.Colors.amberDim`
- Separator `·` between timestamp and the spinner/dots uses existing metadata style (`AppTheme.Colors.muted`, 12pt)
- Spinner transitions to dots without animation — the slot width is stable either way

The same treatment applies to `FeedDetailView.ArticleRow` — spinner and dots in the existing metadata row at the same position.

### Settings

Two related toggles live in a "Reading" section, with "Enable article grading" as the parent:

```
READING
─────────────────────────────────
Article grading            [○]
Requires Apple Intelligence.

  Hide noise from digest   [○]
```

- **Article grading** is the master toggle. When off, no grading tasks fire and no spinner or dots appear on any card. When on, newly fetched articles are graded in the background. Previously graded articles retain their stored grade whether the toggle is on or off.
- **Hide noise from digest** is indented below grading and is only interactive when grading is enabled. When both are on, articles where `qualityGrade == .noise` are excluded from today and yesterday sections. They remain in the database.
- Both toggles are disabled and captioned "Requires Apple Intelligence." on non-Apple-Intelligence devices.
- No inline chip or indicator in the Digest itself — settings are persistent and silent.
- "FROM YOUR BRAIN" recommendations are never filtered, regardless of grade or setting state.

### Copy

Toggle labels are plain: "Article grading" and "Hide noise from digest." No inline explanation of the rubric — the dot indicator on each card teaches the scale passively over time.

---

## Technical Approach

### 1. New model field on `RSSArticle`

```swift
// RSSArticle.swift
var qualityGrade: ArticleQualityGrade? // nil = unrated or AI unavailable
```

```swift
// ArticleQualityGrade.swift — new file
enum ArticleQualityGrade: String, Codable {
    case strong
    case worthIt
    case noise
}
```

SwiftData handles `Codable` enums natively. Migration is automatic (new optional field, default nil).

### 2. New Generable type in `IntelligenceService`

```swift
@available(iOS 26, *)
@Generable
struct ArticleQualityAssessment {
    @Guide(description: """
        Grade the article as a read for someone who values original 
        thinking and focused attention.
        Return exactly one of: strong, worthIt, noise.
        - strong: original argument or insight, earns undivided attention
        - worthIt: informative and well-written, not essential
        - noise: aggregated, promotional, listicle, clickbait, or too brief
        """)
    var grade: String
}
```

New static method on `IntelligenceService`:

```swift
@available(iOS 26, *)
static func gradeQuality(title: String, description: String) async -> ArticleQualityGrade? {
    let input = description.isEmpty ? title : "\(title)\n\n\(String(description.prefix(1500)))"
    let session = LanguageModelSession()
    let response = try? await session.respond(
        to: "Grade this article as a read:\n\n\(input)",
        generating: ArticleQualityAssessment.self
    )
    switch response?.content.grade {
    case "strong":  return .strong
    case "worthIt": return .worthIt
    case "noise":   return .noise
    default:        return nil
    }
}
```

### 3. `GradingProgressTracker`

New `@Observable` class, injected into the environment at the root level:

```swift
// GradingProgressTracker.swift — new file
@Observable
final class GradingProgressTracker {
    var activeIDs: Set<UUID> = []

    func markActive(_ id: UUID) { activeIDs.insert(id) }
    func markDone(_ id: UUID)   { activeIDs.remove(id) }
}
```

Injected via `.environment` on `RootView` so both `DigestView` and `FeedDetailView` can read it.

### 4. Trigger grading in `RSSFetchService`

Grading fires only when `IntelligenceService.isAvailable` and `UserDefaults.standard.bool(forKey: "grading.enabled")` is true:

```swift
// After article insert — fire-and-forget, non-blocking
let gradingEnabled = UserDefaults.standard.bool(forKey: "grading.enabled")
if IntelligenceService.isAvailable, gradingEnabled, article.qualityGrade == nil {
    let articleID = article.id
    tracker.markActive(articleID)
    Task.detached {
        let description = article.summary ?? article.feedDescription ?? ""
        let grade = await IntelligenceService.gradeQuality(
            title: article.title,
            description: description
        )
        await MainActor.run {
            article.qualityGrade = grade
            tracker.markDone(articleID)
            try? context.save()
        }
    }
}
```

`RSSFetchService` receives `tracker` as a parameter when called from the fetch trigger. One task per article; grade is persisted and not recomputed on subsequent fetches.

### 5. Grade indicator component

New `ArticleGradeIndicator` view handles all three states — grading active (spinner), grade available (dots), grade absent (nothing):

```swift
// GradeDots.swift — new file
struct ArticleGradeIndicator: View {
    let articleID: UUID
    let grade: ArticleQualityGrade?
    @Environment(GradingProgressTracker.self) private var tracker
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        if tracker.activeIDs.contains(articleID) {
            // Actively grading — show spinner
            ProgressView()
                .scaleEffect(0.55)
                .tint(AppTheme.Colors.muted)
                .frame(width: 22, height: 10)
        } else if let grade {
            // Grade available — show dots
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < grade.filledCount ? appTheme.accent : AppTheme.Colors.amberDim)
                        .frame(width: 5, height: 5)
                }
            }
        }
        // No grade, not grading — renders nothing, takes no space
    }
}

extension ArticleQualityGrade {
    var filledCount: Int {
        switch self {
        case .strong:  return 3
        case .worthIt: return 2
        case .noise:   return 1
        }
    }
}
```

Used in both `DigestArticleRow` and `FeedDetailView.ArticleRow`. Inserted into the metadata `HStack` with a leading `·` separator that appears only when the indicator is visible:

```swift
// Inside the metadata HStack, after the timestamp
let isVisible = tracker.activeIDs.contains(article.id) || article.qualityGrade != nil
if isVisible {
    Text("·")
        .font(AppTheme.sansSerif(12))
        .foregroundStyle(appTheme.textFaint)
    ArticleGradeIndicator(articleID: article.id, grade: article.qualityGrade)
}
```

### 6. Digest filter

```swift
// DigestView.swift
@AppStorage("grading.enabled") private var gradingEnabled: Bool = false
@AppStorage("digest.hideNoise") private var hideNoise: Bool = false

private var todayArticles: [RSSArticle] {
    var seen = Set<String>()
    return articles
        .filter { Calendar.current.isDateInToday($0.publishedAt) }
        .filter { seen.insert($0.url).inserted }
        .filter { !(gradingEnabled && hideNoise && $0.qualityGrade == .noise) }
}
```

Same one-liner filter on `yesterdayArticles`. No filter on Brain recommendations.

### 7. Settings toggles

In `SettingsView`, add a "Reading" section. The "Hide noise" toggle is only `.disabled` when grading is off or Apple Intelligence is unavailable:

```swift
Section("READING") {
    Toggle("Article grading", isOn: $gradingEnabled)
        .disabled(!IntelligenceService.isAvailable)

    Toggle("Hide noise from digest", isOn: $hideNoise)
        .disabled(!gradingEnabled || !IntelligenceService.isAvailable)
        .padding(.leading, 16)

    if !IntelligenceService.isAvailable {
        Text("Requires Apple Intelligence.")
            .font(AppTheme.monoFont(11))
            .foregroundStyle(AppTheme.Colors.muted)
    }
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `Models/RSSArticle.swift` | Add `qualityGrade: ArticleQualityGrade?` |
| `Models/ArticleQualityGrade.swift` | New `Codable` enum + `filledCount` extension |
| `Services/IntelligenceService.swift` | Add `ArticleQualityAssessment` Generable + `gradeQuality()` |
| `Services/RSSFetchService.swift` | Opt-in guard + `GradingProgressTracker` integration |
| `Views/DigestView.swift` | `gradingEnabled` guard, noise filter, `ArticleGradeIndicator` in `DigestArticleRow` |
| `Views/FeedDetailView.swift` | `ArticleGradeIndicator` in `ArticleRow` |
| `Views/SettingsView.swift` | Article grading toggle + hide noise toggle |
| `App/RootView.swift` | Inject `GradingProgressTracker` into environment |
| `Components/GradeDots.swift` | New `ArticleGradeIndicator` component |
| `State/GradingProgressTracker.swift` | New `@Observable` tracker |

---

## Acceptance Criteria

**Opt-in setting**
- [ ] "Article grading" toggle in Settings, persisted via `AppStorage("grading.enabled")`, default `false`
- [ ] Grading tasks only fire when both `grading.enabled == true` and `IntelligenceService.isAvailable`
- [ ] Grading does not trigger when the toggle is off — no tasks, no spinners, no dots
- [ ] Both toggles show `.disabled` and a capability note on non-Apple-Intelligence devices
- [ ] "Hide noise from digest" toggle is only interactive when "Article grading" is also on

**Grading behaviour**
- [ ] `ArticleQualityGrade` enum persists correctly via SwiftData (`strong`, `worthIt`, `noise`, `nil`)
- [ ] An article that already has a stored grade is not re-graded on subsequent fetches
- [ ] Grading runs in a detached `Task` — UI is never blocked waiting for a grade
- [ ] No additional HTTP fetches for grading — uses `title` + `summary`/`feedDescription` only
- [ ] `GradingProgressTracker` is injected at root and accessible in both Digest and Feed Detail views

**Spinner**
- [ ] While an article's grade is being computed, a `ProgressView` spinner appears in the metadata row (Digest and Feed Detail)
- [ ] Spinner is tinted `AppTheme.Colors.muted` — not amber
- [ ] Spinner is replaced by dots when the grade resolves — no animation required
- [ ] The `·` separator before the indicator appears only when either the spinner or dots are visible
- [ ] Spinner does not appear if grading is disabled, even for ungraded articles

**Grade dots**
- [ ] `●●●` Strong: all three dots amber; `●●○` Worth it: two amber, one dim; `●○○` Noise: one amber, two dim
- [ ] Grade dots appear in the metadata row of `DigestArticleRow` when `qualityGrade != nil`
- [ ] Grade dots appear in the metadata row of `FeedDetailView.ArticleRow` when `qualityGrade != nil`
- [ ] Cards with no grade and no active task are pixel-identical to today's layout
- [ ] All dot and spinner colours use `AppTheme.Colors` tokens — no hardcoded hex values

**Digest filter**
- [ ] When "Hide noise from digest" is on, `qualityGrade == .noise` articles are excluded from today and yesterday sections
- [ ] Filtered articles remain in the database — they are not deleted
- [ ] "FROM YOUR BRAIN" recommendations are never filtered by quality grade, regardless of setting state
