# App Store Connect listing — ParkSignal AI (v1)

Draft copy and metadata for submission. Paste into App Store Connect. Fields
respect Apple's character limits.

---

## App name (max 30)
`ParkSignal AI`

## Subtitle (max 30)
`Read parking signs instantly`

Alternatives:
- `Scan signs. Skip the ticket.`
- `Parking signs, decoded`

## Promotional text (max 170, editable without a new build)
`Point your camera at any parking sign and ParkSignal reads the rules for you —
then reminds you before you have to move. All on-device. No account.`

## What's New (version 1.0 release notes, max 4000)
```
Welcome to ParkSignal AI 1.0.

• Scan any parking sign with your camera — the rules are read on-device in seconds.
• A color-coded "parking signal" tells you at a glance whether you can park, and until when.
• Save your spots on a map, each pin colored by its signal.
• Set an alarm and get reminded before a restriction starts.
• 100% private: no account, no tracking, nothing leaves your device. Optional iCloud sync keeps your own spots across your devices.

Thanks for trying ParkSignal. Feedback is welcome via the Support link in Settings.
```

## Description (max 4000)
```
Parking signs shouldn't be a puzzle. ParkSignal AI reads them for you.

Point your camera at a parking sign and ParkSignal turns the fine print into a
clear, color-coded answer: can I park here, and until when?

• SCAN ANY SIGN
Snap a photo of a parking sign. On-device text recognition reads it and pulls
out the rules — days, times, limits, and type — in seconds.

• KNOW AT A GLANCE
A simple color tells you what to do:
  Green — safe to park
  Red — illegal right now
  Yellow — a restriction is starting soon
  Blue — permit / ADA
  Purple — metered / paid
  Gray — unknown

• SAVE YOUR SPOTS ON A MAP
Every spot you scan becomes a pin, colored by its parking signal. Tap any pin to
see the rules, your photos, and the address.

• NEVER GET A TICKET
Set an alarm and ParkSignal reminds you before a restriction begins — with the
lead time you choose — so you always have time to move the car.

• PRIVATE BY DESIGN
ParkSignal works entirely on your device. There are no accounts, no tracking,
and nothing you scan is sent anywhere. Turn on iCloud to keep your own spots in
sync across your devices — your data stays yours.

Made for drivers who are tired of squinting at confusing signs and gambling on a
ticket. Scan it, know it, park with confidence.

Note: ParkSignal helps you read and organize parking information; always confirm
posted signs. It doesn't guarantee against citations.
```

## Keywords (max 100, comma-separated, no spaces after commas)
`parking,parking sign,street parking,park,ticket,street cleaning,meter,car,reminder,alarm,curb,scanner`

(97 chars — verify in App Store Connect.)

## Categories
- Primary: **Navigation**
- Secondary: **Utilities**

## URLs
Host-ready pages are in `docs/legal/` — publish them (e.g. GitHub Pages) and paste the resulting URLs here.
- Support URL (required): host `docs/legal/support.html` → e.g. `https://<user>.github.io/ParkSignalAIBeta/support.html`
- Privacy Policy URL (required): host `docs/legal/privacy.html` → e.g. `https://<user>.github.io/ParkSignalAIBeta/privacy.html`
- Marketing URL (optional): `https://<your-site>`

> Both pages have `{{SUPPORT_EMAIL}}` and `{{EFFECTIVE_DATE}}` placeholders — fill them before hosting. Enabling GitHub Pages for this repo (Settings → Pages → deploy from `main` / `/docs`) serves everything under `docs/` at `https://<user>.github.io/ParkSignalAIBeta/legal/...`.

## Age rating
**4+** — no objectionable content. Questionnaire: None for all categories
(no violence, profanity, mature/suggestive themes, gambling, etc.).

## App Privacy ("App Privacy" section)
v1 collects **no** data off the device.
- **Data Not Collected** — select this. Nothing you scan, your location, photos,
  or spots leave the device (Apple defines "collection" as transmitting off
  device; ParkSignal does not).
- This matches the bundled `PrivacyInfo.xcprivacy` (declares only the
  UserDefaults required-reason API; no tracking, no collected data types).
- If/when the optional cloud "Smart Scan" ships (a later version), the privacy
  answers and manifest must be updated to declare what is sent.

## Permissions (Info.plist purpose strings already set)
- Camera — "ParkSignal uses the camera to scan parking signs and read the rules for you."
- Location (When In Use) — "ParkSignal uses your location to show nearby parking spots and check the rules for where you are parked."
- Photo Library — "ParkSignal needs access to your photos so you can pick an existing picture of a parking sign to analyze."
- AlarmKit — "ParkSignal uses alarms to alert you before a parking restriction starts so you can move your car in time."

## Build / capabilities notes for submission
- **Device family: iPhone only** (`TARGETED_DEVICE_FAMILY = 1`) — no iPad
  screenshots or iPad review needed.
- **iCloud (CloudKit)** is enabled and shipping (foreground sync). Before the
  App Store build, deploy the CloudKit schema Development → Production (see
  `SUBMISSION_CHECKLIST.md`).
- **Push Notifications** capability decision is still open (see
  `SUBMISSION_CHECKLIST.md`). Push is only needed for real-time *background*
  sync; without it, sync happens when the app is foregrounded. Whatever you
  choose, the entitlements + provisioning must match the uploaded build.
- Copyright: `© 2026 SOTech` (adjust).

## Screenshots
Provided under `docs/store/screenshots/` (6.9" iPhone, native 1320×2868):
- `iphone69-1-dashboard.png`, `iphone69-2-map.png`, `iphone69-3-spotdetail.png` — ready to upload.
- `iphone69-4-alerts-DEBUGrows.png` — **do not upload**: captured from a DEBUG
  build, so it shows developer-only "Test" rows. Recapture from a Release build
  (or the Alerts screen without debug rows) if you want a 4th screenshot; 1–3
  clean shots already satisfy Apple's minimum.
- iPhone-only, so **no iPad screenshots are required**.
