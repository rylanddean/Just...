# Listen Mode

**Tier:** Free  
**Effort:** L  
**Status:** Backlog

Read the stripped article aloud using on-device text-to-speech. The same reading loop — article → reflect window → Brain — applies. Listening counts toward the streak. For users who commute, exercise, or simply prefer ears over eyes.

---

## Why

The stripping pipeline already produces clean, prose-only text. That same text is ideal for TTS — no ads to stumble over, no navigation chrome read aloud. The reflect window is unchanged: after listening, the user still has 60 seconds to capture a thought. The habit holds.

This is not a podcast feature. Just… still strips the article to text. There is no audio file, no narrator, no premium voice pack. It is a reading aid, not a separate product mode.

---

## Experience

### Entry Point

In `ReaderView`, the existing top bar gains a single additional icon: a waveform glyph (`waveform`, SF Symbols). Tapping it starts playback and switches the reader to Listen mode — the article text scrolls to follow the spoken sentence, highlighted in amber.

The icon is visible only after content has loaded. It does not appear during the loading shimmer.

---

### Player Controls

When Listen mode is active, the top bar collapses to a minimal player:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ×    ⟪10    ▶︎ / ‖    1.0×    Done
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  …sentence being read, highlighted…
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **×** — exits Listen mode, returns to the standard reader. Playback position is not preserved.
- **⟪10** — skip back 10 seconds (`goback`, SF Symbols)
- **▶︎ / ‖** — play / pause
- **1.0×** — speed picker: 0.9×, 1.0× (default), 1.25×, 1.5×, 1.75×. Persists in `UserDefaults`. No 2× — at 2× the voice clarity degrades too far for comprehension.
- **Done** — marks the article as read and advances to the reflect window, same as "Done reading" in the standard reader.

The article body scrolls to keep the active sentence centred on screen. The active sentence is highlighted with a `amberDim` background — subtle, not a harsh highlight.

---

### Audio Session

Uses `AVAudioSession.Category.playback` with `.mixWithOthers` unset — meaning Just… temporarily pauses music or podcasts while reading. On audio interruption (incoming call, Siri), playback pauses automatically and resumes when the interruption ends (`AVAudioSession.interruptionNotification`).

Background audio is enabled: if the user locks their screen, playback continues. Now Playing metadata is set on `MPNowPlayingInfoCenter` — article title as the track name, "Just…" as the artist, estimated reading minutes as duration.

Lock screen controls (play/pause, skip back 10s) are wired via `MPRemoteCommandCenter`.

---

### Voice Selection

Uses `AVSpeechSynthesizer` with `AVSpeechSynthesisVoice(language: Locale.current.identifier)`. No voice picker in V1 — the system default is chosen. On iOS 17+, the enhanced neural voices are used automatically when available.

No server requests. All synthesis is on-device.

---

### Reflect Window

When the user taps "Done", the reflect window opens identically to the standard read path. Listen mode is transparent to `ReflectViewModel` — the entry is already created with the article metadata; only the `reflectionMode` will differ if the user speaks their reflection.

A `linksRead` entry is written to `ReadingDay` the same way, so the streak increments.

---

### Sentence Segmentation

`AVSpeechSynthesizerDelegate` fires `willSpeakRangeOfSpeechString` before each utterance unit. The range maps to a character offset in the article body string. `ReaderWebView` receives a JavaScript message to highlight the corresponding sentence (`element.scrollIntoView`, `classList.add("active-sentence")`).

The CSS for the active sentence highlight:

```css
.active-sentence {
  background: rgba(138, 100, 32, 0.35);  /* amberDim at 35% */
  border-radius: 3px;
}
```

Sentence boundaries are determined by splitting on `.`, `?`, `!` followed by whitespace — a simple heuristic that works well for prose. Edge cases (abbreviations like "Dr.", "U.S.") may occasionally over-split, which is acceptable.

---

## Technical Approach

### New: `SpeechPlayer`

```swift
@Observable
@MainActor
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var sentences: [String] = []
    private var currentIndex: Int = 0

    var isPlaying: Bool = false
    var activeSentence: String = ""
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    func load(text: String)
    func play()
    func pause()
    func skipBack()  // rewind 10s worth of sentences
    func stop()

    // AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOf characterRange: NSRange, utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
}
```

`SpeechPlayer` is owned by `ReaderViewModel`. Created lazily on first tap of the waveform button.

### `ReaderViewModel` changes

```swift
var speechPlayer: SpeechPlayer?
var isListenMode: Bool = false
```

`isListenMode` drives the reader UI state — controls bar vs. player bar.

### `ReaderView` changes

- Waveform button in top bar (hidden until `content != nil`)
- Conditional player bar when `viewModel.isListenMode`
- `.onChange(of: viewModel.speechPlayer?.activeSentence)` sends a JS message to `ReaderWebView` to update the highlight

### Background audio entitlement

Add `audio` to the `UIBackgroundModes` array in `Info.plist` (via `project.yml` under `INFOPLIST_KEY_UIBackgroundModes`).

---

## Brand Alignment

| Principle | Check |
|---|---|
| Habit loop unchanged | ✅ — reflect window applies; streak increments |
| No premium gate | ✅ — free for all; TTS is a system API |
| Calm, no pressure | ✅ — no speed competitions, no WPM stats |
| On-device, private | ✅ — AVSpeechSynthesizer is fully local |
| Minimal chrome | ✅ — player replaces the top bar, does not add to it |
| Not a podcast feature | ✅ — still stripped text; no audio files |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Listen button tooltip | (none — icon only) |
| Speed picker options | 0.9×, 1.0×, 1.25×, 1.5×, 1.75× |
| Done button | "Done" |
| Now Playing artist | "Just…" |

---

## Acceptance Criteria

- [ ] Waveform button appears in `ReaderView` top bar after content loads; hidden during loading shimmer
- [ ] Tapping waveform starts TTS and switches to the player bar
- [ ] Player bar shows: ×, skip-back-10, play/pause, speed picker, Done
- [ ] Active sentence scrolls into view and receives `amberDim` background highlight
- [ ] Play/pause works; pause preserves position within the sentence list
- [ ] Skip back rewinds approximately 10 seconds of speech
- [ ] Speed persists across sessions in `UserDefaults`
- [ ] "Done" advances to reflect window and increments streak, same as standard read path
- [ ] Background playback continues when screen is locked
- [ ] Lock screen and Control Centre show article title as Now Playing; play/pause and skip-back work from lock screen
- [ ] Incoming call pauses playback; call end resumes automatically
- [ ] Audio pauses when Just… is backgrounded without lock (e.g. user switches apps) — does not continue over other audio without active NowPlaying session
- [ ] No speech data leaves the device — `AVSpeechSynthesizer` only
- [ ] `UIBackgroundModes` includes `audio` in `Info.plist`
- [ ] × in player bar exits Listen mode and returns to standard reader without advancing to reflect
