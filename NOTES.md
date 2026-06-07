# NOTES — iOS client implementation notes & open gaps

Tracking the gaps between this iOS client and the shared Go core, and the
assumptions the Swift side makes about the engine. The rule is: **do not modify
`caravel/go`** — gaps are recorded here for the core author to close.

## 1. The gomobile `Core` / `Session` facade does not exist yet (BLOCKING for connect/sync)

The task + `docs/cloud-sync.md` describe an exported `core` surface:

```
Core.initStore(dir)
Core.importBundle(path) -> name
Core.syncAndStore(pharosidData, email, pass) -> name   // login/sync; REPLACE-ALL
Core.listProfiles() -> JSON
Core.controllerStatus(bundleName) -> JSON
Core.reachable(pharosidData, timeoutMs) -> Bool
Core.logout() -> count
Core.connect(bundleName, profileName, protoPref, tunFd) -> Session
Session.stats() -> JSON
Session.stop()
```

But `caravel/go/core.go` is still the **C1 stub** (`Tunnel`/`NewTunnel`/`Start`/
`Stop` + `Version`). The packages exist to build the facade on top of
(`profile.Parse`, `sync.Fetch`, `sync.Reachable`, `deviceid.Parse`, `vp.Engine`),
but the facade functions themselves are **not implemented**. The human is building
this in parallel; `caravel/dist/Caravel.xcframework` does not exist yet.

**How this client copes:** every engine call goes through one seam,
`app/Caravel/Core/CaravelCore.swift`, guarded by `#if canImport(Caravel)`:

