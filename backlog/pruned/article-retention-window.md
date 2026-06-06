# Article Retention Window

**Tier:** Free  
**Effort:** S  
**Status:** Completed

Allow users to configure how many days of RSS feed articles Just… retains. Options: 1, 2, 3, 5, 7 days. Default is 2 days. Changing the value immediately clears existing feed articles and triggers a fresh fetch.

---

## Why

The original 7-day hardcoded retention window was designed around a worst-case fetch cadence. Most users open the app daily and rarely need more than 2 days of backlog. A shorter default reduces DB size, speeds up Digest rendering, and keeps the feed list focused on what's recent. Users who do want deeper history can extend it to 7 days.

---

## Behaviour

- Setting lives in `Settings → Feeds → Article retention`.
- Options: 1 day, 2 days, 3 days, 5 days, 7 days.
- Default: 2 days.
- On change: all existing feed articles are deleted immediately and a fresh in-process fetch runs.
- Queue, Brain, and streak are unaffected.
- Newsletter feeds retain 30 days regardless of this setting (editorial cadence is slower).
- Scraped feeds are never pruned regardless of this setting.

---

## Areas of Impact

| File | Change |
|------|--------|
| `RSSFetchService.swift` | Added `retentionDaysKey` / `defaultRetentionDays` constants; `pruneOldArticles()` reads UserDefaults instead of hardcoded 7 |
| `SettingsView.swift` | Added `@AppStorage` binding and Picker row in FEEDS section; `onChange` clears articles and calls `fetchInProcess` |
| `DigestView.swift` | `init()` reads configurable retention days from UserDefaults instead of hardcoded 7 |
| `FeedDetailView.swift` | `init()` reads configurable retention days for RSS and scraped feed display cutoff |
| `docs/support.html` | Updated Digest FAQ; added new "How many days of articles does Just… keep?" entry |

---

## Acceptance Criteria

- [x] Setting appears in Settings → Feeds as "Article retention"
- [x] Options are 1, 2, 3, 5, 7 days; default is 2 days
- [x] Changing the value deletes all existing feed articles immediately
- [x] A fresh fetch runs automatically after the clear
- [x] Digest and feed detail views respect the new window after next launch / view recreation
- [x] Newsletter feeds retain 30 days regardless of setting
- [x] Scraped feeds are unaffected
- [x] Queue, Brain, and streak entries are not deleted when the setting changes
- [x] Support page reflects the configurable window
