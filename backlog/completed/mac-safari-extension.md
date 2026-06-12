# Mac Safari Extension

**Tier:** Free  
**Effort:** L  
**Status:** Done

Add a Safari extension for macOS that lets users send any page URL to their Just… queue with a single click. Links appear on the iPhone instantly via iCloud — no app switching, no copy-paste, no friction.

---

## Why

The iOS share sheet handles link capture well inside the phone. But reading discovery often happens at a desk: a long article opened in Safari, a tab someone wants to read properly later. The current path — copy URL, pick up the phone, open Just…, paste — has too many steps to become a habit. A toolbar button that sends the page in one click removes all of it.

This extends the Just… reading habit to wherever reading discovery actually happens, without pulling the user into a Mac-native reading experience they didn't ask for. The Mac is for capturing. The phone is for reading.

---

## Experience

**Toolbar button**
- Amber `…` glyph in the Safari toolbar, styled to match the app icon.
- Monochrome (template image) when inactive; full amber when the current page can be added.
- Greyed with a dash when the URL is already in the queue.

**Popup — idle state**
- Appears below the toolbar button on click.
- Dark brown background matching `pageBg` (`#0C0A08`).
- Single line: `"Add to Just…"` — amber button, Playfair Display, 16pt.
- Page title shown above in `cream` (`#F5ECD7`), clipped to one line, DM Mono 11pt.
- Domain shown in `muted` (`#8A8070`), DM Mono 11pt.
- Keyboard shortcut hint in `subtle` (`#5A5248`): `⌥⇧J`.
- No cancel button. Pressing Escape or clicking outside closes it.

**Popup — success state**
- Button label changes to a checkmark, amber, 0.8s hold, then popup auto-dismisses.
- No confetti. No sound. Just the checkmark.

**Popup — duplicate state**
- Button becomes a dash icon. Single line below: `"Already in your queue."`
- Auto-dismisses after 0.8s.

**Popup — error state**
- `"Couldn't save this link."` in `streakDanger` (`#E05A5A`).
- Stays open. User closes manually.

**Keyboard shortcut**
- Global Safari shortcut `⌥⇧J` triggers the save silently (no popup) when the user is browsing and knows what they're doing.
- On success: toolbar button flashes amber once.

---

## Copy Strings

| Moment | Copy |
|--------|------|
| Popup idle | `"Add to Just…"` |
| Already in queue | `"Already in your queue."` |
| After save | *(checkmark only — no text)* |
| Error | `"Couldn't save this link."` |
| Keyboard hint | `⌥⇧J` |
| Extension description (System Preferences) | `"Add the current page to Just…"` |

All copy is text-only. No emoji. No exclamation points.

---

## Technical Approach

### New Targets

Two new Xcode targets are required:

1. **`JustEllipsisMac`** — macOS companion app (required by Apple to distribute a Safari extension; can be a minimal window-less app).
2. **`JustEllipsisSafariExtension`** — Safari Web Extension target inside the companion app.

The companion app is invisible to the user beyond appearing in System Preferences → Extensions → Safari. It requires no UI beyond an `NSApplicationDelegate` that stays resident.

### Extension Architecture

The extension uses the **Safari Web Extension** model (available Safari 14+, macOS 11+):

- **`popup.html / popup.js`** — The toolbar popup. Captures current tab URL and title via `browser.tabs.query`, sends a native message to the host app.
- **`background.js`** — Handles the keyboard shortcut `⌥⇧J` and sends silent-save native messages.
- **`manifest.json`** — Declares permissions (`activeTab`, `nativeMessaging`), keyboard command, and toolbar action.

### iCloud Sync — How Links Reach the Phone

The macOS companion app (`JustEllipsisMac`) receives a native message from the extension and writes a `QueuedLink` record directly to CloudKit using `CKModifyRecordsOperation`:

