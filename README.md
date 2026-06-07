<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".assets/logo-inverse.svg">
    <img src=".assets/logo.svg" alt="PharosVPN" width="120" height="120">
  </picture>
</p>

# caravel-ios

PharosVPN client for iOS — a SwiftUI app + a `NEPacketTunnelProvider` network
extension that runs the shared Go engine (gomobile `Caravel.xcframework`). It
mirrors the macOS client ([caravel-mac]) feature-for-feature: import & cloud
sync, named profiles, AmneziaWG / XRay-REALITY, cascades, the controller card,
live stats, and the signature offline world map.

## Architecture

```
SwiftUI app  ──(App Group: profile store + live state)──  PacketTunnel extension
     │                                                            │
     └──────────────── CaravelCore (the one engine seam) ─────────┘
                                   │
                       Caravel.xcframework (gomobile)
                    caravel/go: profile · sync · deviceid · vp
```

- **App** — UI, the profile store, the cloud-sync flow, and the map.
- **Tunnel extension** — obtains the utun fd and runs the userspace
  AmneziaWG/XRay engine via `CaravelCore.connect(…, tunFd:)`.
- **CaravelCore** — the single Swift file that talks to the gomobile engine
  (guarded by `#if canImport(Caravel)` so the app builds before the framework
  lands; see [`NOTES.md`](NOTES.md)).

## Features (parity with caravel-mac)

- Import a `.pharos` profile (document picker) **and** cloud sync (sign in with a
  `.pharosid` + account passphrase, stored in the Keychain).
- Sync = replace-all; one-tap **Sync now**; **Log out** clears the session and
  removes all cloud profiles.
- Named profiles; protocol picker for `both` profiles (Auto / AmneziaWG / XRay).
- Cascade egress path display.
- The **map**: "You" + node pins + a controller pin, dashed data-plane line and
  solid control-plane line (offline `land.geojson`, pinch/drag).
- Controller card: reachability dot, "Last synced … · via <relay>", Sync now,
  Log out.
- Live protocol + rx/tx indicator while connected.

## Build

See [`BUILD.md`](BUILD.md). In short:

```sh
cd app && xcodegen          # generate the project
# set your Apple Team in project.yml or Xcode (Signing & Capabilities)
../scripts/link-core.sh     # link Caravel.xcframework (once built in ../caravel)
# open Caravel.xcodeproj, build to a device
```

## License

Apache-2.0. Contributions under the DCO (`git commit -s`).

[caravel-mac]: https://github.com/PharosVPN/caravel-mac
