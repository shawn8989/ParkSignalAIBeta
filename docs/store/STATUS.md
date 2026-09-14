# v1 Submission-Prep — Status

Progress on the autonomous submission-prep goal. Owner-only shipping steps live in
**`SUBMISSION_CHECKLIST.md`**; this file tracks the engineering work.

_The initial arc (items 1–6, PRs #7–#17) ran with the machine's disk ~100% full, so
those were verified via **GitHub Actions CI**. The later audit arc (#18–#24) ran after
the disk was freed, so each was built + unit-tested locally and re-checked 0-warnings
via CI._

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
- **6. Accessibility (on-device visual pass)** — PR #17. Ran the app in the iOS
  Simulator at the **largest accessibility Dynamic Type size (AX5)** and fixed the
  truncation found: the onboarding page now scrolls (subtitle no longer clips), and
  the Dashboard "City Data Active: …" and "My Curb Signal: …" rows use
  `.fixedSize(horizontal: false, vertical: true)` so they wrap and show in full.
  Settings/Form screens already wrap correctly; standard nav/tab controls meet the
  44pt target; contrast checked on the signal surfaces.

## v1.1 quality pass — audit-driven (2026-09-13/14)

A 12-agent code audit (`docs/AUDIT.md`, 83 findings) drove a second arc fixing the
core correctness bugs. Local builds are back (disk freed) — each PR was built + unit-
tested locally on the iOS 18.6 simulator and re-verified 0-warnings via CI.
**All five high-severity clusters are shipped.**

- **Parser v2** — PR #18 (merged). Exceptions/negation ("except weekends" → Mon–Fri),
  weekday/weekend macros, MON THRU/THROUGH FRI, multiple time windows, spelled-out
  durations, broader types (no standing/stopping/tow/bus/loading/ADA), stacked-sign
  handling, + `AIRestriction.needsReview`/`.exceptHolidays`. Cloud AI stays fallback.
- **Alarm lifecycle** — PR #19 (merged). Edit/delete restriction + delete spot now
  cancel/reschedule alarms; park alert fires `leadMinutes` BEFORE the restriction;
  fixed the CarListView no-op cancel id.
- **Confirm-before-schedule** — PR #20 (merged). `AnalysisConfirmationView` is editable
  (type/days/times) and surfaces `needsReview`; QuickScan (Dashboard) routed through it
  instead of auto-committing with no alarm.
- **Overnight eval** — PR #21 (merged). New `DateTimeUtils.isWindowActive` (checks
  today+yesterday) fixes the after-midnight false-GREEN; consolidated 5 duplicated
  `isActive` copies; `daysMask==0` = every day everywhere.
- **Driving-side / dedup** — PR #22 (merged). Curb side inferred from address parity;
  `SpotMergeService` dedups by street + proximity + side (opposite sides never merge,
  no more duplicate pins, coordinate not overwritten).
- **Photo sync** — PR #23 (**OPEN — review**). `PhotoBlob` external-storage model syncs
  photo bytes via CloudKit; rehydrates on a cache miss. Left open because it adds a
  CloudKit schema field (owner's call; include it when deploying Dev→Prod).
- **Re-analysis alarm cleanup** — PR #24 (**OPEN — review**). Re-analyzing a scan now
  cancels the old restrictions' alarms before deleting them (no orphaned notifications).

Tests grew to **95** (unit-only, all green, 0 warnings).

## Remaining / deferred

### From the audit (`docs/AUDIT.md`) — medium/low, not yet done
- **Alarm/restriction integrity (batch A):** alarms aren't re-established after iCloud
  sync or relaunch (only scheduled at scan/edit time); in-spot Re-Analyze appends
  duplicate restrictions (needs a replace-vs-add decision); editing OCR + Save (not
  Analyze) leaves restrictions stale; changing lead time doesn't reschedule;
  `currentDeviceCoordinate()` uses a throwaway `CLLocationManager` (often nil);
  `deleteSpot` orphans photo files (quick once #23 lands); off-main SwiftData access in
  a notification completion handler.
- **Parser depth (batch B):** nth-weekday-of-month ("1st & 3rd Tue") is unsupported —
  the biggest parser gap (needs a model concept + eval + alarm support); wire
  `needsReview` into the review screen (earlier correction point).
- **Map/segment editor (batch C):** heading never captured (curb-ribbon left/right is
  parity-approximated); MapView renders every scan globally; segment-editor bugs
  (drag force-sets side to "right", Cancel doesn't roll back, all handles at once,
  overshoot, overlapping gestures).
- 15 low-severity polish items (dead code, cosmetics, minor UX).

### Original goal
- **6. Accessibility (minor cosmetic left):** at the very largest accessibility
  text size the Dashboard **map legend overlay grows large and overlaps** the map /
  the "City Data Active" line — everything is still fully readable (no truncation),
  but the legend could be capped, collapsed, or made scrollable at huge sizes. That's
  a design choice worth your eye, so it's left as polish rather than guessed at.
- **7. Phase 3 scaffolding (StoreKit paywall + AI proxy client)** — stretch; not
  started (deferred to keep spend in priority order; also needs product IDs / a
  proxy endpoint which are owner/infra decisions).

## Next steps (recommended order)
1. Review + merge the open PRs: **#23 photo sync** (acknowledge the CloudKit schema
   field) and **#24 re-analysis alarm cleanup**.
2. **Batch A (alarm/restriction integrity)** — highest value; makes alarms trustworthy
   on a real device (reconcile alarms on launch/after sync, re-analysis dedup, lead-time
   reschedule, real device coordinate, deleteSpot photo cleanup).
3. **Batch B — nth-weekday parser support** (street-cleaning is a core use case).
4. Batch C (map/segment editor + heading capture) and the low-severity polish.
5. Owner steps in `SUBMISSION_CHECKLIST.md` (Push decision → create/deploy CloudKit
   schema → host pages → ASC record → archive → submit).
6. (Post-launch) Phase 3 monetization (StoreKit + AI proxy).

_The full ranked backlog is in `docs/AUDIT.md`._
