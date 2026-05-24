# Share Sheet Feedback

**Tier:** Free  
**Effort:** S  
**Status:** Backlog

Add clear success, duplicate, and error states to the Share Sheet extension. Currently the extension silently dismisses — users have no confirmation that anything happened. Silent dismissal erodes trust in the feature, especially for first-time users.

---

## Why

The share extension is the primary link-capture path. One ambiguous experience is enough to make a user stop using it. A clear confirmation costs almost no code but meaningfully improves perceived reliability. The three states that matter: saved, already in queue, failed.

---

## Experience

**Success state**  
- Extension view stays visible for 1.2 seconds after saving.  
- Shows: animated checkmark → article domain (e.g. `nytimes.com`) → "Saved to Just…"  
- Colors: dark brown background (`#0C0A08`), body text in `#C8B898`, checkmark in amber (`#E8A83E`).  
- Dismisses automatically with a gentle fade.

**Duplicate state** (URL already in queue)  
- Same visual layout, dash icon instead of checkmark.  
- Text: "Already in your queue."  
- Dismisses after 1.2 seconds.

**Error state**  
- X icon, amber-tinted.  
- Text: "Couldn't save this link." + brief reason if available (e.g. "No URL found in this share").  
- Stays visible for 2 seconds. User can tap anywhere to dismiss early.

All states use Just… brand typography — `Georgia` (serif) for body, system sans for the status line. Rounded card shape with corner radius 16, matching the app's `cardRadius` token.

---

## Technical Approach

- Replace the current `complete()` call sequence with a `UIHostingController` child view containing a lightweight SwiftUI feedback card.  
- The feedback card is purely presentational — no SwiftData, no new dependencies beyond what already exists in the extension.  
- `ShareViewController` determines the state (success / duplicate / error) synchronously before presenting the card.  
- Auto-dismiss: `DispatchQueue.main.asyncAfter(deadline: .now() + 1.2)` for success and duplicate; `+ 2.0` for error.  
- Tap-to-dismiss: `UITapGestureRecognizer` on the hosting view calls `complete()` early.  
- The card slides up from the bottom with a spring animation (`UIViewPropertyAnimator` or SwiftUI `.transition(.move(edge: .bottom))`).  
- Domain label is extracted from the URL by `PendingLinkStore` or a local helper — no network call.

---

## Acceptance Criteria

- [ ] Success card shown for 1.2s after a link is saved
- [ ] Duplicate card shown when the URL already exists in the pending store
- [ ] Error card shown with a brief reason when save fails
- [ ] All states use Just… brand colours and typography
- [ ] Auto-dismiss fires at the correct delays
- [ ] Tapping anywhere dismisses early
- [ ] Extension continues to function across all iOS 17+ share sources
