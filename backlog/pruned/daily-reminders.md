# Daily Reminders

**Tier:** Free  
**Effort:** S  
**Status:** Done

A smart, calm notification system that reminds users to read before they lose their streak. Two proactive types (morning queue nudge, evening at-risk alert) plus two reactive types (streak lost, Brain rank-up). Permission is requested contextually — never on cold launch.

---

## Why

The architecture doc already sketches the core notification logic. This ticket formalises it into a complete, shippable feature — adding the morning prompt, a daily reminder type, and the contextual permission flow. Streaks are meaningless without the habit of showing up. A well-timed, calm notification is the difference between a 60-day streak and "I forgot again." The Just… tone carries into notifications: no urgency, no guilt, no exclamation points.

---

## Notification Types

| Type | Default time | Copy | Condition |
|---|---|---|---|
| **Morning Queue Nudge** | 8:00 AM | "You have {n} link{s} waiting." | ≥ 1 queued link AND no reading today |
| **Streak at Risk** | 8:00 PM | "Your streak is at risk. Still time." | Streak ≥ 1 AND no reading today |
| **Streak Lost** | 9:00 AM next day | "Your streak ended. Start again." | Had streak ≥ 1 AND no reading day recorded yesterday |
| **Brain Rank Up** | Immediate | "Your Brain is now a {Rank}." | Rank threshold crossed |

Users can toggle each type independently in Settings → Reminders. Morning Nudge and Streak at Risk times are user-adjustable (time picker in Settings).

---

## Permission Flow

Permission is **not** requested on cold launch.

**Contextual trigger:** When the user's streak reaches 3 days for the first time, a quiet banner appears at the bottom of HomeView (above the tab bar, never blocking content): *"Enable reminders to protect your streak?"* with a single "Enable" button. Tap calls `UNUserNotificationCenter.requestAuthorization`.

**Manual enable:** Settings → Reminders → toggle any type on → permission requested if not yet granted.

**Denied state:** Settings → Reminders shows a muted label: *"Notification permission required."* with a "Open Settings" button that deep-links to `UIApplication.openSettingsURLString`.

---

## Technical Approach

- New `NotificationScheduler` — a pure static service struct.  
- Called from `RootView` on `scenePhase == .active`: cancels all pending notifications and reschedules based on current state (queue count, streak, today's reading day).  
- All notifications use `UNCalendarNotificationTrigger` (time-of-day) or `UNTimeIntervalNotificationTrigger(timeInterval: 1)` for immediate rank-up.  
- Background reschedule via `BGAppRefreshTask` — prevents stale notifications from firing if the app isn't opened during the day.  
- Notification categories: plain text only, no reply actions in V1.  
- Streak at Risk fires only if the user hasn't already read today — `StreakEngine.hasReadToday(days:)` check before scheduling.

---

## Acceptance Criteria

- [x] No permission request on cold launch
- [x] Permission request banner shown when streak first reaches 3 days
- [x] Morning Nudge fires at configured time only if queue is non-empty and no reading today
- [x] Streak at Risk fires at configured time only if streak ≥ 1 and no reading today
- [x] Streak Lost fires next morning if applicable
- [x] Rank-up notification fires immediately after reading
- [x] Morning nudge and streak reminder individually toggleable in Settings
- [x] Morning and evening times are user-adjustable
- [x] "Open Settings" deep-link shown when permission is denied
- [x] Rescheduling on app foreground prevents stale notifications
