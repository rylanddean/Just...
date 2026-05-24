# Reader Themes

**Tier:** Premium  
**Effort:** M  
**Status:** Backlog

A settings panel where users choose from 6 carefully designed reading themes. Each theme changes the WKWebView CSS (background, text, accent colour), the SwiftUI reader chrome (Done button, progress bar, countdown ring, voice button), and the Reflect window (save button, cursor tint). Outside the reader, the app stays on its signature dark brown palette.

---

## Why

Reading in the same environment every day builds a ritual. Custom themes let users make that environment personally theirs — a small act of ownership that increases commitment to the habit. The product proposal already scopes this as a premium feature. Offering 6 well-considered presets (not a raw colour picker) keeps the product opinionated while delivering real personalisation.

---

## Themes

| Name | Background | Text | Accent | Mood |
|---|---|---|---|---|
| **Ember** (default) | `#0C0A08` | `#C8B898` | `#E8A83E` | Warm amber. The current default. |
| **Slate** | `#0D1117` | `#C9D1D9` | `#58A6FF` | Cool blue. For tech-focused readers. |
| **Dusk** | `#1A1020` | `#D4C8E0` | `#C084FC` | Deep violet. Calm evening reading. |
| **Sage** | `#0F1612` | `#C8D8C0` | `#6FBF73` | Dark forest green. Easy on the eyes. |
| **Sepia** | `#F4ECD8` | `#3D2B1F` | `#8B4513` | Classic warm light mode. Bookish. |
| **Paper** | `#FAFAF8` | `#1A1A1A` | `#E05C2A` | Clean light mode. Newspaper-crisp. |

All six themes pass WCAG AA contrast for their body text / background pairs. Sepia and Paper are light-mode themes — they flip the WKWebView and SwiftUI backgrounds to light; the tab bar and nav chrome adapt accordingly.

---

## Experience

**Access:** Settings → Reader → Theme.  
**Preview:** Each theme tile shows a 3-line live text preview — users see exactly how articles will look before selecting.  
**Default state:** Ember is the default for all users, including free tier (it is the current experience).  
**Gating:** Selecting any theme other than Ember shows a premium unlock sheet if the user hasn't purchased.  
**Instant apply:** No restart required. The WKWebView re-injects CSS immediately on selection.

---

## Technical Approach

- Add a `ReaderTheme` enum with 6 cases. Each case provides `bg`, `text`, `accent` hex values as static properties.  
- Persist the selected theme in `UserDefaults` (not SwiftData — it is a preference, not data).  
- `ContentFetcher.readerCSS` becomes `readerCSS(for theme: ReaderTheme)` — interpolates the three CSS variables.  
- `AppTheme` gains `currentReaderTheme: ReaderTheme` backed by `UserDefaults`.  
- All reader views already use `AppTheme.readerAccent` — switching the theme propagates automatically.  
- For light themes (Sepia, Paper), inject `color-scheme: light` into the WKWebView and pass the light background to SwiftUI via the theme token.  
- Add a `SettingsView` if it doesn't yet exist; Reader Themes is its first section.

---

## Acceptance Criteria

- [ ] 6 theme tiles in Settings with accurate live text preview
- [ ] Selected theme persists across app restarts
- [ ] Ember is default and always accessible without Premium
- [ ] Non-Ember selection on free tier shows premium prompt, does not apply theme
- [ ] Theme change takes effect immediately — no reload or restart required
- [ ] Light themes do not break the status bar or navigation chrome
- [ ] WKWebView re-renders with new CSS variables on theme change
