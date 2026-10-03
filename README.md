<p align="center"><img src="docs/icon.png" width="128" alt="HuaSideload icon"></p>

<h1 align="center">HuaSideload</h1>

<p align="center"><b>Sideload your own apps and music onto Huawei watches from an iPhone.</b><br>No Android phone needed.</p>

Huawei Health on iPhone can pair with a Huawei watch, but it cannot install third-party watch apps or copy
music to the watch; Huawei only allows that from Android phones. **HuaSideload** is an iOS app that talks
to Huawei *lite wearable* watches directly over Bluetooth LE: it pairs with the watch, **installs your own
watch apps** (signed HarmonyOS/OpenHarmony lite JS apps, built with the included tools), **uploads music**
to the watch's player, and gives your watch apps a JSON message channel to the iPhone.

> **Huawei Health:** set the watch up once with Huawei Health as usual (language, region, terms). After that
> HuaSideload pairs with the watch on its own and does not need Huawei Health. Setting up a brand-new or
> factory-reset watch with HuaSideload alone has not been tested.

The Huawei protocol is a Swift port of [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge)'s
implementation. The app UI is available in **English and Turkish** (globe menu, top right).

---

## Contents
1. [What it does and doesn't do](#1-what-it-does-and-doesnt-do)
2. [Requirements](#2-requirements)
3. [Install the iPhone app and pair the watch](#3-install-the-iphone-app-and-pair-the-watch)
4. [Your own watch app](#4-your-own-watch-app)
5. [Things to know when writing watch apps](#5-things-to-know-when-writing-watch-apps)
6. [Keeping your own features in a separate project](#6-keeping-your-own-features-in-a-separate-project)
7. [Troubleshooting](#7-troubleshooting)
8. [Project layout and how it works](#8-project-layout-and-how-it-works)
9. [Credits and license](#9-credits-and-license)

---

## 1. What it does and doesn't do

**Does:**
- Pairs with the watch over BLE (HiChain), encrypted connection, automatic reconnect
- Battery and watch info, notifications to the watch
- **Installs and removes your own watch apps** (signed `.bin` with a debug profile)
- Uploads **MP3/M4A/AAC/FLAC/WAV/OPUS** to the watch's own music player (to listen without the phone)
- **JSON messaging** between your watch apps and the phone (Wear Engine P2P)
- Shows the watch's **UDID** (needed for the debug profile; no Android phone required)

**Doesn't (at least for now, tried; limited by the watch hardware or iOS):**
- Play iPhone audio (Spotify etc.) through the watch speaker: the watch is not an audio receiver (A2DP)
- Upload DRM-protected songs (Spotify, Apple Music) to the watch
- Give watch apps internet access (but the phone app can send them any data)

**Tested watch:** HUAWEI WATCH GT 3 SE (firmware 3.0.0.69, OpenHarmony 1.1 based lite wearable, API 6,
466×466 round screen). Other Huawei *lite wearable* watches on the same platform (GT 2 Pro, GT 3, …) will
likely work but are untested. HarmonyOS *wearable* watches (Watch 3/4) are a different platform.

> ⚠️ **Disclaimer:** This uses an unofficial protocol. Pairing with HuaSideload may break the Huawei Health
> connection; if something goes wrong you may need to reset the watch and pair it with Health again.
> This project is not affiliated with Huawei. Use at your own risk.

---

## 2. Requirements

| | What for | How |
|---|---|---|
| Mac + **Xcode 16+** | the iPhone app | App Store |
| **XcodeGen** | generating the Xcode project | `brew install xcodegen` |
| Apple ID | installing on your iPhone | A free account works (apps must be reinstalled every 7 days) |
| **Huawei developer account** | signing watch apps | Free, [developer.huawei.com](https://developer.huawei.com) |
| **OpenHarmony SDK (API 9)** | compiling watch apps | DevEco Studio 3.1 → Settings → SDK → OpenHarmony API 9 (`js` and `toolchains`). Default location: `~/Library/Huawei/Sdk/openharmony/9` |
| **Node.js 16** | the watch app compiler (ace-loader) | the Node that DevEco installs, or `nvm install 16`. Newer versions don't work |
| **Java 11+** | packing and signing tools | `brew install openjdk@17` |
| Python 3 | helper tools | comes with macOS |

If the SDK or Node live elsewhere, set `OHOS_SDK=/path` or `NODE16=/path/to/node`.

> If you only want the iPhone app (pairing, music upload, notifications) you don't need the Huawei account
> or the OpenHarmony SDK; those are only for installing your own watch apps.

---

## 3. Install the iPhone app and pair the watch

```bash
git clone https://github.com/Burak4Arslan/huawei-watch-sideload-ios.git HuaSideload && cd HuaSideload
cp Config/local.env.example Config/local.env   # fill in your Team ID and bundle ID
./generate.sh                                  # creates HuaSideload.xcodeproj
open HuaSideload.xcodeproj                     # pick your iPhone, Run
```

- **Team ID:** Xcode → Settings → Accounts → your account → Team. You can also leave it empty and pick the team in Xcode under *Signing & Capabilities*.
- **Bundle ID:** something unique, e.g. `com.yourname.huasideload`. Your watch apps send their messages to this ID.

**Pairing** (the watch must have been set up once with Huawei Health):
1. Close Huawei Health (swipe it up in the app switcher).
2. HuaSideload → **Find watch** → tap your watch. If it is connected to Huawei Health it shows up as "connected to phone".
3. **Pair**. If the watch asks for confirmation, accept it.
4. From then on HuaSideload reconnects and pairs automatically.

**UDID:** after pairing it appears under Status, hidden. **Show identity** reveals it, **Copy UDID** copies it. You need it for the debug profile.

**Language:** the globe menu (top right) switches between English and Turkish. The first launch follows the phone's language.

---

## 4. Your own watch app

### 4.1 Huawei developer account and signing (once)

The watch only installs apps signed with a Huawei-issued debug profile that **contains your watch's UDID**.

**a) Create a key and a CSR** (with the signing tool from the OpenHarmony SDK):
```bash
SDK=~/Library/Huawei/Sdk/openharmony/9
mkdir -p signing && cd signing
java -jar $SDK/toolchains/lib/hap-sign-tool.jar generate-keypair \
  -keyAlias mykey -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile mykey.p12 -keyPwd YOURPASSWORD -keystorePwd YOURPASSWORD
java -jar $SDK/toolchains/lib/hap-sign-tool.jar generate-csr \
  -keyAlias mykey -keyPwd YOURPASSWORD -keystoreFile mykey.p12 -keystorePwd YOURPASSWORD \
  -subject "C=US,O=Your Name,OU=Your Name,CN=mykey" -signAlg SHA256withECDSA -outFile mykey.csr
echo -n YOURPASSWORD > password.txt
```

**b) In AppGallery Connect** ([developer.huawei.com](https://developer.huawei.com) → AppGallery Connect):
1. **Certificates, App ID and Profiles → Certificates → New:** type **Debug**, upload `mykey.csr`, download the `.cer` → `signing/mykey-debug.cer`.
2. **Devices → Add:** type **Sports watch** (lite wearable), paste the UDID from HuaSideload.
3. **My projects → create a project → Add app:** HarmonyOS app, device **Sports watch**, package name (e.g. `com.yourname.huasideload.sample`). Don't select any capabilities or permissions.
4. **Profiles → Add:** that app, type **Debug**, your certificate, your watch → download the `.p7b` → save it as `signing/profiles/<package name>.p7b`.

Repeat steps 3 and 4 for every new watch app. The key, certificate and device stay the same.

**c) `signing/signing.env`:** copy `signing/signing.env.example` and fill in the file names. Nothing in `signing/` is committed to git.

### 4.2 Start from the sample

```bash
cp -R watch-apps/sample watch-apps/my-app
```
- `entry/src/main/config.json` → set `bundleName` to your package name from AppGallery Connect.
- `resources/base/element/string.json` → `app_name` (the name shown on the watch, at most 30 characters).
- Icon: `python3 tools/make-app-icon.py watch-apps/my-app 2A6FDB` (a colored disc), or put your own `icon.png` (114×114) and `icon_small.png` (41×41) in `resources/base/media/`.

### 4.3 Build, bundle into the iPhone app, install on the watch

```bash
tools/build-watch-app.sh watch-apps/my-app     # → WatchApps/<app_name>.bin
./generate.sh                                  # adds the new .bin to the Xcode project
```
1. Run the iPhone app from Xcode again.
2. HuaSideload → **Watch apps** → **"Install … on the watch"**.
3. When it's done the app appears in the watch's app list. To remove it: **Show apps on the watch** → **Delete**.

At the end `build-watch-app.sh` checks the package against the watch installer's rules with
`tools/check-watch-bin.py`. If it says "WILL NOT INSTALL", the reason is printed right there.

**Updating:** **increase** `version.code` in `config.json` (the watch refuses the same or a lower version), build, install again.

### 4.4 Talking to the phone

On the watch, `common/bridge.js`:
```js
import bridge from '../../common/bridge.js';
bridge.listen(function (message) { /* from the phone: {"t": ..., ...} */ });
bridge.start();
bridge.send({ t: 'hello' }, function (ok) { /* delivered? */ });
```

On the iPhone, a `WatchFeature` (see `HuaSideload/HelloFeature.swift`):
```swift
final class MyFeature: WatchFeature {
    private weak var host: WatchFeatureHost?
    var watchPackages: [String] { ["com.yourname.huasideload.sample"] }
    func attach(to host: WatchFeatureHost) { self.host = host }
    func handle(_ message: [String: Any], from package: String) async -> Bool {
        guard message["t"] as? String == "hello" else { return false }
        host?.bridge(for: package)?.send(["t": "hello", "s": "Hi!"])
        return true
    }
}
```
Add it in `WatchFeatures.load()`, or keep it in a separate project as described in section 6.
A feature can also put its own sections on the main screen (`sections()`).

---

## 5. Things to know when writing watch apps

All of these were found by testing on the watch. Most of them give no error message at all: just "103",
a black screen or a frozen watch.

| Symptom | Cause | Fix |
|---|---|---|
| Install fails with **103** | no `icon_small.bin` in the icon folder | add `resources/base/media/icon_small.png` (41×41) |
| Install fails with **103** | your watch's UDID is not in the profile / wrong package name / wrong certificate | check 4.1; `tools/check-watch-bin.py` inspects the package |
| Install fails with **103** | `version.code` is not higher than the installed version | increase it |
| **Black screen** at launch | `import x from '@system.wearengine'` (not known to the OpenHarmony compiler; webpack emits code that throws at runtime) | load it with `requireModule('@system.wearengine')` inside try/catch (`bridge.js` does this). The build tool stops on `COMPILE RESULT:FAIL` |
| Watch **freezes** at launch | starting the phone connection on the very first page at launch | a plain splash page (`pages/index`) + `router.replace` to the real page, connect there |
| Watch **freezes** at launch | `config.json` → `module.metaData` → `supportLists` | leave it out; messaging works without it |
| Drawings pile up, memory fills | the lite `canvas` has no `clearRect` | recreate the canvas with `if` (swap between two canvases) |
| `fillText` draws nothing | the canvas font needs a font family name | draw text with a normal `<text>` on top |
| Messages don't arrive | messages larger than ~1 KB | split them (`WatchAppBridge.sendBatch` on the iPhone side) |

**Other notes:**
- Keep the screen on: `requireModule('@system.brightness').setKeepScreenOn({ keepScreenOn: true })`.
- The lite JS engine (JerryScript) is small and slow; write short code with `var`, `function` and plain objects.
- Each Bluetooth message takes about 0.3 s round trip. Pack multi-part data into few messages.

---

## 6. Keeping your own features in a separate project

This repo is the **core**. You can keep your own features and watch apps out of it, in a separate folder:

```
~/Projects/
  HuaSideload/            ← this repo (core)
  HuaSideload-private/    ← your private project (doesn't need to be on git at all)
    project.yml           ← takes the core from ../HuaSideload/HuaSideload, adds your iOS/ and WatchApps/
    iOS/                  ← your WatchFeatures
    watch-apps/           ← your watch apps
    signing/              ← your signing files
    WatchApps/            ← built .bin files
```

In the private project, define a class implementing `WatchFeatureProvider` with the Objective-C name
`HuaSideloadPrivateFeatures`. The core finds it at runtime:
```swift
@objc(HuaSideloadPrivateFeatures)
final class PrivateFeatures: NSObject, WatchFeatureProvider {
    @MainActor func makeFeatures() -> [WatchFeature] { [MyFeature()] }
}
```

Sources in the private project's `project.yml`:
```yaml
sources:
  - path: ../HuaSideload/HuaSideload
    excludes: ["Info.plist"]
  - path: iOS
  - path: WatchApps
    buildPhase: resources
    includes: ["*.bin"]
```
Build its watch apps with this repo's tool:
```bash
HUASIDELOAD_SIGNING_DIR=$PWD/signing HUASIDELOAD_OUT_DIR=$PWD/WatchApps \
HUASIDELOAD_PHONE_PACKAGE=com.yourname.huasideload ../HuaSideload/tools/build-watch-app.sh watch-apps/my-app
```
Fixes to the core then reach both projects automatically.

---

## 7. Troubleshooting

- **The watch is not in the list:** if it's actively connected to another phone or to Huawei Health it may not show up. Close Health, toggle Bluetooth, **Find watch**.
- **"Verification failed: the saved key is no longer valid":** the watch was reset. **Forget pairing** → **Pair** again.
- **Install fails with 103:** see the table in section 5. Start with `python3 tools/check-watch-bin.py WatchApps/X.bin`.
- **"Could not reach the phone (is HuaSideload open?)":** the iPhone app must be running and connected to the watch. It also works in the background, but not after you force-quit it.
- **Sharing the log:** **Copy** in the Log section. Identity details stay masked unless **Show identity** is on.
- **Live log on a Mac:** `xcrun devicectl device process launch --device <iPhone UDID> --console <bundle ID>` (unlock the iPhone first). Every line starts with `[HuaSideload]`.
  `-e '{"HUASIDELOAD_DIAG":"1"}'` also asks the watch for its supported commands, capabilities and music storage.

---

## 8. Project layout and how it works

```
HuaSideload/               the iPhone app (SwiftUI)
  HuaweiProtocol.swift     packet framing (0x5A, CRC16), VarInt, TLV, slicing
  HuaweiAuth.swift         HiChain pairing, AES-GCM/CBC, product info, notifications
  HuaweiFeatures.swift     services: music 0x25, file upload 0x28, apps 0x2A, P2P 0x34
  HuaweiSession.swift      request/response, encryption, file upload state machine, P2P
  WatchLink.swift          CoreBluetooth, pairing, install/remove, music upload, privacy, features
  WatchAppCatalog.swift    finds the bundled .bin files, derives the messaging identity from the profile
  WatchAppBridge.swift     JSON messaging with a watch app
  WatchFeature.swift       plugin API
  HelloFeature.swift       sample feature
  Localization.swift       English / Turkish
watch-apps/sample/         sample watch app (lite wearable JS)
tools/
  build-watch-app.sh       compile → pack → sign → check
  check-watch-bin.py       will a .bin pass the watch installer?
  make-app-icon.py         icon.png + icon_small.png
  make-brand-icon.swift    draws the HuaSideload icon
signing/                   (not in git) key, certificate, profiles
WatchApps/                 (not in git) built watch apps
```

**The protocol in short:** the watch exposes BLE service `FE86` (write `FE01`, notify `FE02`). Packets start
with `0x5A` and end with a CRC16/XMODEM; the payload is TLV. Pairing uses HiChain, after which everything is
encrypted with AES-GCM.
- **Installing:** the file is uploaded over `0x28` as type 6; the watch reports progress and the result with `0x2A/0x02` (102 installed, 103 failed).
- **Music:** uploaded as type 2; the watch then asks for the song title with `0x25/0x09`.
- **Messaging with watch apps:** Wear Engine P2P (`0x34`). A watch app's identity is `package + "_" + base64(EC public key of the developer certificate)`; `WatchAppCatalog` derives it from the profile inside the `.bin`.
- **UDID:** the watch sends its UDID on every pairing, in tag `0x05` of the security negotiation reply (`0x01/0x33`).

The build pipeline is the command-line equivalent of DevEco Studio's "legacy lite" build:
ace-loader (webpack lite) → restool → haptobin_tool → hap-sign-tool `sign-app -inForm bin`.

---

## 9. Credits and license

- The Huawei protocol was ported to Swift from the Huawei support in [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) (AGPL-3.0); therefore this project is licensed under **AGPL-3.0** as well (`LICENSE`).
- The watch-side install rules were found by reading OpenHarmony's `appexecfwk_lite` and `security_appverify` sources (Apache-2.0).
- `bridge.js` follows the logic of Huawei's Wear Engine lite wearable JS SDK (Apache-2.0), trimmed down.

HUAWEI, HarmonyOS and AppGallery are trademarks of Huawei Technologies Co., Ltd. This project is not affiliated with Huawei.
