# ParkSignal AI

An iPhone parking-sign reader, organizer and reminder. Free v1 uses Apple Vision
OCR and an on-device parser; there is no OpenAI key, app account, ads or purchase.

Capture a sign, compare the suggested rules with the original and confirm them
before saving. Unsupported monthly, seasonal, holiday and vehicle-specific rules
remain marked for review and cannot produce a clear parking signal or automatic
reminders. A color indicator describes saved rules, not legal permission to park.

## Development

Open `test2.xcodeproj`, scheme `test2`, in Xcode 26.6 or a compatible newer Xcode.
Deployment target: iOS 18.6. Module: `ParkSignal_AI`. Product: `ParkSignal AI`.

```sh
xcodebuild test -project test2.xcodeproj -scheme test2 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:test2Tests CODE_SIGNING_ALLOWED=NO
```

CI runs unit tests and a Release build. The sign corpus checks supported meanings
and explicit review handling for unsupported signs; it is not a claim of accuracy
on every photograph or city. Simulator tests also exercise disk-store migration,
photo rehydration, multiple parking sessions, reminder reconciliation and DST.

## Storage and reminders

SwiftData stores spots, cars, scans, restrictions, sessions and photo blobs locally.
CloudKit is configured for the user's private `iCloud.com.SOTech.ParkSignalAI`
database when available. CloudKit relationships are optional; convenience lists
keep UI access straightforward while preserving existing stored field names.
Settings reports local-only operation and iCloud availability/transfer status.
A successful local save does not prove a successful cloud upload.

`ParkingSessionService` owns parking-session changes. `ScanReviewService` replaces
only the confirmed scan's rules. `ReminderCoordinator` derives device-local
reminders from active sessions, preserves manual cancellation, and reschedules
when saved data or lead time changes. Each device must enable its own reminders.
Photos use local files as a cache and `PhotoBlob` as the synced source.

## Release

The release candidate is not a submitted or approved app. See
[the submission checklist](docs/store/SUBMISSION_CHECKLIST.md),
[status and evidence](docs/store/STATUS.md) and [listing draft](docs/store/APPSTORE.md).
Authenticated two-device sync, a physical-device scan/alarm pass and the signed
TestFlight build remain release gates. Do not reset a user's store to resolve a
migration error. Apple-account, signing and App Store actions belong to the owner.

[Privacy policy](PRIVACY.md) · [Support](https://shawn8989.github.io/ParkSignalAIBeta/legal/support.html)

## Later

Evaluate opt-in cloud Smart Scan only if it materially improves a measured sign
benchmark. It would require a server-held key, consent, rate limits, usage
accounting and StoreKit purchases. Scan packs are a pricing experiment for later;
core reminders and manual corrections remain free. No such service ships in v1.
