# caravel-ios

PharosVPN mobile client — iOS implementation in Swift.

> Part of [PharosVPN](https://github.com/PharosVPN) — see [`docs/BUILD.md`](https://github.com/PharosVPN/docs/blob/main/BUILD.md) for the platform roadmap.

## Architecture

Shared Go core (via `gomobile`) + native SwiftUI.

- `go/` — shared core (VPN engine, profile store, gRPC sync, crypto) — *to be symlinked from coxswain repo or as a submodule*
- `app/` — iOS app (SwiftUI, Keychain integration, Network Extension)
- `Podfile` — CocoaPods dependencies (if using pods; otherwise SPM)

## Milestones (C1–C7)

See [`docs/BUILD.md`](https://github.com/PharosVPN/docs/blob/main/BUILD.md) caravel section:
- **C1:** Skeleton, validate gomobile architecture, VPN permission plumbing
- **C2:** Local profile store + `.pharos` parsing
- **C3:** VPN engine (AmneziaWG, then XRay) + protocol registry
- **C4:** Sources (file import, QR, self-contained QR)
- **C5:** Account sync (enrollment, gRPC, E2E decrypt, multi-device)
- **C6:** MDM managed config + posture detection
- **C7:** Role-gated admin subset

## Status

🚧 Pre-alpha — scaffold. See [`docs/DESIGN.md`](https://github.com/PharosVPN/docs/blob/main/DESIGN.md) §3 for the platform architecture.

## Build

(To be filled in once C1 architecture is locked.)

## License

AGPL-3.0-or-later. Contributions under the DCO (`git commit -s`).
