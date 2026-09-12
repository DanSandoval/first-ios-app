# First iOS App

A SwiftUI "hello world" built entirely in the cloud. No Mac required — GitHub Actions
compiles it on a macOS runner and hands you back an `.ipa` you install on your iPhone
from Windows.

## What the app does

| Tab | Feature | Concept it demonstrates |
| --- | --- | --- |
| **Home** | Title reads **First iOS App** | `.navigationTitle` / large titles |
| **Home** | Button that puts **Hello, World!** on screen | `@State`, `withAnimation`, transitions |
| **Home** | Button that pushes to a **Second Page** | `NavigationStack` + `NavigationLink` |
| **Home** | Tap counter (+ / −) | `@State` and animated numeric text |
| **Home** | Name field + "Excited" toggle with live output | Two-way `$` bindings |
| **List** | Searchable list of iOS concepts → detail pages | `List`, `.searchable`, `navigationDestination` |
| **Device** | Haptic buzz buttons | `UIFeedbackGenerator` — real hardware only |
| **Device** | Model, iOS version, screen size, app version | Reading device info |
| **Device** | Launch count + nickname that survive a force-quit | `@AppStorage` / `UserDefaults` |

Dark mode, SF Symbols icons, a generated app icon, and a proper launch screen are all wired up.

## Getting it on your iPhone

### 1. Grab the build

Every push to `main` triggers the build. Go to the repo's **Actions** tab → newest
**iOS Build** run → scroll to **Artifacts** → download **`FirstApp-unsigned-ipa`**.
Unzip it; inside is `FirstApp-unsigned.ipa`.

The `.ipa` is deliberately **unsigned** — GitHub's runner has no access to your Apple
identity, so it can't sign for your device. You supply the signature locally in step 3.

### 2. One-time Windows setup

1. **iTunes** — install from [apple.com](https://www.apple.com/itunes/download/win64), **not**
   the Microsoft Store version. Only the apple.com installer ships the USB device drivers
   sideloading needs.
2. **iCloud for Windows** — also from [apple.com](https://support.apple.com/en-us/HT204283),
   again not the Store version.
3. **Sideloadly** — from [sideloadly.io](https://sideloadly.io).

### 3. Sideload it

1. Plug the iPhone in over USB, unlock it, tap **Trust** on the prompt.
2. Open Sideloadly, drag `FirstApp-unsigned.ipa` onto it.
3. Enter your Apple ID. Use your **real password** and then the 2FA code when prompted —
   an app-specific password will not work here, Sideloadly needs a full sign-in to request
   a development certificate.
4. Hit **Start** and wait.
5. On the iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID →
   **Trust**. iOS will not launch the app until you do this.
6. Open **First iOS App** from your home screen.

### Free-account limits (not our doing — Apple's)

- The app **stops working after 7 days**. Re-run Sideloadly to reset the clock.
- **Three** sideloaded apps maximum per Apple ID at a time.
- [AltStore](https://altstore.io) is worth a look if the weekly re-plug annoys you — its
  AltServer component refreshes apps over Wi-Fi automatically while your PC is on.

## Upgrading to a paid account later

Nothing here gets thrown away. The app code doesn't change at all, and the workflow
already contains a complete `testflight` job — it just sits dormant.

When you enrol in the Apple Developer Program ($99/yr):

1. Add these **repository secrets** (Settings → Secrets and variables → Actions):

   | Secret | What it is |
   | --- | --- |
   | `APPLE_CERT_P12_BASE64` | Apple Distribution certificate, exported as `.p12`, base64-encoded |
   | `APPLE_CERT_PASSWORD` | The password you set on that `.p12` |
   | `APPLE_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile, base64-encoded |
   | `APPLE_TEAM_ID` | Your 10-character Team ID |
   | `APPSTORE_API_KEY_ID` | App Store Connect API key ID |
   | `APPSTORE_API_ISSUER_ID` | App Store Connect issuer ID |
   | `APPSTORE_API_PRIVATE_KEY` | Contents of the `AuthKey_*.p8` file |

2. Add the **repository variable** `ENABLE_TESTFLIGHT` = `true`.

That's the switch. Pushes then also build a signed archive and upload it to TestFlight,
and you install over the air from the TestFlight app — no cable, no 7-day expiry,
90 days per build.

The signing steps use a throwaway keychain with a random password that is destroyed at
the end of every run, pass secrets through step `env:` rather than interpolating them
into shell text, and delete every decoded credential immediately after use.

## Building it differently

The Xcode project is **not** committed. `project.yml` is the source of truth and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) generates `FirstApp.xcodeproj` during
the build. That keeps merge-conflict-prone `.pbxproj` noise out of the repo — change the
bundle ID, display name, or deployment target in `project.yml` and the next build picks it up.

If you ever get access to a Mac:

```sh
brew install xcodegen
swift Tools/make-icon.swift FirstApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png
xcodegen generate
open FirstApp.xcodeproj
```

## Cost note

macOS runners bill at **10× the normal rate** against your Actions minutes. On a public
repo that's irrelevant — it's free. On a private repo, the free tier's 2,000 minutes/month
works out to roughly 200 macOS minutes, and a build here takes about 3, so budget
accordingly.
