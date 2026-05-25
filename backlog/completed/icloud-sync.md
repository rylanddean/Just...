# iCloud Sync

**Tier:** Free  
**Effort:** L  
**Status:** Backlog

Sync the reading queue (`QueuedLink`), Brain entries (`BrainEntry`), and reading days (`ReadingDay`) across all of a user's iCloud-connected devices using CloudKit + SwiftData. The architecture doc explicitly scopes this to V1.1 — "iCloud sync is V1.1 via `ModelConfiguration` with `cloudKitDatabase`."

---

## Why

Users who save links on one device and want to read on another lose queue continuity today. Power users with growing Brains face the risk of losing entries to a lost or replaced device. iCloud sync solves both with zero additional accounts, zero servers, and near-zero UX complexity — it's automatic, invisible, and native to the Apple ecosystem.

---

## Experience

**Opt-in:** Sync is enabled from Settings → Sync → "Sync with iCloud". A brief explanation: "Your queue, Brain, and streak sync automatically across devices signed into the same Apple ID."  
**No account required:** No separate login. Uses the user's existing Apple ID.  
**Offline behaviour:** All changes write to the local SwiftData store first. Sync happens when connectivity returns. The offline-first architecture is unchanged.  
**Conflict handling:** CloudKit uses last-write-wins per field. `BrainEntry.reflection` conflicts are rare; minor `sortOrder` ordering surprises on `QueuedLink` are acceptable. Noted in the Settings description.  
**Disable:** Toggling sync off reverts to local-only. Existing data is retained on-device; CloudKit copy remains until the user deletes the container manually.

---

## Technical Approach

- Change `ModelConfiguration` to use `.cloudKitDatabase(.private("iCloud.com.rylandean.justellipsis"))` when sync is enabled.  
- Gate via a `UserDefaults` flag `iCloudSyncEnabled`. On first enable, a one-time migration pass promotes local records into the CloudKit-backed configuration.  
- **Critical:** `cachedHTML` on `QueuedLink` must be excluded from sync. A 50–200kb HTML blob per link would make the sync slow and risk hitting CloudKit's 1MB per-record limit. Options: mark with `@Attribute(.externalStorage)` and verify CloudKit exclusion, or move cached HTML to a separate non-synced `QueuedLinkCache` model keyed by URL.  
- `cachedHTML` on secondary devices is simply `nil` — the reader fetches and caches it fresh on first open. This is already the standard code path.  
- Add `iCloud` and `Push Notifications` capabilities to `project.yml` under the main app target.  
- The Share Extension writes to the App Group UserDefaults store as before. The main app drains and inserts into SwiftData, which CloudKit then syncs. No change to the extension.  
- Use `ModelConfiguration.migrationPlan` for future schema changes — CloudKit schema migrations require coordination between app versions.

---

## Risks

| Risk | Mitigation |
|---|---|
| CloudKit schema changes break older app versions | Pin schema version; use migration plan; never delete CloudKit fields (only add) |
| `cachedHTML` in CloudKit causes oversized records | Confirmed exclusion before shipping — test with large HTML blobs |
| Two devices complete same article before sync | Last-write-wins on `QueuedLink` deletion is acceptable; Brain entries are append-only |
| User disables iCloud Drive in system Settings | Detect availability via `FileManager.default.ubiquityIdentityToken`; show Settings deep-link if unavailable |

---

## Acceptance Criteria

- [ ] Toggle in Settings; available to all users
- [ ] Queue, Brain entries, and reading days sync across two devices on the same Apple ID
- [ ] `cachedHTML` is not synced — fetched fresh on secondary devices
- [ ] Offline writes queue locally and sync on reconnect
- [ ] Disabling sync reverts to local-only without data loss
- [ ] Sync is entirely background — no spinner or loading state visible to the user
- [ ] App functions correctly when iCloud Drive is disabled (graceful fallback to local)
