# Onboarding

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

A minimal first-run experience communicating Just…'s core concept — reading as a daily discipline — and explaining the Save → Strip → Read → Reflect → Brain loop. Shown once on first launch. Skippable at any step after screen 2.

---

## Why

Just… is conceptually different from every read-later app a user has tried before. It is not Pocket. Without onboarding, a new user opens the app, sees an empty queue, and leaves. The onboarding must establish the core distinction immediately: this is a reading habit, not an archive.

The tone must match the product: calm, direct, no exclamation points. The onboarding itself is a signal about what kind of app this is.

---

## Screens

All screens are cards in a `TabView` with `.tabViewStyle(.page)`. Horizontal swipe advances. Page dots are hidden — the card stack is the navigation metaphor.

---

**Screen 1 — Brand mark**
Full dark background. Just… wordmark centred. Tagline below: *"Read. Think. Grow."*
Holds for 1.2s, then a subtle upward nudge animation cues the user to swipe.
No skip button on this screen.

---

**Screen 2 — The Problem**
Icon: hourglass glyph, `muted` amber.
Headline: *"You save links you never read."*
Body: *"Just… is different. It's not a read-later app. It's a reading habit. Your queue is for reading now, not someday."*

---

**Screen 3 — The Reader**
Icon: open book glyph.
Headline: *"Strip. Focus. Read."*
Body: *"Every article is stripped to words. No images, no ads, no distractions. Just the text."*
Small mockup of a reader card (title + 3 lines of lorem text in Georgia) to make the concept concrete.

---

**Screen 4 — The Reflect Window**
Icon: ellipsis (…) in amber. The most important screen.
Headline: *"60 seconds."*
Body: *"After each article, a clock starts. One thought. Type it or say it. Research shows this single minute doubles what you remember."*
Footnote link: *"Why this works →"* — opens an in-app sheet with condensed research. Static content, no network.

---

**Screen 5 — The Brain**
Icon: the Brain orb (static, dimmed).
Headline: *"Your Brain grows."*
Body: *"Every article you finish. Every thought you capture. Stored in your Brain. It never shrinks."*
Rank ladder shown inline: Curious → Reader → Thinker → Scholar → Polymath → Luminary, with small amber dots between each.

---

**Screen 6 — Start**
Headline: *"Add your first link."*
Body: *"Share anything from Safari. Or paste a URL."*
Full-width button: **"Get started"** — amber background, dark text.
Small muted link below: *"Restore purchase"*

---

## Technical Approach

- `fullScreenCover` from `RootView`, conditioned on `UserDefaults["hasCompletedOnboarding"] == false`.
- All 6 screens in a `TabView(.page)` with `.indexViewStyle(.page(backgroundDisplayMode: .never))`.
- Skip button (top-right, `textFaint`) appears on screens 2–5. Taps jump directly to screen 6 by setting the tab selection to index 5.
- "Why this works" sheet: a `ScrollView` with condensed research content (Ebbinghaus forgetting curve, testing effect, production effect). Static string, no network, no external dependency.
- On "Get started": set `UserDefaults["hasCompletedOnboarding"] = true`, dismiss the cover, then present `AddLinkView` as a sheet from `RootView` after a 0.3s delay (lets the cover dismiss animation complete).
- "Restore purchase" calls `PremiumStore.restore()`.

---

## Acceptance Criteria

- [ ] Onboarding shown exactly once — never again after "Get started" is tapped
- [ ] All 6 screens render correctly on all iPhone sizes (SE through Plus)
- [ ] Page swipe advances between screens; swipe back returns
- [ ] Skip button available on screens 2–5; jumps to screen 6
- [ ] No skip button on screen 1
- [ ] "Why this works" sheet opens, is scrollable, and dismisses cleanly
- [ ] "Get started" sets the flag, dismisses onboarding, and presents AddLinkView after 0.3s
- [ ] "Restore purchase" triggers StoreKit restore flow
- [ ] Onboarding does not appear again after completion, including after reinstall with iCloud backup (flag persists via iCloud `NSUbiquitousKeyValueStore` or standard `UserDefaults` — whichever is already used for other flags)
- [ ] All colours via `appTheme` tokens — no hardcoded hex
- [ ] No exclamation points in any copy
