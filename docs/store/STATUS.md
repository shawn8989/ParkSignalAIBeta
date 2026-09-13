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
- **2. Warnings (safe subset)** — PR #9. Removed ~19 low-risk warnings
  (`var`→`let`, unused bindings, an unreachable `catch` → real `try` save, a
  deprecated `Locale.regionCode`, and a `PersistentModel` `Sendable`-crossing via a
  `Void` closure). No behavior change.

## Remaining / deferred

- **2. Warnings (rest)** — not done; needs reliable local builds to iterate safely:
  - **Deprecations (~19):** `onChange(of:perform:)` across many View files
    (DashboardView, MapView, SpotsMapView, SignScanEditView, ParkingSignScannerView,
    AnalysisConfirmationView, SpotPhotosView, SegmentMapEditorView, CarListView) →
    migrate to the two-/zero-parameter `onChange`; and the deprecated
    `Map(coordinateRegion:…)` in `ParkingSpotDetailView` → the `MapContentBuilder`
    initializer.
  - **Swift-6 concurrency (~23):** main-actor-isolated conformances/inits and
    `PersistentModel` `Sendable` warnings in `AIAnalyzerService` (Decodable),
    `VisionOCRService` (init), `NotificationLogStore` (2), `AlarmService`
    (`no async operations within 'await'`, 2), `QuickScanSheet` /
    `ParkingSpotDetailView` (Sendable), and the `DateTimeUtils` calls from the
    non-isolated test suites. These need a considered ModelActor /
    `persistentModelID` / `nonisolated` refactor, not blind edits.
- **6. Accessibility** — largely already covered by the v1-polish pass: toolbar
  controls use `Label` (accessible names), the Settings gear has an explicit
  `accessibilityLabel`, and map annotations carry labels; a Version label was added
  this PR. **Residual (needs on-device verification, not done here):** confirm no
  truncation at the largest Dynamic Type sizes, audit 44pt minimum tap targets, and
  sweep purely-decorative color-only icons for `accessibilityHidden(true)` where
  they duplicate adjacent text.
- **7. Phase 3 scaffolding (StoreKit paywall + AI proxy client)** — stretch; not
  started (deferred to keep spend in priority order).

## Next steps (recommended order)
1. Free disk space so local builds/verification are reliable again.
2. `onChange`/`Map` deprecation migration (mechanical; one PR, verify each closure
   signature).
3. Swift-6 concurrency pass (separate PR; validate with `-strict-concurrency`).
4. On-device accessibility audit (Dynamic Type + tap targets).
5. Then the owner steps in `SUBMISSION_CHECKLIST.md` (Push decision → create/deploy
   CloudKit schema → host pages → ASC record → archive → submit).