1. Extension sends `{ url, title }` message to the companion app via native messaging (`browser.runtime.sendNativeMessage`).
2. Companion app receives the message in its `NSExtensionRequestHandling` handler.
3. Companion app constructs a `CKRecord` matching the `QueuedLink` schema (same field names used by SwiftData's CloudKit sync in the iOS app).
4. Companion app writes the record to the private CloudKit database (`iCloud.com.rylandean.justellipsis`) using `CKContainer`.
5. On the iPhone, `NSPersistentCloudKitContainer` pulls the new record during its next sync window — typically within seconds when both devices are online.

The companion app does **not** use SwiftData (macOS SwiftData + CloudKit has additional complexity and the companion app has no local persistence requirements). A thin `CKModifyRecordsOperation` write is sufficient and maps exactly to what the iOS app expects.

**`QueuedLink` CKRecord field mapping:**

| SwiftData field | CKRecord key | Type |
|-----------------|-------------|------|
| `id` | `id` | `String` (UUID) |
| `url` | `url` | `String` |
| `title` | `title` | `String?` |
| `domain` | `domain` | `String?` |
| `addedAt` | `addedAt` | `Date` |
| `sortOrder` | `sortOrder` | `Int64` |
| `isRead` | `isRead` | `Int64` (0/1) |
| `sourceRaw` | `sourceRaw` | `String` ("manual") |

`cachedHTML` and `prefetchStateRaw` are omitted — the iOS app sets defaults when it first reads the record.

### Duplicate Detection

Before writing to CloudKit, the companion app queries for an existing `QueuedLink` record with the same `url` field:

```swift
let pred = NSPredicate(format: "url == %@", url)
let query = CKQuery(recordType: "CD_QueuedLink", predicate: pred)
```

If a match is found → return `.duplicate` to the extension. If none → write the record.

### Entitlements

The companion app (`JustEllipsisMac`) requires:
- `com.apple.developer.icloud-container-identifiers`: `["iCloud.com.rylandean.justellipsis"]`
- `com.apple.developer.icloud-services`: `["CloudKit"]`
- `com.apple.security.network.client` (for CloudKit)

The Safari Extension target requires:
- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`

No App Group is needed — data flows through CloudKit, not shared containers (macOS and iOS cannot share an App Group across platforms).

### Companion App Visibility

The companion app window is suppressed:
```swift
// JustEllipsisMacApp.swift
NSApplication.shared.setActivationPolicy(.accessory)
```
It appears in the menu bar only if the user explicitly opens it from System Preferences. No dock icon.

---

## Visual Design

**Popup dimensions:** 320 × 140pt  
**Background:** `#0C0A08`  
**Surface (inner card):** `#141210`  
**Corner radius:** 12pt  
**Border:** 1pt, `#8A6420` (amberDim)  
**Amber button:** `#E8A83E` background, `#0C0A08` text, 8pt radius, full width  
**Typography:** Playfair Display for the button label; DM Mono for title/domain/hint  

The popup deliberately mirrors the app's `surface` card language — a user who opens Just… on their phone should immediately recognise the visual family.

**Toolbar icon:** Provide as a `…` glyph in Playfair Display Italic, exported as a template PNG at 16pt × 16pt and 32pt × 32pt (for Retina). The template rendering lets Safari tint it automatically for dark/light mode toolbars.

---

## Acceptance Criteria

- [ ] Safari toolbar button appears after enabling the extension in Safari → Settings → Extensions
- [ ] Clicking the button opens a popup showing the current page title, domain, and amber "Add to Just…" button
- [ ] Clicking "Add to Just…" saves the link; popup shows a checkmark and dismisses in 0.8s
- [ ] Clicking on a page already in the queue shows "Already in your queue." and dismisses in 0.8s
- [ ] Error state shows `"Couldn't save this link."` and stays open until dismissed
- [ ] Keyboard shortcut `⌥⇧J` saves silently; toolbar button flashes amber on success
- [ ] Saved links appear in the iOS app queue within ~10s on a good connection (CloudKit sync)
- [ ] Companion app has no visible window and no dock icon
- [ ] Popup uses `pageBg`, `surface`, `amber`, `cream`, `muted`, `subtle`, `amberDim`, `streakDanger` tokens only — no new colours
- [ ] Extension description in System Preferences reads `"Add the current page to Just…"`
- [ ] Duplicate detection prevents the same URL being written to CloudKit twice

---

## Out of Scope

- Reading articles on Mac — Just… on Mac is for capture only.
- A full macOS app with a queue view, reader, or Brain.
- Syncing `cachedHTML` (HTML prefetch is an iOS-only concern).
- Support for non-Safari browsers.
- RSS feed management from Mac.

---

## Dependencies

- Active iCloud account on both Mac and iPhone (same Apple ID).
- Just… iOS app installed with iCloud sync enabled.
- macOS 13+ (Ventura) — minimum for reliable CloudKit + Safari Web Extension stack.
- Same Apple Developer team ID across both iOS and Mac targets.
- CloudKit container `iCloud.com.rylandean.justellipsis` must have the `CD_QueuedLink` record type registered (it will be, once the iOS app has synced at least once).
