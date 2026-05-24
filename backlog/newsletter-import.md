# Newsletter Import

**Tier:** Free  
**Effort:** M (V1 share extension) / L (V2 IMAP auto-import)  
**Status:** Backlog

Surface reading links from newsletters directly into the queue — removing the daily effort of manually hunting for content. V1 is user-initiated via the share extension. V2 adds optional automatic polling via IMAP.

---

## The Problem

The share extension solves "I found a link, add it." Newsletters solve "I want good content to come to me." Many of the best publications in the world — Stratechery, Dense Discovery, The Browser, Lenny's Newsletter — exist only as email. Right now, a Just… user who subscribes to these has to open their mail app, find a link they want to read, copy it, and paste it into Just…. That is four steps too many for a habit that is supposed to feel effortless.

---

## Apple's Email API Landscape

There is no public iOS API for reading the Mail app. `MessageUI` only composes; it cannot read. iOS Mail Extensions exist on macOS only and are scoped to spam filtering. The real options are:

| Approach | Privacy surface | Backend? | Works with |
|---|---|---|---|
| **Share extension (V1)** | None — content delivered via share sheet | No | Any mail app |
| **IMAP polling (V2)** | Credentials stored in Keychain; device-to-server only | No | Gmail, Outlook, iCloud, any IMAP |
| **Gmail / Outlook OAuth (V2 alt)** | OAuth token in Keychain; provider sees search query | No | Gmail or Outlook only |
| **Forward-to address** | Requires backend server | Yes | Any mail client |

The forward-to approach is ruled out — it requires backend infrastructure, which violates the no-backend architecture. V1 is the share extension. V2 is opt-in IMAP.

---

## V1 — Newsletter Share Extension

### How it works

The existing share extension already handles URLs. This extends it to handle **email content** — specifically newsletter HTML passed from any mail client via the share sheet.

When a user shares an email to Just…:
1. The extension receives the email as `public.html` or `public.plain-text` via `NSExtensionItem`.
2. SwiftSoup parses the HTML locally — no network call, no server.
3. All URLs are extracted and filtered (see filtering rules below).
4. A lightweight pick-list UI shows the filtered links — title, domain, estimated read time.
5. The user selects which links to queue. Each tap adds a `PendingLinkStore` entry.
6. The extension dismisses. The main app drains the store on next foreground.

### Experience

**Trigger:** User opens a newsletter in Mail, Gmail, Outlook, Spark, or any mail client → taps Share → Just….

