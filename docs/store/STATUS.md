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

## Physical-device follow-up

2026-10-12: signed Release installed on an iPhone 16 Pro Max running iOS 26.2,
using the owner's existing entitlement file only as a build override. No capability
file or provisioning setting was changed. A private backup of Documents/Library is
retained outside Git in the Mac's ParkSignal application-support folder.

- Every pre-upgrade model ID remained in the upgraded store; counts were unchanged
  (8 spots, 1 car, 14 sessions, 4 scans, 10 restrictions and 1 current-parking record).
  The owner confirmed saved spots and photos remain visible. Three referenced
  PhotoBlob rows were created by backfill.
- Settings reported **iCloud transfer completed**; Alerts showed Notifications
  Allowed and System Alarms Authorized. This is one-device evidence, not proof that
  the records/photos arrive on a second device or that Production schema is ready.
- The Release active-alarm list opened and showed no active alarms. Reminders were
  off on this device. Alarm firing/cancellation with a real scheduled event remains
  unverified in this session.
- Fixed a device-only unreachable-code compiler warning in CloudKit configuration.
  CI now also compiles unsigned physical-device Release, so simulator-only checks
  cannot miss this branch again. Signed device Debug/Release and simulator Debug
  passed with compiler warnings treated as errors before this follow-up was committed.
- Added a production **Enable System Alarms** permission action. Previously the only
  request path was inside DEBUG test controls. The Release screen displays the live
  permission state and retains notification fallback.

On 2026-10-12 the owner authorized uploading **when ready**. Preparation may proceed;
readiness gates still apply. No App Store upload, schema deployment or public release
has occurred. The phone remains on the Release candidate. The proposed temporary
Debug installation for a 10-second diagnostic alarm was rejected by automatic
approval review and did not execute.

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

## Distribution preparation follow-up — 2026-10-12

The owner explicitly authorized automatic provisioning after the first attempt was
rejected by automatic approval review. Xcode exported version 1.0/build 2 to a local
IPA using a matching App Store profile (team EU6247328G, debugging disabled, no
device-limited list). Export requested the Production CloudKit environment. The
archive/package remain outside Git, and no App Store upload has occurred. Build 2
is provisional until existing App Store Connect builds are checked.

The current Release photo-picker/OCR/review path displayed Monday–Friday,
09:00–18:00 and a separate 120-minute maximum stay from the labeled sample sign.
Save Rules remained disabled before confirmation. This does not yet prove the
completed save or alarm delivery. Simulator resizing briefly restored control;
intermittent window/time-out errors returned during the confirmation scroll.

Production schema, two-device sync, delivery/cancellation, full accessibility and
the final screenshot set remain release gates. The owner's phone was not used
for this follow-up.

## CloudKit schema inspection — 2026-10-13

The owner signed into Safari. CloudKit Console confirmed the correct team and
container. Development had seven application record types; the production preview
proposed creating all seven, their indexes and standard role grants. Production
has not yet received these application types. The preview was dismissed without
Deploy. `CD_CurrentParking` was missing `CD_spotID` despite the property existing
in the app model: the automatically observed schema is incomplete.

Prepared an explicit Debug-only `-InitializeCloudKitSchema` tool following Apple's
SwiftData/Core Data procedure. It generates the complete model using the app's
shared type list and uses a separate temporary local store. Release excludes the
initializer. It has not been run against CloudKit or installed on the phone.
Local validation: 121 unit tests passed (132 parameterized executions), no failures
or skips, plus an unsigned physical-device Release build with compiler warnings
as errors. Original dirty entitlements are byte-for-byte unchanged.

See `CLOUDKIT_SCHEMA_INITIALIZATION.md` for the controlled owner-assisted run,
field verification and deployment steps. Do not deploy the incomplete preview.
The previous exported IPA remains tied to commit 6001c85; rebuild/archive the final
verified source before eventual upload. No upload or public release occurred.
