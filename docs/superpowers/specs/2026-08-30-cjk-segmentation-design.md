# NotchLyrics — CJK Segmentation & Romanization

**Date:** 2026-08-30
**Status:** Approved for planning
**Builds on:** `2026-08-30-notch-lyrics-design.md`

Fixes word tracking for CJK lyrics, and optionally displays them romanized.

---

## 1. Verified Findings

### 1.1 Word tracking is currently broken for CJK, not merely rough

CJK scripts have no spaces, so `LRCParser`'s space split yields roughly one
"word" per line. Measured against LRCLIB entries:

```
Pretender (Japanese script)   73 words / 55 lines  = 1.3 per line
As It Was (English)          237 words / 39 lines  = 6.1 per line
```

The whole line lights at once. This is a defect in existing behaviour, not a
missing feature.

### 1.2 LRCLIB's Japanese coverage is inconsistent

Some entries arrive already romanized, some in native script:

```
Pretender  kana=74% kanji=24% latin=0%    -> native script
Idol       latin=95%                      -> already romaji
Gurenge    latin=99%                      -> already romaji
```

So processing must trigger on detected script, never unconditionally.

### 1.3 CFStringTokenizer solves segmentation and romanization together

Verified on the target machine, from a pure-Foundation library target with no
AppKit import — so it can live in `NotchLyricsCore` and be unit-tested.

```
今日[kyou] は[ha] 良い[yoi] 天気[tenki] です[desu] ね[ne]
カタカナ[katakana] と[to] ひらがな[hiragana] の[no] 混在[konzai]
```

Density on 13-character sentences: space split 1.0 words, tokenized **8.6**.
That is better granularity than English averages.

### 1.4 CFStringTransform is the wrong API

`CFStringTransform(kCFStringTransformToLatin)` returns Chinese readings for
kanji — `東京都` becomes "dōng jīng dōu" rather than "toukyouto". Plausible
looking and completely wrong. Must not be used.

### 1.5 Known quality limits

- Grammatical particles romanize by spelling: は→"ha" (said "wa"), を→"wo"
  (said "o"). Standard wāpuro romaji; accepted.
- Tokenization splits grammatically, so verb endings become separate tokens
  (`kazoe / te / iru`). Correct, but finer than a singer phrases it.
- Unusual kanji compounds and names can take the wrong reading.

---

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Segmentation | Always, for detected CJK | §1.1 is a bug; tracking must work regardless of display choice |
| Romanization | On by default, toggleable | What the user asked for; some may prefer native script |
| Detection | ≥20% of a line's non-space characters are Han/Kana/Hangul | §1.2 — must not touch already-romaji entries |
| Timing weight | Romaji length | Kanji are dense: 音楽 is 2 chars but 6 syllables |
| Scope | Japanese, Chinese, Korean | Same no-spaces problem, same API |
| Cache | Schema bumps to 5 | Stored documents hold the old one-word-per-line split |

### Non-goals

- Particle-aware romanization (は→"wa")
- Merging grammatical suffixes into stems
- Translation

---

## 3. Architecture

`CJKSegmenter` (core, Foundation only) exposes:

```swift
public enum CJKSegmenter {
    public static func isCJK(_ text: String) -> Bool
    public static func segment(_ text: String) -> [Segment]   // token + romaji
}
```

`LRCParser` asks it whether a line is CJK. If so it uses the returned tokens
instead of splitting on spaces, storing romaji in `WordToken.text` and the
source token in `WordToken.original`. Non-CJK lines are untouched.

`WordToken` gains `original: String?`. The view shows `text` normally, or
`original` when romanization is switched off — so toggling needs no refetch.

---

## 4. Error Handling

| Condition | Behaviour |
|---|---|
| Tokenizer returns nothing | Fall back to the space split |
| A token has no Latin transcription | Keep the source token as its own text |
| Mixed-script line (English inside Japanese) | Per-token: Latin tokens pass through unchanged |
| Non-CJK line | Untouched, existing path |

---

## 5. Testing

Unit, no network or UI:
- `isCJK` — Japanese, Chinese, Korean, English, romaji, mixed, empty
- `segment` — token counts, romaji output, Latin passthrough, punctuation
- `LRCParser` — a CJK line yields many words not one; a Latin line is unchanged;
  `original` populated only for CJK
- `WordTimingEstimator` — weighting uses romaji length

All fixtures use neutral sentences, never song lyrics.
