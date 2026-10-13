# Sign interpretation corpus

`sign_corpus.json` contains 42 curated text transcriptions/patterns. This is a
parser regression corpus, not a measured photographic OCR accuracy study.

There are two acceptance classes:

- `requiresReview: false`: every expected type, weekday, hour and maximum duration
  must match, and the result must not require review.
- `requiresReview: true`: the weekly model cannot represent the full condition.
  The result must be nonempty, every rule must require review, and its signal must
  be gray. The text remains available for manual review; no automatic reminders.

The current split is 30 supported patterns and 12 intentionally unresolved patterns.
The latter cover monthly/date/holiday/exemption/loading conditions; they are not
counted as correctly interpreted signs. “42/42 correct or explicitly unresolved”
is a safety acceptance result, not 100% interpretation accuracy.

No failing-case exemption is allowed. CI fails on an incorrect supported parse or
an unsupported sign that loses its review state. Add a documented `source`, unique
`id`, `ocrText`, expected rules and `requiresReview` for each regression. Only mark
review-required for a genuine unsupported condition, not to conceal a bug in a
supported weekly pattern. For image fixtures, record permission/source and add
`image` instead of `ocrText`; OCR then runs through Vision.

`ParserCorpusTests` prints per-case PASS/REVIEW/FAIL and a summary. CI includes this
report in its job summary when the test-runner output path is available. Additional
unit tests cover ambiguity, durations, DST/time zones, saved review states and
reminder suppression; the corpus does not replace field testing.
