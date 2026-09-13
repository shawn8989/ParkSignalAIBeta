# ParkSignal AI — v1.0 Submission Checklist

The remaining steps to ship v1.0. **These all require your Apple account,
credentials, a device, or App Store Connect access — they can't be automated.**
Do them roughly in order; the code itself is ready (builds clean, tests green).

Repo: `shawn8989/ParkSignalAIBeta` · Bundle ID: `com.SOTech.ParkSignalAI` ·
Team: `EU6247328G` · iCloud container: `iCloud.com.SOTech.ParkSignalAI` ·
iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).

---

## 1. Decide on Push Notifications
You added the Push capability in Xcode, so `test2/test2.entitlements` currently
has `aps-environment` back (uncommitted).

- **Push is only needed for real-time _background_ sync** (silent pushes wake the
  app to pull changes). Without it, CloudKit still syncs — just when the app is
  foregrounded.
- **Keep Push:** also add Background Modes → *Remote notifications* (removed
  earlier), then commit the entitlements + `Info.plist` so the repo matches your
  App ID. Signing works because the capability is enabled on the App ID.
- **Drop Push:** remove the Push capability in Xcode (reverts `aps-environment`);
  sync then happens on foreground only.
- Either way, the **entitlements + provisioning profile must match the uploaded
  build**, or the upload is rejected.

## 2. Create the CloudKit schema (Development)
The schema (record types) only gets created when the app runs against a **real,
authenticated iCloud account**. A simulator with no iCloud account won't do it.

1. On your iPhone (already signed into iCloud), or a simulator signed into iCloud:
   run the app from Xcode (select the device → Run).
2. Add or scan a spot.
3. SwiftData auto-creates the `CD_*` record types in the container's **Development**
   environment.

## 3. (Optional) Verify sync end-to-end
Sign a second device (or simulator) into the same iCloud account, launch the app,
and confirm the spot from step 2 appears. Confirms sync, not just schema creation.

## 4. Deploy the CloudKit schema Development → Production
Only appears **after** step 2 has created the schema.

1. Go to **[CloudKit Console](https://icloud.developer.apple.com/dashboard)** → sign in.
2. Select container **`iCloud.com.SOTech.ParkSignalAI`**.
3. Confirm the `CD_*` record types show under **Development → Schema → Record Types**.
4. Click **Deploy Schema Changes…** (Development → Production) and confirm.
   *(Required before the App Store build — the App Store app runs against Production.)*

## 5. Host the Privacy Policy & Support pages
Both are ready in `docs/legal/` (`privacy.html`, `support.html`).

1. Replace `{{SUPPORT_EMAIL}}` and `{{EFFECTIVE_DATE}}` in both files.
2. Publish them — easiest is **GitHub Pages**: repo **Settings → Pages →** deploy
   from `main`, folder `/docs`. Pages then serves them at
   `https://<user>.github.io/ParkSignalAIBeta/legal/privacy.html` (and `support.html`).
3. Note both URLs for App Store Connect (step 7).

## 6. Real-device camera scan test
On your iPhone: scan a real parking sign end-to-end (camera → on-device parse →
signal → saved spot → set an alarm and confirm it fires). Confirms the release
build works on hardware.

## 7. Create the App Store Connect record + metadata
In **[App Store Connect](https://appstoreconnect.apple.com)** → **Apps → +**.

1. Platform iOS, name **ParkSignal AI**, primary language English, bundle ID
   `com.SOTech.ParkSignalAI`, SKU (anything unique).
2. Paste metadata from **`docs/store/APPSTORE.md`**: subtitle, promo text,
   description, keywords, categories (Navigation / Utilities), copyright.
3. **What's New**: paste the 1.0 release notes from `APPSTORE.md`.
4. **Support URL** and **Privacy Policy URL**: the two hosted URLs from step 5.
5. **App Privacy**: select **Data Not Collected** (matches `PrivacyInfo.xcprivacy`).
6. **Age rating**: complete the questionnaire → **4+** (no objectionable content).
7. **Screenshots** (6.9" iPhone): upload `docs/store/screenshots/iphone69-1…3`.
   **Do not** upload `iphone69-4-alerts-DEBUGrows.png` (it shows DEBUG-only rows);
   recapture from a Release build if you want a 4th. iPhone-only → no iPad shots.

## 8. Archive & upload the build
In Xcode:

1. Select **Any iOS Device (arm64)**, scheme `test2`, **Release** config.
2. Set/verify **Version** (1.0) and **Build** (1).
3. **Product → Archive** → **Distribute App → App Store Connect → Upload**.
4. Signing must use your Team `EU6247328G` with a profile that includes the
   iCloud container (and Push, if kept in step 1).
5. (Optional) Test via **TestFlight** first.

## 9. Submit for review
In App Store Connect: attach the uploaded build to the 1.0 version, answer the
export-compliance question (no non-exempt encryption), add review notes if
helpful (e.g. "on-device parking-sign reader; no account required"), and
**Submit for Review**.

---

### Status of the code (done — no action needed)
- ✅ v1 is iPhone-only, on-device, single-user; mock login/demo seed removed (DEBUG-gated).
- ✅ `PrivacyInfo.xcprivacy` present (UserDefaults required-reason API); no tracking/collection.
- ✅ CloudKit-compatible models; container with local-only fallback.
- ✅ Unit tests green in CI (`-only-testing:test2Tests`); Debug + Release build clean.
- ⏳ Compiler-warning cleanup and accessibility polish are tracked in `STATUS.md`.
