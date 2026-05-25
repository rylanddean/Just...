# Expand Feed Directory

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

Grow the built-in browse catalog from ~135 feeds to ~400+ across a wider range of categories by sourcing from established open RSS feed repositories, curating for quality, and expanding the category taxonomy. The feeds.json file stays bundled in the app for v1 — no server required.

---

## Why

The browse directory is the primary on-ramp for users who don't already read RSS. If the first time someone opens it they can't find their interest — gaming, climate, food, AI, history — they close the sheet and the feature has failed. A broader catalog with tighter categories means more users finding a feed that sticks, which is the only path to a sustained reading habit.

135 feeds across 9 categories is a reasonable start, but it leaves large gaps. There is no category for AI and machine learning (arguably the most-discussed topic in tech), no food writing, no climate or environment coverage, no history, no business and startups that isn't rolled into Finance. Users interested in those areas see "Nothing here." That empty state should never happen in browse.

---

## The Tension

Just… is a quality-first product. The risk with "add more feeds" is that it becomes a quantity exercise — dumping 500 mediocre aggregators into the list to hit a number. That would make the directory feel like the rest of the internet: overwhelming and undifferentiated.

The design resolves this with a strict curation gate. Every feed added must pass four criteria before it goes in: it must have posted within the last 90 days, it must be independently authored (not a link aggregator re-hosting other work), it must be substantively readable without a paywall, and it must represent a source a thoughtful reader would actually recommend to a friend. The open feed repos below are starting points, not source-of-truth — every entry is checked by hand before it ships.

---

## Source Repositories

These are the best openly maintained RSS feed collections to draw from. All are on GitHub, freely licensed, and maintained by the RSS community.

### 1. plenaryapp/awesome-rss-feeds
**URL:** `github.com/plenaryapp/awesome-rss-feeds`  
**Format:** OPML + Markdown  
**Coverage:** ~500 feeds, strong on regional news and general interest; well-categorized  
**Best for:** Filling new categories (Health subcategories, regional news, environment)

### 2. greysonp/rss-feeds
**URL:** `github.com/greysonp/rss-feeds`  
**Format:** JSON (compatible with the existing feeds.json structure)  
**Coverage:** Popular feeds across mainstream topics  
**Best for:** Quick import candidates — format already matches the app

### 3. AboutRSS/ALL-about-RSS
**URL:** `github.com/AboutRSS/ALL-about-RSS`  
**Format:** Markdown  
**Coverage:** Comprehensive index of RSS tools *and* curated feed lists by niche  
**Best for:** Finding specialty sources (AI/ML, climate, niche writing) not in the mainstream repos

---

## New Categories

Expand from 9 to ~16 categories. The additions below each have enough quality feeds to populate a meaningful list without padding.

| New Category | Rationale |
|---|---|
| **AI & Machine Learning** | Most-searched tech topic; currently absent from directory |
| **Environment & Climate** | Strong editorial feeds (Inside Climate News, Carbon Brief, Yale E360) |
| **Food & Drink** | High-engagement category; excellent writing (Lucky Peach archive, Eater, Serious Eats) |
| **History** | Underserved; loyal readership (JSTOR Daily, Lapham's Quarterly, The History Blog) |
| **Writing & Craft** | Fits the Just… reader profile; links to the Brain use case |
| **Business & Startups** | Separate out from Finance to surface founder/operator voices |
| **Mental Health** | Complements existing Health but distinct enough to warrant its own label |

Keep the existing 9 categories. Rename "Sport" → "Sports" for consistency.

---

## Curation Criteria

Every feed — new or existing — is checked against these four gates before it ships:

1. **Active:** At least one post in the last 90 days. Check the feed URL directly.
2. **Original:** The feed publishes original writing, not just link-round-ups or scraped content from other sources.
3. **Readable:** The majority of articles are readable without a paywall. Feeds like The Economist (mostly paywalled) should be cut; feeds like The Atlantic (some paywalled, most free) are fine.
4. **Recommendable:** Would a thoughtful person recommend this source to a friend unprompted? If the answer is "maybe" or "it depends," it's out.

Audit the existing 135 feeds with the same criteria. Some will not pass (a few Feedburner URLs are already dead; Matt Levine's Bloomberg feed links to a profile page, not an RSS endpoint).

---

## Technical Approach

The existing data pipeline is already correct for this scope: a static `feeds.json` bundled in the app, decoded into `[FeedDirectoryItem]` at launch, filtered in-memory by category and search text. No service changes needed.

**Work items:**

1. **Audit existing 135 feeds** — verify each URL is live, passes curation criteria, and has accurate metadata. Remove dead or low-quality entries.
2. **Build candidate list** — pull from the three repos above. Target ~350 entries total after audit.
3. **Write descriptions** — every new entry needs a one-line description in the same voice as the existing ones: direct, informative, no marketing language.
4. **Assign categories** — map to the expanded 16-category taxonomy.
5. **Update `feeds.json`** — add all validated entries in the existing JSON schema.
6. **Verify category counts** — each category should have at least 8 feeds; none should exceed 40. If a category is under 8, fold it into a broader one.

No model changes. No view changes. The category picker in `FeedDirectoryView` is dynamic — it derives categories from the data.

---

## Remote Catalog (Follow-on, Not This Ticket)

Bundling `feeds.json` means a catalog update requires an app release. A natural follow-on is to serve the catalog from a CDN (a single static JSON file at a stable URL, fetched on launch and cached locally) so the directory can be refreshed without waiting for App Store review. This is a meaningful improvement but not needed to ship the expanded catalog. Track separately.

---

## Acceptance Criteria

- [ ] Existing 135 feeds audited — dead URLs removed, descriptions corrected
- [ ] Total catalog reaches ≥ 350 feeds
- [ ] All 7 new categories present with ≥ 8 feeds each
- [ ] No feed URL returns a non-200 status or redirects to a homepage
- [ ] No feed has been posted to in > 90 days
- [ ] Every feed has a non-empty `description` of 10 words or fewer
- [ ] Category picker renders all new categories without layout issues (spot-check on iPhone SE and iPad)
- [ ] Search returns results across new category entries
- [ ] "Sport" renamed to "Sports" throughout
