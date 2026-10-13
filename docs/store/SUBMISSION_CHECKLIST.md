# Free v1 release gates

This is a candidate, not a certified release. Complete every gate before submission.
The integrated implementation is on `codex/free-v1-release`; see `STATUS.md` for
build evidence and the PR. Do not archive an older branch by mistake.

## 1. Review the integration and preserve signing changes

- Review the integration PR against main. It includes #23–25 plus parser,
  confirmation, reminder, migration and release-copy fixes. It changes behavior
  and the persistent schema, so it is intentionally left open for review.
- Keep the original `test2` checkout's uncommitted `test2/test2.entitlements` safe.
  It was not edited or committed by this work. Bring the owner's chosen capability
  settings into the final release branch separately.
- Xcode → target test2 → Signing & Capabilities: verify team `EU6247328G`, bundle
  `com.SOTech.ParkSignalAI`, iCloud/CloudKit container
  `iCloud.com.SOTech.ParkSignalAI`. Reconcile Push Notifications and Background
  Modes → Remote notifications with the intended CloudKit configuration and profile.
  This work does not change Push, entitlements, provisioning or account settings.
  Do not claim background synchronization until it has been tested.

## 2. Verify a signed build and existing-data upgrade on hardware

Use a development device signed into the owner's iCloud account. Keep its existing
data; do not delete the app to work around a migration error. Build/run the candidate
from Xcode, open Settings → Storage & Sync and check status. A local-only message
must be resolved before advertising sync. “iCloud available” alone is not proof
of an upload.

Unsigned simulators deliberately use local storage, avoiding a framework trap
when CloudKit entitlements are absent. For an actually signed, iCloud-authenticated
simulator only, add the launch argument `-EnableCloudKitSimulator` in Scheme →
Run → Arguments. Do not add it to unsigned CI runs. A signed physical device uses
CloudKit by default.

## 3. Verify Development sync on two devices — required

1. On device A, save a spot, a car, a reviewed rule and a sign/street photo; park.
2. On device B, with the same iCloud account, verify records, relationships and
   full photo images arrive. Confirm reminders are off until enabled on B.
3. Edit a rule and end parking on A. Confirm B receives the change and updates its
   own reminders if enabled. Delete a scan and confirm its rules disappear.
4. Relaunch both apps; verify data remains. Test offline edits, reconnection and
   permissions denied. Confirm existing data upgrades without loss.
5. Record device/OS/build and observations. In-memory tests and an available
   account do not demonstrate a real CloudKit transfer.

## 4. Deploy the CloudKit schema

Open [CloudKit Console](https://icloud.developer.apple.com/), select the correct
team and `iCloud.com.SOTech.ParkSignalAI`, then Development → Schema/Record Types.
After the signed app exports test data, check its SwiftData `CD_*` record types,
including PhotoBlob and the review/duration/time-zone fields. If none appear,
inspect Xcode's CloudKit logs and account/container configuration first.

Use the console's **Deploy Schema Changes** action, review the Development →
Production changes, then deploy. This is an owner action. TestFlight and App Store
builds use Production; perform the two-device test again with TestFlight before
shipping. Schema deployment does not copy private test records into Production.

## 5. Real-world validation in TestFlight — about one week

- Photograph real signs in ordinary and poor lighting. Confirm OCR, days, hours,
  separate maximum duration and original text. Reject suggestions that omit rules.
- Monthly, seasonal, holiday and exemption signs must remain “Review required”
  and never silently show green or schedule automatic reminders.
- Test manual corrections, cancelling review, re-analysis, photo rehydration,
  multiple cars and deleting a parked car/spot.
- Verify a short hardware alarm and a normal scheduled reminder; test denied
  permissions, cancelled alarms, lead-time changes, relaunch and synced changes.
- Reminders use a rolling 14-day window capped at 48 upcoming events. Open the app
  to extend it. Verify the limitation is acceptable for intended use.
- Verify overnight/DST behavior where applicable, VoiceOver, large text and dark
  mode on the supported devices. Simulator checks are not a hardware guarantee.

## 6. Review public pages and listing

The following pages are published and were HTTP 200 on 2026-10-12:

- [Privacy](https://shawn8989.github.io/ParkSignalAIBeta/legal/privacy.html)
- [Support](https://shawn8989.github.io/ParkSignalAIBeta/legal/support.html)

Source is `docs/legal/`; hosting uses the separate `gh-pages` branch. Update both
when changing policy copy. Support currently uses public GitHub issues; confirm
that channel is monitored. No fabricated support email is published.

Use `APPSTORE.md` for listing copy. Review the new Release captures and screenshot
manifest; do not upload the historical DEBUG capture or stale earlier screens.
The target is iPhone-only. Check Apple's current screenshot slots before uploading.

## 7. App Store Connect setup — owner

Apps → + → New App: iOS, ParkSignal AI, English, the bundle ID above, an owner-chosen
SKU. Set free pricing. No ads, subscriptions or in-app purchases are part of v1.
Paste the listing and public URLs; upload the approved screenshot set.

Complete App Privacy using the actual release data flows and Apple's definitions.
Private CloudKit records/photos and Apple map/address services are described in
`PRIVACY.md`. Do not mechanically select “Data Not Collected” because OCR is local.
Confirm developer/third-party access and retention before answering. Complete the
current age-rating, export-compliance and distribution questionnaires honestly;
do not reuse an assumed age rating from old notes. Privacy manifests and App Store
privacy answers are separate requirements.

## 8. Archive, upload, test Production, submit

The owner has authorized the assistant to upload after readiness checks pass.
Account sign-in/MFA, schema deployment and accurate submission answers still need
the owner. An upload is not an automatic public release.

Choose the reviewed integrated commit, verify a new build number, select Any iOS
Device and Product → Archive. Validate in Organizer, then Distribute → App Store
Connect. Verify archive entitlements/provisioning match the final capability choice.
Upload to TestFlight, complete the Production sync/hardware checks above, then
attach the approved build, review notes and contact details to the version and
submit for review. Keep the final release manual until the owner approves it.

## References

- [Apple: SwiftData sync](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Apple: screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Apple: App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
