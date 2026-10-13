# Free v1 implementation status

Updated 2026-10-12. **Submission is still gated on owner verification.** The selected
product is free, with no ads, purchases or OpenAI requirement. This file supersedes
older “code ready” claims and the 24/42 corpus baseline.

## Integrated implementation

Branch `codex/free-v1-release` combines #23 (photo sync), #24 (alarm cleanup) and
#25 (session service/refactor/corpus). Original merge commit: `927aea5`. The combined
behavior/schema changes are offered in [PR #26](https://github.com/shawn8989/ParkSignalAIBeta/pull/26), not automatically merged.

- Local-only sign interpretation; the direct OpenAI service is removed. Branding
  remains intact. No payment or advertising SDK was added.
- Durations survive alongside time windows. Weekday/holiday exceptions, meridiem
  inference and multiple rules have regression coverage. Unsupported monthly,
  seasonal, holiday, loading and exemption conditions retain review-required state.
- Confirm/correct before committing scan rules; cancelling review preserves existing
  rules. Re-analysis replaces only that scan's rules. Editing OCR invalidates old
  interpretations. Unknown/unresolved conditions do not produce green or reminders.
- Fake city-rule import is removed; Release city overlays/data are empty. Old rows
  migrate conservatively as needing review. Onboarding/listing no longer promise
  legal certainty or that users can never get a ticket.
- One device-local reminder coordinator reconciles edits, deletions, re-analysis,
  relaunch, synced saves and lead-time changes. Device opt-in is local. Cancelled
  and delivered occurrences are not recreated; explicit restore is available.
  Failed cancellations retain ownership for retry, including when restoring a
  cancelled reminder. Concurrent synced sessions select the newest per car.
  All-day duration limits do not reset at midnight.
  Reminders cover the next 14 days, capped at 48 upcoming events. Permission errors
  are visible; enabling within the lead window still schedules promptly.
- Every persisted relationship is optional, preserving original field names.
  A real file-store migration test preserves the old graph and photo bytes.
  Referenced older files are backfilled into PhotoBlob; cache rehydration and owned
  scan/rule/photo deletion are covered.
- Local-only/failing storage is visible. An unreadable store shows recovery guidance
  without deleting data. Unsigned simulators use local storage; signed hardware
  keeps the CloudKit configuration. A signed simulator can explicitly opt in.
- Save errors are surfaced, advanced geometry is collapsed, key confirmation/day
  controls have accessible labels, and times are reviewed in the spot's saved zone.
  A scan from a saved spot stays attached to that spot. Unchecking an unsupported
  proposal cannot silently clear its source sign's unresolved conditions.
- Large accessibility text uses a compact map with a separate scrollable legend,
  stacked spot-row actions and wrapping labels. Gray status badges use primary
  text for contrast. The map filter excludes unresolved spots.

## Verified locally

- Xcode 26.6; iOS 18.6 iPhone 16 Pro simulator.
- Debug unit suite: **120 tests passed**, 0 failed/skipped (131 parameterized executions).
- The 42-case corpus: **30 correctly interpreted supported patterns + 12 explicitly
  unresolved patterns**. No known-failure exemptions. This is not a claim of 100%
  real-world sign or photographic OCR accuracy.
- Debug and Release compile with Swift/C warnings treated as errors.
- Migration, optional relationship schema, scan replacement, photo cleanup,
  reminder idempotence/cancellation/denial, multiple cars, time zones and DST tested.
- Owner's original dirty entitlement SHA-256 remains
  `0bc905b9bcd36669ee3e75e7e0c1a68e12b4d0546141cea32186134cf2542bd9`.

## Public pages

Privacy and support are live (HTTP 200) at:

- https://shawn8989.github.io/ParkSignalAIBeta/legal/privacy.html
- https://shawn8989.github.io/ParkSignalAIBeta/legal/support.html

Published from `gh-pages` commit `0772ceedb8861950f6cde55e858c7476dcdf8e4f`.
Source copies: `docs/legal/`. Policy describes private CloudKit records/photos,
Apple Maps/address lookup, local interpretation and device-specific reminders.
The support channel is public GitHub issues; do not post private parking details.

## CI and visual verification

[PR #26 checks](https://github.com/shawn8989/ParkSignalAIBeta/pull/26/checks) run the
unit suite and both build configurations on the integrated branch. The first
combined code commit `1701654` passed [CI run 38340050512](https://github.com/shawn8989/ParkSignalAIBeta/actions/runs/38340050512).
The follow-up adds cancellation retry/restore, duplicate-session and multi-day-limit
coverage plus scan and accessibility refinements. Verify the latest PR commit's
check before merging; an earlier green run does not certify a later change.

Native Release screenshots and the capture manifest are under `screenshots/`.
The saved-spot/draft-scan data survived relaunch. A synthetic sign image was selected
through the photo picker and recognized by Vision; the review displayed its two-hour
rule and 09:00–18:00 window. This is a controlled OCR smoke check, not field accuracy.
The end-to-end confirmation/save and subsequent reminder UI still need a complete pass.

The largest accessibility text setting exposed legend overlap, which was corrected.
Dashboard default-text and large-text/dark-mode captures are recorded. Full VoiceOver,
remaining screen layouts and the final Map/review/alarms marketing captures remain
**incomplete**: Simulator control repeatedly returned `noWindowsAvailable` even while
native screenshot capture worked. No Apple-account step is needed to finish these
checks; resume when simulator UI control is available. Historical DEBUG screenshots
must not be uploaded. See `screenshots/MANIFEST.md` for exact capture status.

## Owner release gates

`SUBMISSION_CHECKLIST.md` gives the ordered steps. Required: review the integration,
reconcile the preserved Push/signing decision, demonstrate authenticated two-device
sync including photos and existing-data upgrade, deploy Development schema to
Production, test on TestFlight/hardware, approve accurate privacy/listing answers,
then archive/upload/submit. No Apple-account actions or credential changes were made.

Physical camera quality, AlarmKit delivery and real CloudKit transfer have not been
certified by simulator/unit tests. TestFlight should include real signs, offline and
denied permissions, overnight limits, cancellations and multiple devices. No date
is promised until these checks pass. Later paid Smart Scan remains out of v1.
