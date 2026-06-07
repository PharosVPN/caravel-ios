# Building the PharosVPN iOS client (caravel-ios)

A SwiftUI app + a `NEPacketTunnelProvider` network extension that runs the shared
Go engine (gomobile `Caravel.xcframework`). Project files are generated with
[xcodegen]; the engine is built separately in the `caravel` core repo.

## Prerequisites

```sh
brew install xcodegen          # project generator
brew install resvg             # (only to regenerate the app icon)
```

Xcode 15+ and an **Apple Developer account** (a paid/free Team that can provision
NetworkExtension + App Groups). NetworkExtension does **not** run in the iOS
simulator — to actually connect you must build to a real device.

## 1. Generate the Xcode project

```sh
cd app
xcodegen generate          # writes app/Caravel.xcodeproj
```

This creates two targets:

- **Caravel** — the SwiftUI app (bundle id `org.pharosvpn.caravel`).
- **Tunnel** — the packet-tunnel extension (`org.pharosvpn.caravel.tunnel`),
  embedded into the app.

## 2. Set your Team

The project is **sign-ready** but ships with no Team (you supply it):

- Either edit `app/project.yml` → `settings.base.DEVELOPMENT_TEAM: "ABCDE12345"`
  (your 10-character Apple Team ID) and re-run `xcodegen`,
- Or open `Caravel.xcodeproj` in Xcode and, for **both** targets, pick your Team
  under **Signing & Capabilities** (Automatic signing).

Both targets need these capabilities provisioned under your Team (the entitlements
files already declare them — Xcode/automatic signing registers them):

- **Network Extensions** → *Packet Tunnel Provider*
- **App Groups** → `group.org.pharosvpn.caravel`
- **Keychain Sharing** → `org.pharosvpn.caravel.shared`

> **Two one-time gotchas for a signed device / TestFlight build** (simulator
> builds need neither — they're unsigned):
>
> 1. **The Team gets wiped on regen.** `project.yml` keeps `DEVELOPMENT_TEAM: ""`,
>    so every `xcodegen` blanks the team in the (gitignored) `.xcodeproj`. The
>    local project is generated with `DEVELOPMENT_TEAM = NJV3R6ZFF6`; **re-set it
>    after any regen** (Xcode → Signing & Capabilities, or
>    `sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = NJV3R6ZFF6;/' app/Caravel.xcodeproj/project.pbxproj`).
> 2. **The App Group must be registered once.** `xcodebuild`
>    `-allowProvisioningUpdates` can create App IDs but **cannot create App
>    Groups**. Open the project in Xcode → a target → **Signing & Capabilities**
>    → **App Groups** → enable `group.org.pharosvpn.caravel` once. Until then a
>    device/TestFlight build won't sign.

## 3. Link the Go engine (`Caravel.xcframework`)

The shared engine is built in the **caravel** repo (not here):

```sh
cd ../caravel
./build-bindings.sh ios        # → caravel/dist/Caravel.xcframework
```

Then wire it into this app:

```sh
cd ../caravel-ios
./scripts/link-core.sh         # copies the xcframework into Frameworks/ + regenerates
```

> Until the engine is linked, the app **still builds and runs** against a
> no-engine fallback: import / list / map / controller card / disable / logout all
> work; **Connect** and **Cloud sync** report "engine not linked". See `NOTES.md`.

## 4. Build & run

- **Simulator (UI only, no VPN):**
  ```sh
  cd app
  xcodebuild build -project Caravel.xcodeproj -scheme Caravel \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO
  ```
- **Device (full VPN):** open `app/Caravel.xcodeproj` in Xcode, select your
  device, build & run. The first **Connect** triggers the system VPN-permission
  prompt; allow it once.

## 5. App icon

The maroon-beacon AppIcon set is checked in. To regenerate from the SVG:

```sh
./scripts/make-icons.sh        # needs resvg or rsvg-convert (alpha-preserving)
```

(Do **not** rasterize the icon with `qlmanage` — it flattens transparency to
white. The 1024 marketing icon is flattened to opaque RGB, as the App Store
requires.)

## Versioning & release

Fleet-wide semver convention (same as `helm`/`node`/`relay`/`caravel`):

- Repo-root **`VERSION`** (bare semver, e.g. `0.1.0`) is the source of truth.
- **`scripts/bump-version.sh [major|minor|patch] [--tag]`** bumps it (asks if no
  part given; `--tag` also makes a `vX.Y.Z` git tag).
- `project.yml`'s `MARKETING_VERSION` mirrors `VERSION`; the release script passes
  `MARKETING_VERSION=$(tr -d '[:space:]' < VERSION)` to `xcodebuild`.

```sh
./scripts/bump-version.sh minor      # 0.1.0 -> 0.2.0
./scripts/release.sh                 # validate VERSION + signing prereqs, print TestFlight steps
./scripts/release.sh --archive       # also run xcodebuild archive + export .ipa
```

iOS ships via **TestFlight / App Store**, *not* a downloadable artifact — there is
**no GitHub release** for this repo. `scripts/release.sh` documents the archive →
`-exportArchive` → TestFlight path and validates the signing prerequisites above.
Pre-alpha: the engine facade isn't built yet and device signing is blocked on the
App Group registration, so no device/TestFlight build has shipped.

## Layout

```
app/
  project.yml                 xcodegen spec (two targets)
  Caravel/                    the app
    CaravelApp.swift          @main
    Core/                     engine seam + view-model + NE manager
      CaravelCore.swift       the ONE place that calls the gomobile engine
      TunnelController.swift  view-model (ports caravel-mac)
      TunnelManager.swift     NETunnelProviderManager (start/stop the VPN)
    Model/                    Profiles, Regions, Keychain, TunnelState
    Views/                    ContentView, ControlPanel, LandMap, SyncSheet
    Shared/SharedConstants    App Group / bundle ids / store paths
    Resources/land.geojson    offline world for the map
    Assets.xcassets           AppIcon + AccentColor
    Info.plist / *.entitlements
  Tunnel/                     the packet-tunnel extension
    PacketTunnelProvider.swift
    Info.plist / *.entitlements
Frameworks/                   Caravel.xcframework lands here (link-core.sh)
scripts/                      make-icons.sh, link-core.sh
```

[xcodegen]: https://github.com/yonaskolb/XcodeGen
