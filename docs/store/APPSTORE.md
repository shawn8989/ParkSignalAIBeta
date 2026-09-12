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
- Support URL: `https://<your-site-or-github-pages>/support` (required — placeholder)
- Marketing URL (optional): `https://<your-site>`
- Privacy Policy URL: host `PRIVACY.md` (e.g., GitHub Pages) and paste that URL (required)

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
- iCloud (CloudKit) + Push capabilities must be enabled on the App ID before an
  iCloud-syncing build is uploaded (see PR #3). If you submit v1 without iCloud,
  remove the entitlements first, or ship with the capabilities enabled.
- Copyright: `© 2026 SOTech` (adjust).

## Screenshots
Provided under `docs/store/screenshots/` (6.9" iPhone: dashboard, map, spot
detail). See the note in the PR about the alerts screenshot (debug rows) and the
iPad set (pending the iPhone-only vs universal decision).
