# v1 Submission-Prep — Status

Progress on the autonomous submission-prep goal. Owner-only shipping steps live in
**`SUBMISSION_CHECKLIST.md`**; this file tracks the engineering work.

_Constraint during this run: the machine's disk was ~100% full (≈1–2 GB free), so
local Xcode builds were avoided; correctness was verified via **GitHub Actions CI**
(`Build & Unit Test`), which builds and runs the unit tests on GitHub's runners._

## Done (merged to `main`)

- **1. Test coverage** — PR #7. Added 4 unit-test files (~40 new cases; 61 total,
  all green in CI): the curb-signal engine (`ParkingSignalEvaluator`, both
  `[Restriction]` and `AIAnalysisResponse` overloads), `DateTimeUtils`, more
  `ParkingTextParser` edge cases, and a SwiftData model round-trip (relationship
  integrity + defaults + `daysOfWeek` bitmask) in an in-memory store.
- **3. Submission checklist** — PR #8. `SUBMISSION_CHECKLIST.md` with the ordered
  owner-only steps.
- **4. Legal/support pages** — PR #8 (pages) + this PR (in-app links).
  `docs/legal/privacy.html` + `support.html` (host-ready, `{{SUPPORT_EMAIL}}` /
  `{{EFFECTIVE_DATE}}` placeholders). Settings now has an **About** section linking
  to both (URL constants in `SettingsView`, default to the GitHub Pages path) plus
  a Version row.
- **5. Metadata polish** — PR #8. `APPSTORE.md`: 1.0 "What's New", URLs pointed at
  the new pages, corrected capabilities/screenshot notes (iPhone-only, CloudKit
  shipping, Push pending, skip the DEBUG-rows screenshot).
- **2. Zero warnings** — PRs #9, #11, #12, #14. **The tree now builds with 0
  compiler warnings** (confirmed by grepping the CI build log: 19 → 0).
  - #9: mechanical (`var`→`let`, unused bindings, an unreachable `catch` → real
    `try` save, deprecated `Locale.regionCode`, a `Sendable`-crossing via a `Void`
    closure).
  - #11: all 14 `onChange(of:perform:)` → iOS 17 two-parameter `onChange`, and
    `Map(coordinateRegion:)` → `Map(initialPosition: .region(…))`.
  - #12: dropped redundant `await` on the non-async `AlarmManager.cancel(id:)` calls.
  - #14: Swift-6 concurrency — marked pure value types / `DateTimeUtils` `nonisolated`
    (the target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), `nonisolated` on
    the `CGImagePropertyOrientation(_:)` init, `MainActor.assumeIsolated` in the
    `.main`-queue NotificationLog observer, and made the scan-save `Task`s
    `@MainActor` so SwiftData models no longer cross an actor boundary.
  - All behavior-preserving.
- **6. Accessibility (code portion)** — PRs #10, #15, #16. Toolbar controls use
  `Label` (accessible names), the Settings gear has an explicit `accessibilityLabel`,
  map annotations carry labels, a Version label was added, and the color-only signal
  icons that duplicate an adjacent text label are now `accessibilityHidden(true)`
  (Dashboard, AnalysisConfirmation, ParkingSpotDetail, live scanner). #16 also:
  contrast — the colored status labels in `CarListView` now use `.primary` text
  (the color cue stays on the adjacent dot); Dynamic Type — every truncation-prone
  `lineLimit(1)` label gained `.minimumScaleFactor(0.75)` so text shrinks instead of
  clipping at large sizes.

## Remaining / deferred

- **6. Accessibility (device-only residual):** the code has been hardened
  (labels, decorative flags, `.primary` status text, `minimumScaleFactor`), but the
  final *visual* confirmation still needs the app rendered at the largest Dynamic
  Type sizes, a 44pt tap-target check (mainly the small map-pin markers), and
  measured contrast ratios. These are inherently on-device/visual and can't be done
  from CI — and running the app locally is currently blocked by the full disk. This
  is the one part of the goal that conflicts with its own "no device" constraint.
- **7. Phase 3 scaffolding (StoreKit paywall + AI proxy client)** — stretch; not
  started (deferred to keep spend in priority order; also needs product IDs / a
  proxy endpoint which are owner/infra decisions).

## Next steps (recommended order)
1. On-device accessibility audit (Dynamic Type + tap targets + contrast).
2. The owner steps in `SUBMISSION_CHECKLIST.md` (Push decision → create/deploy
   CloudKit schema → host pages → ASC record → archive → submit).
3. (Post-launch) Phase 3 monetization.

_Note: local Xcode builds were avoided all run because the machine's disk was ~100%
full (≈1–2 GB free); everything was verified via GitHub Actions CI, including a
zero-warning check by grepping the build log. Freeing space (e.g. the regenerable
`~/Library/Developer/Xcode/DerivedData`) restores fast local builds._