**Pick list UI:** A sheet with the Just… brand card style. Each row shows the article title (from the link's anchor text or the URL domain) and domain. Checkboxes allow multi-select. A single "Add {n} to queue" button at the bottom. Cancel dismisses with nothing added.

**After adding:** Standard share extension success card ("Saved to Just…") showing the count: "3 links added to your queue."

### Link Filtering Rules

Not every URL in a newsletter belongs in a reading queue. The extension filters aggressively:

**Exclude:**
- Unsubscribe / manage preferences links (URLs containing `unsubscribe`, `optout`, `preferences`, `manage`)
- Tracking pixels and redirects (URLs with no meaningful path, or known redirect domains like `click.mailchimp.com`, `link.substack.com/redir`)
- Social media profile links (`twitter.com`, `instagram.com`, `linkedin.com`, `facebook.com`)
- The newsletter's own homepage (domain matches the From address domain)
- Image assets and CDN URLs (non-HTML content types inferred from URL extension: `.jpg`, `.png`, `.gif`, `.css`, `.js`)
- URLs shorter than 20 characters (too short to be a real article)

**Keep:**
- External article URLs — links that point to a different domain than the newsletter sender
- Links whose anchor text is longer than 20 characters (likely a headline, not a button label)
- Links containing path segments that look like article slugs (`/article/`, `/post/`, `/p/`, `/blog/`, year patterns `/2024/`, `/2025/`)

This heuristic catches the vast majority of newsletter formats (Substack, Mailchimp, Beehiiv, ConvertKit, Ghost). Edge cases will occasionally surface a non-article link — the pick-list UI ensures the user always has final say.

### Technical Approach

- Extend `ShareViewController` to handle `public.html` and `public.email-message` UTIs in addition to `public.url`.
- When the input item is an email, extract the HTML body from the attachment.
- Pass the HTML to a new `NewsletterParser.extractLinks(from html: String) -> [NewsletterLink]` function (pure static, SwiftSoup, no network).
- `NewsletterLink: Sendable { let url: String; let title: String; let domain: String }`.
- Present a `UIHostingController` with a SwiftUI pick-list view.
- Each selected link is written to `PendingLinkStore` on confirm.
- The pick list replaces the immediate-dismiss behaviour for email inputs only; URL inputs still dismiss instantly as before.

---

## V2 — IMAP Auto-Import (Optional, Opt-In)

### Concept

The user connects a mailbox once. Just… runs a daily background task, finds new newsletter emails, extracts links using the same `NewsletterParser`, and adds any it hasn't seen before to the queue — ready to read without any manual action.

This is the "just show up" version. The queue fills itself.

### Why V2 and not V1

Storing email credentials is a meaningful responsibility. The app's architecture principle is "all data stays on-device" — IMAP satisfies this (device talks directly to the mail server, no middleman), but it requires the user to consciously trust Just… with their inbox. That trust must be earned through the V1 share extension experience first. It also requires more careful UX to scope the access (newsletter folder only, not full inbox).

### Privacy Design

- Credentials stored in the iOS Keychain — never in SwiftData, never in UserDefaults.
- IMAP connection is device-to-mail-server only. No proxy, no backend, no Anthropic or Just… server involved.
- Access is scoped to a specific folder or label if possible. Recommended setup: the user creates a "Just…" filter in their mail client that moves newsletters into a dedicated folder, and Just… reads only that folder.
- The setup screen explains this explicitly before asking for credentials: *"Just… connects directly from your device to your mail server. Your credentials never leave your phone."*
- Disconnect at any time from Settings → Newsletters. Disconnecting deletes credentials from the Keychain immediately.

### Newsletter Detection

Even with a scoped folder, the IMAP scanner needs to identify emails that are newsletters (not personal emails or transactional messages). Detection signals:
- `List-Unsubscribe` header present — the most reliable signal; all bulk senders are required to include this
- `Precedence: bulk` or `Precedence: list` header
- From address matches a known newsletter domain (Substack, Beehiiv, Ghost, Mailchimp, etc.)
- Link density: body contains more than 3 external article URLs

Emails that don't match are ignored — personal emails are never parsed.

### IMAP Library

Swift has no built-in IMAP client. Options:
- **MailCore2** — mature Objective-C library with Swift bindings. Supports IMAP, SMTP, MIME. Well-maintained.
- **NIOIMAP** — Swift NIO-based IMAP parser (Apple open source). Lower-level, more work, but pure Swift.

MailCore2 is the pragmatic choice for V1 of the IMAP path.

### Auto-Import Behaviour

- Background task runs once daily (`BGProcessingTask`).
- Fetches emails received since the last check (stored timestamp).
- Runs `NewsletterParser.extractLinks` on each qualifying email.
- Deduplicates against existing `QueuedLink` URLs.
- Adds new links to SwiftData via the standard insert path.
- Maximum 5 links added per daily run — prevents queue flooding if the user subscribes to many high-volume newsletters.
- A subtle badge or note on newly auto-imported cards: a small envelope glyph in the card corner (like the RSS glyph for RSS picks).

### Setup Flow

1. Settings → Newsletters → "Connect a mailbox"
2. Choose provider: Gmail, Outlook, iCloud, or Other (IMAP)
3. For Gmail/Outlook: OAuth flow in a `WKWebView` (no server-side OAuth needed — use PKCE / installed app flow)
4. For iCloud / Other: IMAP host, port, username, app-specific password
5. Choose folder to monitor (defaults to Inbox; recommend setting up a "Newsletters" filter first)
6. Test connection — shows count of qualifying emails found
7. Done

---

## Brand Alignment Check

| Principle | V1 Share Extension | V2 IMAP |
|---|---|---|
| No backend | ✅ | ✅ |
| Offline-first | ✅ | ✅ (background fetch) |
| All data on-device | ✅ | ✅ (Keychain only) |
| User controls what enters the queue | ✅ Pick list | ⚠️ Auto-import with 5-link cap |
| Privacy-first | ✅ No permissions | ⚠️ Requires Keychain credentials — disclosed clearly |
| Not a read-later archive | ✅ User picks | ⚠️ Daily cap prevents flooding; auto-import serves the habit |

V1 is fully on-brand with zero compromise. V2 is acceptable with clear disclosure and the daily cap — the cap is what keeps the queue a reading queue rather than an inbox.

---

## Acceptance Criteria

### V1

- [ ] Share extension handles `public.html` and `public.email-message` input types
- [ ] Links extracted locally via SwiftSoup — no network call
- [ ] Filter rules remove unsubscribe, tracking, social, and non-article URLs
- [ ] Pick-list UI shows filtered links with title and domain
- [ ] User can select any subset; "Add {n} to queue" confirms
- [ ] Cancel adds nothing
- [ ] Success card shows link count ("3 links added to your queue.")
- [ ] Works from Mail, Gmail app, Outlook, Spark, and any share-capable mail client

### V2

- [ ] IMAP credentials stored in Keychain, never elsewhere
- [ ] Setup flow supports Gmail (OAuth), Outlook (OAuth), iCloud, and generic IMAP
- [ ] Only emails with `List-Unsubscribe` header or matching newsletter signals are parsed
- [ ] Maximum 5 links auto-added per daily background run
- [ ] Auto-imported links show a small envelope glyph in `LinkCard`
- [ ] Disconnect in Settings removes Keychain credentials immediately
- [ ] Privacy disclosure shown before credential entry: *"Just… connects directly from your device to your mail server. Your credentials never leave your phone."*
- [ ] Deduplication prevents the same URL being added twice
