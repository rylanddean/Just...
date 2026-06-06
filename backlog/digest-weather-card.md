# Digest Weather Card

**Tier:** Free  
**Effort:** S  
**Status:** Backlog

A quiet weather card sits at the top of the Digest — today's high, today's low, and one calm reading suggestion tuned to the conditions outside.

---

## The Problem

The Digest is a daily reading surface, but it has no awareness of the day. A grey rainy morning and a bright Saturday afternoon ask for different reading moods. The card acknowledges the world outside without making a show of it.

This is not a weather app. It is a gentle nudge that makes the Digest feel like it knows what day it is.

---

## Experience

### The Card

A single card appears above all article sections — above topic chips if present, below the navigation bar. It spans the full content width, styled like any other `surface` card.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FRIDAY · PARTLY CLOUDY
  18° / 9°
  A good day to read outside.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TODAY
  …
```

- **Date line:** Day name + condition, in `.label` style — DM Mono, all-caps, `muted`.
- **Temperature line:** High and low in `cream`, Playfair Display `headline` weight.
- **Suggestion line:** One calm sentence in DM Mono `mono`, `muted`. No punctuation beyond the period.
- The card is hidden if location permission is denied or the weather fetch fails. No fallback, no error state shown to the user.
- The card shows once per day. After the first successful load it is cached until midnight.

### Suggestion Copy

One suggestion per condition category. Never more than one sentence. No emoji.

| Condition | Suggestion |
|-----------|-----------|
| Sunny, warm | "A good day to read outside." |
| Sunny, cool | "Clear skies. A good day for a long read." |
| Partly cloudy | "Good light for reading." |
| Overcast | "A quiet day. Plenty of time to read." |
| Rainy | "A good day to stay in and read." |
| Heavy rain / storm | "Nowhere to be. A good day to read more." |
| Snow | "Slow day outside. A good day for something long." |
| Very hot | "Stay inside. Good reading weather." |
| Very cold | "Stay warm. A good day to read something long." |
| Windy | "A good day to settle in with something." |

Rules:
- Never say "weather" in the suggestion copy.
- Never say "it looks like" — state it plainly.
- The suggestion never references a specific article or feed.
- Suggestions rotate once per day, not per app launch.

---

## Technical Approach

### Data Source

Use `WeatherKit` — already available under the existing HealthKit entitlement umbrella. Request `.current` and `.daily` forecasts. No third-party API keys required.

```swift
let weather = try await WeatherService.shared.weather(
    for: location,
    including: .current, .daily
)
let todayForecast = weather.daily.forecast.first
let high = todayForecast?.highTemperature
let low  = todayForecast?.lowTemperature
let condition = weather.current.condition
```

Request location via `CoreLocation` at `.whenInUse` accuracy. If the user has not granted location permission, the card is silently omitted — no permission prompt from within the Digest.

### DigestWeatherCard View

A new `DigestWeatherCard` view owned by `DigestView`. Receives a `DigestWeather` value type:

```swift
struct DigestWeather {
    let condition: WeatherCondition
    let high: Measurement<UnitTemperature>
    let low: Measurement<UnitTemperature>
    let weekday: String          // e.g. "Friday"
    let conditionLabel: String   // e.g. "Partly Cloudy"
}
```

`DigestWeatherViewModel` (or an extension on the existing digest view model) fetches and caches this value. Cache key: calendar date. On cache hit, no network call.

### Placement in DigestView

```swift
VStack(spacing: 0) {
    if let weather = viewModel.todayWeather {
        DigestWeatherCard(weather: weather)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 12)
    }
    if availableTopics.count > 1 {
        topicFilterBar
    }
    // … rest of digest
}
```

### Permissions

No new permission prompts are added to the Digest flow. If `CLLocationManager.authorizationStatus` is `.authorizedWhenInUse` or `.authorizedAlways`, fetch proceeds. Otherwise the card is omitted.

If the user grants location for another Just… feature in future, the card appears automatically on next Digest load.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Calm, no pressure | ✅ — One line, no urgency, never gamified |
| Acknowledges the day without demanding attention | ✅ — Card is quiet, not a hero banner |
| No emoji | ✅ — Text only |
| No exclamation points | ✅ — Suggestions are declarative statements |
| Fails silently | ✅ — No card if location or weather unavailable |
| Consistent typography | ✅ — `.label`, `headline`, `.mono` only |
| Consistent colour | ✅ — `surface`, `cream`, `muted` — no new tokens |
| Respects "now go live your life" | ✅ — Encourages going outside when weather permits |

---

## Copy Reference

| Element | Copy |
|---|---|
| Date label format | "FRIDAY · PARTLY CLOUDY" |
| Temperature format | "18° / 9°" (high first, low second, unit from system locale) |
| Suggestion: sunny warm | "A good day to read outside." |
| Suggestion: rainy | "A good day to stay in and read." |
| Suggestion: overcast | "A quiet day. Plenty of time to read." |
| Suggestion: snow | "Slow day outside. A good day for something long." |
| Suggestion: very hot | "Stay inside. Good reading weather." |

---

## Acceptance Criteria

- [ ] Weather card appears at the top of `DigestView` when location permission is granted and WeatherKit returns data
- [ ] Card shows weekday, condition label, high/low temperature, and one suggestion line
- [ ] Card is silently omitted when location is unavailable or the fetch fails — no error shown
- [ ] Weather data is cached per calendar day — no re-fetch on re-open within the same day
- [ ] Suggestion copy matches the condition table exactly — no ad-lib generation
- [ ] Temperature respects system locale (°C / °F)
- [ ] Card uses only existing `AppTheme` colour and type tokens — no new tokens introduced
- [ ] No new location permission prompt is triggered from within `DigestView`
- [ ] Card appears above topic filter chips when both are present
