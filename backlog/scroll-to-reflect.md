# Scroll to Reflect

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

Replace the "Done" button tap with a natural scroll-past-the-end gesture. When the user reaches the last line of an article and keeps scrolling, the Reflect view slides up — creating the feeling of scrolling directly into the next moment, not pressing a button to end one. Continuous. Unbroken.

---

## Why

Tapping "Done" is an abrupt context switch. The user has to stop reading, look up at the navigation chrome, and consciously interrupt the reading mode. Scroll-to-reflect mirrors how reading actually ends — you reach the last line and your eyes travel past it. Capturing that gesture makes the transition feel earned rather than mechanical.

Removing the Done button also reduces the top-bar chrome to its minimum: domain label and read time only.

---

## Experience

**Approach indicator:** When the user is within ~150px of the article's bottom, a subtle pull indicator fades in at the screen's lower edge — a thin amber line with a small upward chevron and the word "reflect" in muted text. Never intrudes on reading.

**Trigger:** The user over-scrolls past the article end by ~80px. This is a deliberate, intentional gesture — momentum scrolling alone will not trigger it. A soft haptic tap fires. The Reflect view slides up from the bottom with a spring animation.

**Cancel:** Releasing the over-scroll before 80px springs the indicator back. No transition.

**Fallback Done button:** A small, muted "Done" button remains in the top-right for accessibility and discoverability. It can be removed in a later version once the gesture is established.

---

## Technical Approach

- Inject JavaScript into the WKWebView to detect when `scrollTop + clientHeight >= scrollHeight - 150` and post a `WKScriptMessage` (`nearBottom`).  
- When the `nearBottom` message fires, show the pull indicator with a fade-in animation.  
- Track additional over-scroll delta via the WKWebView's underlying `scrollView` (`WKWebView.scrollView`). `UIScrollViewDelegate.scrollViewDidScroll` reports content offset beyond the natural bottom.  
- When delta > 80pt, fire `UIImpactFeedbackGenerator.impactOccurred()` and call `openReflect()`.  
- Inertia guard: track whether the final delta was achieved by sustained user touch vs. momentum. Only trigger on active touch (use `scrollView.isDragging`).  
- Animate the pull indicator chevron upward as drag progresses, rubber-banding at the limit, matching iOS native over-scroll physics.  
- Accessibility: the fallback Done button is always present and VoiceOver-accessible. VoiceOver announces "Article complete — activate to reflect" when scroll reaches the bottom.

---

## Acceptance Criteria

- [ ] Pull indicator appears only when within 150px of article end
- [ ] 80px over-scroll with active touch triggers reflect transition
- [ ] Momentum scrolling alone does not trigger transition
- [ ] Haptic fires exactly once at trigger threshold
- [ ] Pull indicator animates with rubber-band physics during over-scroll
- [ ] Releasing below threshold returns indicator to hidden state
- [ ] Fallback Done button remains accessible to VoiceOver
- [ ] Transition is continuous — no jarring cut between reader and reflect
