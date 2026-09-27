# Parking-sign corpus

`sign_corpus.json` is the accuracy benchmark for the on-device parser (`ParkingTextParser`).
`ParserCorpusTests` runs every entry on each CI run and prints one line per sign:

```
CORPUS|PASS|sf-street-cleaning-tue|expected: …|actual: …
CORPUS|SUMMARY|31/42 signs parsed correctly (73.8%)
```

- `PASS`: the parser output matches.
- `KNOWN`: a known failure (`"knownFailing": true`), so it doesn't fail the build.
- `FAIL`: a regression. The test fails and CI goes red.
- `NOW-PASSING`: lists known failures that started passing; set `knownFailing` to `false` so they stay fixed.

To find the table in CI, open the **Build & unit test** step log and search for `CORPUS|`.

## Adding a real sign

The seed entries are typed-in wording of common US signs. The benchmark only becomes trustworthy with real photos, and **50–100 of them** is the goal.

1. Photograph the sign straight on and crop it to the sign.
2. Save it here as a JPEG with a unique name, e.g. `test2Tests/Corpus/nyc-bk-atlantic-ave-01.jpg`. Files are bundled automatically, but **flat**: names must be unique across the whole test bundle.
3. Add an entry:

```json
{
  "id": "nyc-bk-atlantic-ave-01",
  "source": "NYC",
  "image": "nyc-bk-atlantic-ave-01.jpg",
  "expected": [
    { "type": "no_parking", "days": [1, 2, 3, 4, 5], "start": "07:00", "end": "10:00" }
  ],
  "knownFailing": false,
  "notes": "Brooklyn, Atlantic Ave northside"
}
```

With `image` set, the test runs Vision OCR on the photo first. That tests the whole pipeline, not just the parser. You can also give `ocrText` alone, e.g. text copied from the app's "Last OCR" section.

## Writing `expected`

Write what the sign **means**, not what the parser currently returns.

| Field | Rule |
|---|---|
| `type` | `street_cleaning`, `no_parking` (also no standing/stopping, tow-away, loading, fire lane), `metered` (paid or time-limited), `permit` (permit/resident/accessible), `other` |
| `days` | 0 = Sunday … 6 = Saturday. `[]` = every day. |
| `start`/`end` | `"HH:mm"` 24-hour. Leave both out for "anytime". Overnight windows keep `end < start`. |
| `durationMinutes` | For time limits ("2 HOUR PARKING" → 120). Only checked when present. |
| `exceptHolidays` | `true` when the sign excepts holidays. Only checked when present. |

If the parser gets a new sign wrong, set `"knownFailing": true` and describe the gap in `notes`. The entry then tracks the gap without breaking CI.