- **Framework absent (today):** the app builds + runs against a pure-Swift
  fallback. Import (file copy + native `.pharos` parse), profile listing, the map,
  the controller pin (from the bundle's embedded coords + the `.synced` marker),
  disable/delete, and logout-purge all work. **Connect** and **cloud sync** report
  a clear "engine not linked" error (the UI shows an "engine not linked" chip).
- **Framework present (once built + linked):** the same calls hit the real engine.
  Run `./scripts/link-core.sh` to copy `caravel/dist/Caravel.xcframework` into
  `Frameworks/` and wire it into `project.yml`.

### Assumed gomobile symbol names

`CaravelCore.swift` assumes standard gomobile name-mangling for `package core`:
package-level funcs become `Core<Func>` and the session type becomes
`CoreSession`. So it calls `CoreInitStore`, `CoreImportBundle`, `CoreSyncAndStore`,
`CoreListProfiles`, `CoreControllerStatus`, `CoreReachable`, `CoreLogout`,
`CoreConnect` (→ `CoreSession`), `CoreVersion`, and `session.stats()` /
`session.stop()`. **If the core author names the exported funcs differently**
(e.g. a wrapper type `Core` with methods), adjust the calls inside the
`#if canImport(Caravel)` branches of `CaravelCore.swift` — that file is the only
place that names engine symbols.

Signatures assumed (gomobile bridges `error` to a trailing `NSError**` /
throwing, `[]byte` to `Data`, `int` to `Int`/`Int32`):

| Swift call | expected Go |
|---|---|
| `CoreInitStore(dir, &err)` | `func InitStore(dir string) error` |
| `CoreImportBundle(path, &err) -> String` | `func ImportBundle(path string) (string, error)` |
| `CoreSyncAndStore(Data, email, pass, &err) -> String` | `func SyncAndStore(pharosid []byte, email, pass string) (string, error)` |
| `CoreListProfiles() -> String` | `func ListProfiles() string` |
| `CoreControllerStatus(name, &err) -> String` | `func ControllerStatus(bundle string) (string, error)` |
| `CoreReachable(Data, Int) -> Bool` | `func Reachable(pharosid []byte, timeoutMs int) bool` |
| `CoreLogout() -> Int` | `func Logout() int` |
| `CoreConnect(bundle, profile, proto, Int32, &err) -> CoreSession?` | `func Connect(bundle, profile, proto string, tunFd int32) (*Session, error)` |
| `CoreSession.stats() -> String` | `func (s *Session) Stats() string` |
| `CoreSession.stop()` | `func (s *Session) Stop()` |

## 2. utun file descriptor handoff (verify on device)

`PacketTunnelProvider.tunnelFileDescriptor()` gets the utun fd via KVC
(`packetFlow.value(forKeyPath: "socket.fileDescriptor")`), the technique
wireguard-apple uses, with a getsockopt(UTUN_OPT_IFNAME) scan fallback. This is
**not testable in the simulator** (no NetworkExtension) and KVC on a private
property can break across OS releases — verify on a real device once the engine
lands. If the engine prefers to own the utun itself (open its own fd from the
provider), this handoff changes; coordinate the `Connect(tunFd)` contract.

## 3. Live stats shape

The state writer (`PacketTunnelProvider.writeState`) expects `Session.stats()` to
return JSON `{rx, tx, proto, endpoint}` (per the task surface). It tolerates
missing fields. If the engine emits different keys, adjust `writeState`.

## 4. `controllerStatus` / `reachable` without the engine

When the engine is absent, the controller card + map pin are assembled from
on-disk data alone (`.synced` marker + the bundle's `control` coords); `reachable`
is shown as `false` because we don't perform the TLS dial without the engine. Once
linked, `CoreControllerStatus` / `CoreReachable` drive these for real. Per
`cloud-sync.md §7`, reachability is probed on **foreground**, not on a timer.

## 5. Signing — Team required + App Group must be registered

`project.yml` sets `DEVELOPMENT_TEAM: ""`. NetworkExtension + App Groups +
Keychain sharing **cannot be code-signed without a real Team**, so the app builds
for the **simulator** un-signed (verified) but a **device** build needs the Team
set and the App Group / NE capabilities provisioned. See `BUILD.md`.

**Two human one-time steps before a signed device / TestFlight build will sign:**

1. **Keep the Team set (`NJV3R6ZFF6`).** `project.yml` intentionally has
   `DEVELOPMENT_TEAM: ""`, so a fresh `xcodegen` **wipes the team** out of the
   (gitignored) `app/Caravel.xcodeproj`. After any `xcodegen` regen, re-set it —
   in Xcode (Signing & Capabilities, Automatic) or with:
   ```sh
   cd app && sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = NJV3R6ZFF6;/' \
     Caravel.xcodeproj/project.pbxproj   # then verify both targets
   ```
2. **Register the App Group `group.org.pharosvpn.caravel` once.** `xcodebuild`'s
   auto-provisioning (`-allowProvisioningUpdates`) can create the App **IDs** but
   **cannot create App Groups**. Open `app/Caravel.xcodeproj` in Xcode → select a
   target → **Signing & Capabilities** → **App Groups** → add/enable
   `group.org.pharosvpn.caravel` (this registers it on the Apple account). Until
   then, a **simulator** build works (no signing) but a **device / TestFlight**
   build fails to sign with a missing-App-Group provisioning error.

Once both are done, archive + export for TestFlight with `scripts/release.sh`
(it validates these prerequisites and prints the `xcodebuild archive` /
`-exportArchive` commands). There is **no GitHub-release artifact** for iOS.

## 7. Versioning (fleet semver convention)

This repo follows the fleet-wide convention used by `helm`/`node`/`relay`/`caravel`:

- Repo-root `VERSION` (bare semver, e.g. `0.1.0`) is the source of truth.
- `scripts/bump-version.sh [major|minor|patch] [--tag]` bumps it (asks if no part
  is given; `--tag` also creates `vX.Y.Z`).
- `project.yml`'s `MARKETING_VERSION` mirrors `VERSION` (currently `0.1.0`); the
  release/build script passes `MARKETING_VERSION=$(tr -d '[:space:]' < VERSION)`
  to `xcodebuild` so the build always uses the source-of-truth version.
- `scripts/release.sh` documents the TestFlight path. Pre-alpha (`0.1.0`): the
  engine facade isn't built yet (§1) and device signing is blocked on the App
  Group registration (§5), so no device/TestFlight build has shipped.

## 6. Cosmetics / future parity

- The mac app's gentle 30s controller poll is intentionally **dropped** on iOS
  (battery) — we probe on foreground only.
- No QR-code import yet (mac doesn't have it either; it's a future caravel
  milestone, C4).
- iPad uses the same single-screen layout (map hero + floating panel); a true
  split layout could be added later but isn't required for parity.
