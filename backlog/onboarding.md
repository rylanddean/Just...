# Onboarding

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

A minimal first-run experience communicating Just…'s core concept — reading as a daily discipline — and explaining the Save → Strip → Read → Reflect → Brain loop. Shown once on first launch. Skippable at any step after screen 2.

---

## Why

Just… is conceptually different from every read-later app a user has tried. It is not Pocket. It is not Safari Reading List. Without onboarding, a new user opens the app, sees an empty queue, and leaves. The onboarding must establish the core distinction immediately: this is a reading habit, not an archive. It also provides the context to make the Brain and Reflect window feel meaningful from the first use.

The tone must match the product: calm, direct, no exclamation points.

---

## Screens

All screens are cards in a `TabView` with `.tabViewStyle(.page)`. Horizontal swipe advances between cards. Page dots are hidden — the card stack is the navigation metaphor.

---

**Screen 1 — Brand mark**  
Full dark background. Just… wordmark centred. Tagline below: *"Read. Think. Grow."*  
Holds for 1.2s, then a subtle upward nudge animation cues the user to swipe.  
No skip button on this screen.

---

**Screen 2 — The Problem**  
Icon: hourglass, muted amber.  
Headline: *"You save links you never read."*  
Body: *"Just… is different. It's not a read-later app. It's a reading habit. Your queue is for reading now, not someday."*

---

**Screen 3 — The Reader**  
Icon: open book.  
Headline: *"Strip. Focus. Read."*  
Body: *"Every article is stripped to words. No images, no ads, no distractions. Just the text."*  
Small mockup of a reader card (title + 3 lines of lorem text in Georgia) to make the concept concrete.

---

**Screen 4 — The Reflect Window** *(the most important screen)*  
Icon: an ellipsis (…) in amber.  
Headline: *"60 seconds."*  
Body: *"After each article, a clock starts. One thought. Type it or say it. Research shows this single minute doubles what you remember."*  
Footnote link: *"Why this works →"* — opens an in-app sheet with condensed research from the product proposal. Static content, no network required.

---

**Screen 5 — The Brain**  
Icon: the Brain orb (static, dimmed).  
Headline: *"Your Brain grows."*  
Body: *"Every article you finish. Every thought you capture. Stored in your Brain. It never shrinks."*  
Rank ladder shown inline: Curious → Reader → Thinker → Scholar → Polymath → Luminary, with small dots between each.

---

**Screen 6 — Start**  
Headline: *"Add your first link."*  
Body: *"Share anything from Safari. Or paste a URL."*  
Full-width button: **"Get started"** in amber, dark background text.  
Small muted link below: *"Restore purchase"*

---

## Technical Approach

- `fullScreenCover` from `RootView`, conditioned on `UserDefaults["hasCompletedOnboarding"] == false`.  
- All 6 screens are a `TabView(.page)` with page indicators hidden via `.indexViewStyle(.page(backgroundDisplayMode: .never))`.  
- Skip button (top-right, `AppTheme.textFaint`) appears on screens 2–5. Tapping skip jumps directly to screen 6 by setting tab selection.  
- "Why this works" sheet: a `ScrollView` with the condensed research content. Static string, no network, no external dependency.  
- On "Get started" tap: `UserDefaults["hasCompletedOnboarding"] = true`, dismiss the cover, then present `AddLinkView` as a sheet from `RootView` after a 0.3s delay (allows the cover dismiss animation to complete first).  
- "Restore purchase" calls `PremiumStore.restore()`.

---

## Acceptance Criteria

- [ ] Shown exactly once — never again after "Get started" is tapped
- [ ] All 6 screens render correctly on all iPhone sizes
- [ ] Page swipe advances between screens; horizontal swipe back returns
- [ ] Skip button available on screens 2–5; jumps to screen 6
- [ ] "Why this works" sheet opens, is scrollable, and dismisses cleanly
- [ ] "Get started" sets the flag, dismisses onboarding, and presents AddLinkView
- [ ] "Restore purchase" triggers StoreKit restore flow
- [ ] Onboarding does not appear again after completion, even after reinstall with iCloud backup
