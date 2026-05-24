# Typography Settings

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

Allow users to choose their reading font in Settings, and adjust font size inline in the reader. Both settings apply to the WKWebView-rendered article and the SwiftUI Reflect window text editor.

---

## Why

Reading comfort is personal. Some users find serif fonts slower to process at small sizes; others find sans-serif cold for long-form text. Offering two axes of control — family and size — is the most meaningful typographic personalisation the reader can offer.

---

## Font Families

| Name | CSS Stack | Character |
|---|---|---|
| **Georgia** (default) | `Georgia, serif` | Classic, bookish. The current default. |
| **New York** | `ui-serif, serif` | The device's native serif. Contemporary and elegant. |
| **San Francisco** | `-apple-system, sans-serif` | Clean, familiar, efficient. |
| **Lora** | `Lora, Georgia, serif` | Warm humanist serif. High reading comfort. |
| **Literata** | `Literata, Georgia, serif` | Google's ebook font. Optimised for sustained reading. |

Lora and Literata are open-source (SIL Open Font License). Bundled in the app to avoid a network dependency. Total addition: ~420kb.

Georgia is the default. All five font families are available to all users.

---

## Font Size

**Default:** 20px (current).  
**Range:** 16px – 28px in 2px increments.  
**Inline control:** +/- buttons in the reader top bar (in the space between the X and domain label). Visible during reading only.  
**Persists:** `UserDefaults`. Changes apply immediately — no article reload.  
**Pinch-to-zoom:** Enable WKWebView pinch-to-zoom (currently disabled). Scale snaps to the nearest 2px step on gesture end.

---

## Technical Approach

- `ReaderTheme` struct gains `fontFamily: ReaderFont` and `fontSize: Int` fields.  
- `ContentFetcher.readerCSS(for theme:)` interpolates both into the CSS `font-family` and `font-size` properties.  
- Font family and size persisted in `UserDefaults`. Changing either posts a `NotificationCenter` notification that `ReaderWebView` observes, re-injecting the style block into the existing WKWebView without reloading page content.  
- Bundled fonts declared in `project.yml` under `INFOPLIST_KEY_UIFonts` (or legacy `UIAppFonts` key).  
- Font files go in `JustEllipsis/Resources/Fonts/`.  
- `ReflectView`'s `TextEditor` uses `AppTheme.serif()` or `AppTheme.sansSerif()` depending on the selected font family — so the reflect environment matches the reading environment.

---

## Acceptance Criteria

- [ ] 5 font families available in Settings → Reader → Font
- [ ] Georgia is default; all 5 font families selectable immediately
- [ ] Font size +/- buttons visible in reader top bar
- [ ] Font size range 16–28px persists across sessions
- [ ] Pinch-to-zoom enabled; snaps to step on release
- [ ] Lora and Literata render from bundled files — no fallback to Georgia
- [ ] Font changes apply immediately via CSS re-injection — no article reload
- [ ] Reflect TextEditor font matches selected reader font family
