# First iOS App

A SwiftUI "hello world" built entirely in the cloud. No Mac required — GitHub Actions
compiles it on a macOS runner and hands you back an `.ipa` you install on your iPhone
from Windows.

## What the app does

**Requires iOS 18 or later.**

| Tab | Feature | Concept |
| --- | --- | --- |
| **Home** | Title reads **First iOS App** | large navigation titles |
| **Home** | Button that puts **Hello, World!** on screen | `@State`, `withAnimation`, transitions |
| **Home** | Button that pushes to a **Second Page** | `NavigationStack` + `NavigationLink` |
| **Home** | Tap counter, name field, toggle | two-way `$` bindings |
| **List** | Searchable list of iOS concepts | `List`, `.searchable`, `navigationDestination` |
| **Search** | Live GitHub repo search | the whole networking stack, end to end |
| **Device** | Haptics, device info, persisted values | hardware feedback, `@AppStorage` |

## Reusable modules

Everything under `FirstApp/Core/` is written to be copied into another project.

| Module | What it gives you |
| --- | --- |
| `Core/Networking` | Actor-based API client, typed `APIError`, exponential backoff with full jitter, rate-limit parsing, injectable transport for testing |
| `Core/Security` | Keychain wrapper (`AfterFirstUnlockThisDeviceOnly`, upsert, excluded from backups), `TokenStore`, Face ID gate |
| `Core/Persistence` | Actor-backed disk cache with TTL and a network-first-fallback-to-cache policy |
| `Core/Diagnostics` | OSLog wrappers that redact tokens, URL query values and auth headers |
| `Core/DesignSystem` | 4pt spacing scale, semantic palette, button styles, Dynamic Type throughout |
| `Core/Connectivity` | `NWPathMonitor` observable with `isExpensive` / `isConstrained`, offline banner |
| `Core/State` | `Loadable` plus loading / empty / error views |

51 unit tests run on a simulator in CI **before** the device build, so a failing
test blocks the `.ipa`.

Three decisions worth knowing about, each a bug that would otherwise surface late:

- Query strings encode a literal `+` as `%2B`. `URLComponents` is spec-correct to
  leave it bare, but any server that form-decodes reads `a+b` back as `a b`, silently.
- `BiometricGate` builds a fresh `LAContext` per attempt. A reused context reports
  success with no prompt and no biometric check.
- Cache keys are SHA-256 hashed. A raw key containing a path separator is a
  traversal bug.

## Getting it on your iPhone

### 1. Grab the build

Every push to `main` builds and publishes. Two ways to get it:

**From your phone (easiest)** - open the
[latest release](../../releases/tag/latest) in Safari *on the iPhone* and download
`FirstApp-unsigned.ipa`. It is a plain public file, so no GitHub login and no zip
wrapper. The URL never changes:

```
https://github.com/DanSandoval/first-ios-app/releases/download/latest/FirstApp-unsigned.ipa
```

**From Windows** - same link in a desktop browser, or the **Actions** tab -> newest
**iOS Build** run -> **Artifacts** -> `FirstApp-unsigned-ipa` (that one arrives zipped).

The `.ipa` is deliberately **unsigned** - GitHub's runners hold no Apple identity, so they
cannot sign for your device. You supply the signature at install time.

### 2. One-time Windows setup

Sideloadly needs the **web (desktop) builds** of iTunes and iCloud, **not** the Microsoft
Store versions. If the Store ones are installed, uninstall them first or signing fails.
Take **64-bit** throughout - Windows 11 has no 32-bit edition.

Apple's own iCloud support page now links only to the Microsoft Store build, which does not
work here. Get both installers from the **"Before you install"** dialog on
[sideloadly.io](https://sideloadly.io) instead - its **Web iTunes 64-bit** and **Web iCloud**
buttons point at the legacy direct installers.

1. **iTunes** (web version) - ships the USB device drivers sideloading depends on
2. **iCloud** (web version)
3. **Sideloadly** - the purple **Windows** button is the 64-bit build; the darker "32-bit"
   segment beside it is the alternate you do not want

### 3. Enable Developer Mode on the iPhone

**iOS 16 and later will not run a sideloaded app until Developer Mode is on.** Skipping this
is the most common reason an install fails.

**Settings -> Privacy & Security -> Developer Mode** (at the bottom) -> toggle on -> **Restart**.
After the phone reboots, unlock it and confirm **Turn On** at the prompt.

If the menu item is not there, it is because the phone has not yet been asked to run a
development app. Attempt the install once; the failure makes the menu appear.

This is one-time - it persists across reboots and future sideloads.

### 4. Sideload it

Keep the phone **unlocked and on the home screen** for this. A locked screen fails with
`LOCKDOWN_E_PASSWORD_PROTECTED`, whose "make sure the cable is connected tightly" message is
misleading - it is the lock state, not the cable.

1. Plug the iPhone in, unlock it, tap **Trust** and enter the passcode.
2. Open Sideloadly. The phone should appear in the **iDevice** dropdown.
3. Drag `FirstApp-unsigned.ipa` onto the window.
4. Enter your Apple ID and press **Start**. Use your real password plus the 2FA code when
   prompted. If Sideloadly specifically asks for an app-specific password, generate one at
   [account.apple.com](https://account.apple.com) under Sign-In and Security.
5. On the phone: **Settings -> General -> VPN & Device Management -> [your Apple ID] -> Trust**.
   That entry only appears after the install completes, and the app will not launch until you
   tap it.
6. Open **First iOS App**.

#### If it fails

| Error | Cause |
| --- | --- |
| `LOCKDOWN_E_PASSWORD_PROTECTED` | Phone is locked. Unlock and retry. |
| Developer Mode prompts | See step 3 above. |
| Device not in dropdown | Unplug/replug; confirm Apple Mobile Device Service is running. |
| Untrusted Developer on launch | Step 5 not done yet. |

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
