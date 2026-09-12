# ParkSignal AI 🚦

**Read any parking sign in a tap. Know if you can park. Get an alarm before you have to move.**

ParkSignal AI is an iOS app that reads parking signs with your camera and turns
them into a clear, color-coded "can I park here?" signal — then saves the spot to
a map and reminds you before a restriction starts.

It is **local-first and private**: v1 interprets signs **entirely on-device**
(Apple Vision text recognition + an on-device rules parser). There are no
accounts, and nothing you scan leaves your device. Optional iCloud sync keeps
your own spots in step across your devices.

---

## Features

- **📸 Scan a sign** — photograph a parking sign; on-device OCR reads the text and
  an on-device parser extracts the rules (days, time windows, limits, type).
- **🎨 Parking signal** — a color tells you at a glance:
  - 🟢 Safe to park · 🔴 Illegal now · 🟡 Restriction soon · 🔵 Permit/ADA ·
    🟣 Metered/paid · ⚪ Unknown
- **🗺️ Map of your spots** — each saved spot is a pin colored by its signal; tap
  for rules, photos, and address.
- **⏰ Alarms & reminders** — schedule an alert a chosen lead time before a
  restriction begins (AlarmKit on iOS 26, local notifications otherwise).
- **🚗 Cars & sessions** — track where each car is parked.
- **☁️ Optional iCloud sync** — your data, synced across your own devices via the
  CloudKit private database. No login; iCloud is the identity.

## Tech stack

- **SwiftUI** app (iOS 18.6+), MVVM-ish view models
- **SwiftData** for local persistence (+ optional CloudKit sync)
- **Apple Vision / VisionKit** for on-device OCR
- **CoreLocation + MapKit** for spots and the map
- **AlarmKit** (iOS 26) with a UserNotifications fallback

No third-party services and no network calls to interpret signs in v1 — it all
runs on the device.

## Project structure

```
test2/
├── App/          # App entry (ParkMateApp) and root navigation
├── Models/       # SwiftData @Model types (ParkingSpot, Restriction, SignScan, …)
├── Services/     # OCR, on-device parser, location, geocoding, alarms, notifications
├── Utilities/    # Signal engine, date/geometry helpers, LocalIdentity
└── Views/        # Home, Map, Cars, Scan, Spots, Alerts, Settings, Onboarding
```

(The Xcode target is named `test2` for historical reasons; the product is
"ParkSignal AI", module `ParkSignal_AI`.)

## Building

Open `test2.xcodeproj` in Xcode and run the `test2` scheme on an iOS 18+
simulator or device. Unit tests: `⌘U` (or `xcodebuild test -scheme test2
-only-testing:test2Tests`). CI builds and runs the unit tests on every PR.

To enable iCloud sync on a device, add the **iCloud (CloudKit)** and **Push
Notifications** capabilities to the `test2` target with the container
`iCloud.com.SOTech.ParkSignalAI`, and sign into iCloud on the device.

## Roadmap

- **Smart Scan (premium)** — optional higher-accuracy cloud interpretation via a
  key-protected proxy, behind a subscription. (v1 is on-device only.)
- Broader/authoritative city rule data
- Richer history and multi-car workflows
- App Store launch

## Privacy

See [PRIVACY.md](PRIVACY.md). Short version: no tracking, no analytics, and no
data leaves your device in v1.

## License

TBD (MIT recommended).
