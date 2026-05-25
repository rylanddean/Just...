# iPad Support

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

Adapt Just… for iPad — a larger canvas that demands a different layout without losing the focused, distraction-free reading experience that defines the app.

---

## Why

iPad is the natural reading device for long-form content. Users who add links on iPhone will increasingly want to read them on iPad. The app runs on iPad today via iPhone compatibility mode, but that is not a layout — it is a concession. A proper iPad adaptation respects the screen and the user's intent.

---

## Layout Approach

Just… on iPad does not become a multi-column productivity app. The reading habit is still one link at a time. The goal is to use the additional space to improve the reading experience, not to add surface area.

| View | iPhone | iPad |
|------|--------|------|
| Root / Queue | Full-screen list | Sidebar + detail split (UISplitViewController) |
| Reader | Full-screen WKWebView | Centered column, max-width ~680pt, generous horizontal margins |
| Reflect window | Bottom sheet | Floating panel, centered, ~540pt wide |
| Brain | Full-screen list | Sidebar + detail split |
| RSS Feeds | Full-screen list | Sidebar + detail split |
| Settings | Full-screen list | Standard iPad settings split |

### Reader Column

The reader on iPad uses a capped content width — the same principle used by every serious reading app and publication. Long lines are harder to read; narrower columns are not wasted space.

- Max content width: **680pt**
- Horizontal padding: automatic centering via CSS `margin: 0 auto`
- Background (`pageBg`) extends edge-to-edge behind the centered column
- No sidebar during reading — full attention on the article

### Reflect Panel

The Reflect window on iPad should feel like opening a notebook beside what you just read, not like a full-screen interruption.

- Presentation: sheet with `presentationDetents([.medium, .large])`
- Width: capped at 540pt, centered
- Same timer, same prompts, same behaviour — layout only changes

---

## Technical Approach

- Adopt `NavigationSplitView` for the three split-layout views (Queue, Brain, Feeds). iPhone layout continues to use `NavigationStack` unchanged.
- Use `horizontalSizeClass` environment value to branch layout decisions. Keep branching shallow — one `if sizeClass == .regular` per view, not scattered throughout.
- Reader CSS already uses `max-width` for the article body. Extend this to apply a wider max-width on regular size class (`@media (min-width: 768px)`).
- Reflect sheet: add `.frame(maxWidth: 540)` and `.presentationDetents([.medium, .large])` when size class is regular.
- Test in both landscape and portrait. Landscape splits give the sidebar more room — ensure the sidebar does not feel bloated.
- Stage and focus bar (iPad multitasking): test in Split View and Slide Over. The reading column should remain usable at Slide Over width (~320pt).

---

## What Does Not Change

- The queue is still one link at a time. Selecting a link opens the reader — it does not preview inline in the detail pane.
- The streak mechanic, Brain rank system, and all copy strings are identical.
- No new features ship with this — layout adaptation only.
- iPhone layout is untouched.

---

## Acceptance Criteria

- [ ] App declares iPad support — `UIDeviceFamily` includes iPad in `Info.plist`
- [ ] Queue, Brain, and RSS Feeds use `NavigationSplitView` on regular size class
- [ ] Reader content column is centred and capped at 680pt on iPad
- [ ] Reflect panel is capped at 540pt wide and uses `.medium` detent by default on iPad
- [ ] No layout regressions on iPhone (all existing size-class-compact paths unchanged)
- [ ] App is usable in Split View at Slide Over width (~320pt)
- [ ] Landscape and portrait tested on both 11" and 13" iPad canvas sizes
