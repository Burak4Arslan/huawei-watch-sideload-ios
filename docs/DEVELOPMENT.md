# HuaSideload developer guide

Everything for building your own watch apps and HuaSideload features. Installing the app, pairing and watch faces
are in the [README](../README.md).

## Contents
1. [Requirements](#1-requirements)
2. [Your own watch app](#2-your-own-watch-app)
   - [2.1 Huawei developer account and signing (once)](#21-huawei-developer-account-and-signing-once)
   - [2.2 Start from the sample](#22-start-from-the-sample)
   - [2.3 Build, bundle into the iPhone app, install on the watch](#23-build-bundle-into-the-iphone-app-install-on-the-watch)
   - [2.4 Talking to the phone](#24-talking-to-the-phone)
   - [2.5 Ready-made games: Dino, Flappy, Snake](#25-ready-made-games-dino-flappy-snake)
   - [2.6 The watch speaker in your features](#26-the-watch-speaker-in-your-features)
3. [Things to know when writing watch apps](#3-things-to-know-when-writing-watch-apps)
4. [Keeping your own features in a separate project](#4-keeping-your-own-features-in-a-separate-project)
5. [Troubleshooting for developers](#5-troubleshooting-for-developers)
6. [Project layout and how it works](#6-project-layout-and-how-it-works)

---

## 1. Requirements

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

Build the iPhone app yourself as described in the [README](../README.md#3-install-the-iphone-app-and-pair-the-watch)
(*Building it yourself*). If your watch apps will message the phone, use your own build, not the prebuilt IPA: the
sideloading tool may change the bundle ID.

---

## 2. Your own watch app

### 2.1 Huawei developer account and signing (once)

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
2. **Devices → Add:** type **Sports watch** (lite wearable), paste the UDID from HuaSideload (**Watch** tab → **Show identity** → **Copy UDID**).
3. **My projects → create a project → Add app:** HarmonyOS app, device **Sports watch**, package name (e.g. `com.yourname.huasideload.sample`). Don't select any capabilities or permissions.
4. **Profiles → Add:** that app, type **Debug**, your certificate, your watch → download the `.p7b` → save it named after the app's package, e.g. `signing/profiles/com.yourname.huasideload.sample.p7b`.

Repeat steps 3 and 4 for every new watch app. The key, certificate and device stay the same.

**c) `signing/signing.env`:** copy `signing/signing.env.example` and fill in the file names. Nothing in `signing/` is committed to git.

### 2.2 Start from the sample

```bash
cp -R watch-apps/sample watch-apps/my-app
```
- `entry/src/main/config.json` → set `bundleName` to your package name from AppGallery Connect.
- `resources/base/element/string.json` → `app_name` (the name shown on the watch, at most 30 characters).
- Icon: `python3 tools/make-app-icon.py watch-apps/my-app 2A6FDB` (a colored disc), or put your own `icon.png` (114×114) and `icon_small.png` (41×41) in `resources/base/media/`.

### 2.3 Build, bundle into the iPhone app, install on the watch

```bash
tools/build-watch-app.sh watch-apps/my-app     # → WatchApps/My App.bin  (file name = app_name)
./generate.sh                                  # adds the new .bin to the Xcode project
```
1. Run the iPhone app from Xcode again.
2. **Install** tab → **Watch apps** → **"Install … on the watch"**.
3. When it's done the app appears in the watch's app list. To remove it: **Show apps on the watch** → **Delete**.

At the end `build-watch-app.sh` checks the package against the watch installer's rules with
`tools/check-watch-bin.py`. If it says "WILL NOT INSTALL", the reason is printed right there.

**Updating:** **increase** `version.code` in `config.json` (the watch refuses the same or a lower version), build, install again.

### 2.4 Talking to the phone

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
Add it in `WatchFeatures.load()`, or keep it in a separate project as described in section 4.
A feature can also put its own sections on the **Features** tab (`sections()`).

### 2.5 Ready-made games: Dino, Flappy, Snake

`watch-apps/` has three games for 466×466 round screens, tested on a HUAWEI WATCH GT 3 SE. Signed builds can't be
shared (a `.bin` is signed for one developer's watches), so build them with your own signing like any other app:

| Game | Folder | What it is |
|---|---|---|
| **Dino** | `watch-apps/dino` | endless runner: tap to jump over cacti and birds, day and night mode |
| **Flappy** | `watch-apps/flappy` | tap to fly through the pipes; after a new best score it sends `{"t": "flappy", "s": score, "b": best}` to the iPhone (a `bridge.js` example: handle it in your own `WatchFeature`, section 2.4) |
| **Snake** | `watch-apps/snake` | Nokia-style snake on a round arena without walls; it turns toward your tap |

For each game:
1. AppGallery Connect: add an app with your own package name (e.g. `com.yourname.huasideload.dino`) and a debug profile for it (section 2.1, steps 3 and 4).
2. Put that package name into the game's `entry/src/main/config.json` → `bundleName`.
3. Build: `HUASIDELOAD_LEGACY_IMAGES=1 tools/build-watch-app.sh watch-apps/dino`, then `./generate.sh` and run the iPhone app again (section 2.3).

`HUASIDELOAD_LEGACY_IMAGES=1` keeps only one copy of every image in the package (the compiler writes each image
twice), which makes Dino about 40% smaller. The images are generated by `tools/make_sprites.py` / `tools/make_assets.py`
inside each game folder.

### 2.6 The watch speaker in your features

How the watch speaker works for users is in the [README, section 3.1](../README.md#31-listening-on-the-watch-speaker).
`host.speaker` (`WatchSpeaker`) tells when the speaker is on and off (`onPlaying`, `onEnded`), can ring the watch
(`ring()`), and reports gestures with the watch's volume panel (`onVolumeGesture`): down a little and right back up,
that twice, or down to the bottom and up again. The watch never changes the volume on its own, so a feature can use
them to control its own player, e.g. through the Spotify Web API. (The mic button can't be used reliably: in quiet
parts of a song the watch mutes its mic on its own too.)

---

## 3. Things to know when writing watch apps

All of these were found by testing on the watch. Most of them give no error message at all: just "103",
a black screen or a frozen watch.

| Symptom | Cause | Fix |
|---|---|---|
| Install fails with **103** | no `icon_small.bin` in the icon folder | add `resources/base/media/icon_small.png` (41×41) |
| Install fails with **103** | your watch's UDID is not in the profile / wrong package name / wrong certificate | check 2.1; `tools/check-watch-bin.py` inspects the package |
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

## 4. Keeping your own features in a separate project

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

## 5. Troubleshooting for developers

Pairing and watch face problems are in the [README's troubleshooting](../README.md#5-troubleshooting).

- **Install fails with 103:** see the table in section 3. Start with `python3 tools/check-watch-bin.py WatchApps/X.bin`.
- **"Could not reach the phone (is HuaSideload open?)":** the iPhone app must be running and connected to the watch. It also works in the background, but not after you force-quit it.
- **Live log on a Mac** (unlock the iPhone first; every line starts with `[HuaSideload]`):
  ```bash
  xcrun devicectl list devices    # shows your iPhone's identifier, e.g. 00008110-001A2B3C4D5E6F70
  xcrun devicectl device process launch --device 00008110-001A2B3C4D5E6F70 --console com.yourname.huasideload
  ```
  `-e '{"HUASIDELOAD_DIAG":"1"}'` also asks the watch for its supported commands, capabilities and music storage.

---

## 6. Project layout and how it works

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
  WatchFacePackage.swift   reads .hwt watch face packages (minimal zip reader)
  WatchSpeaker.swift       iPhone audio on the watch speaker (CallKit incoming call + HFP), volume gestures
  HelloFeature.swift       sample feature
  Localization.swift       English / Turkish
watch-apps/sample/         sample watch app (lite wearable JS)
watch-apps/dino|flappy|snake/   ready-made games
WatchFaces/                ready-made watch faces (.hwt), bundled into the iPhone app
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
- **Watch faces:** only `watchface.bin` from inside the `.hwt` is uploaded, as type 1, with a name and version (like Gadgetbridge).
- **Notifications:** sent as an app notification (type `0x7F`) with the app's ID (tag `0x11`); the watch shows its built-in icon for apps it knows. After pairing, the app also offers its own icon to the watch's notification icon service (`in.huawei.NotificationAppIcon` over P2P; the watch asks for the sizes it wants, file type 7). Tested on a GT 3 SE: it takes the icons but keeps showing the default icon. Gadgetbridge reports that uploaded notification icons need HarmonyOS 5 or later.
- **Messaging with watch apps:** Wear Engine P2P (`0x34`). A watch app's identity is `package + "_" + base64(EC public key of the developer certificate)`; `WatchAppCatalog` derives it from the profile inside the `.bin`.
- **UDID:** the watch sends its UDID on every pairing, in tag `0x05` of the security negotiation reply (`0x01/0x33`).
- **Background:** `CBCentralManager` with a restore identifier (CoreBluetooth state restoration). If iOS terminates the app, it keeps the pending connection and relaunches the app for the watch's events; the app then sets up the channel and pairs again with the saved key.
- **Watch speaker:** a CallKit *incoming* call (`reportNewIncomingCall`); after it is answered on the watch, `AVAudioSession` `.playAndRecord` with `.allowBluetooth` (HFP) and `.mixWithOthers`, playing silence to keep the route open. Needs `UIBackgroundModes` `voip` (without it CallKit refuses the call) and `audio`. The volume panel on the watch shows up as `outputVolume` changes on the iPhone.

The build pipeline is the command-line equivalent of DevEco Studio's "legacy lite" build:
ace-loader (webpack lite) → restool → haptobin_tool → hap-sign-tool `sign-app -inForm bin`.
