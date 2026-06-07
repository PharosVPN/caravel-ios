// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import Foundation

// CaravelCore is the single Swift seam over the shared Go engine (the gomobile
// `Caravel.xcframework`, Swift module `Caravel`). Both the app and the
// PacketTunnel extension talk to the engine ONLY through this type, so the
// gomobile surface is referenced in exactly one place.
//
// The exported `core` surface (docs + caravel/go), Swift module `Caravel`:
//
//   Core.initStore(dir)
//   Core.importBundle(path) -> name
//   Core.syncAndStore(pharosidData, email, pass) -> name   // login/sync; REPLACE-ALL
//   Core.listProfiles() -> JSON                            // bundles → profiles[] (+control)
//   Core.controllerStatus(bundleName) -> JSON              // {reachable,last_synced_at,relay,controller}
//   Core.reachable(pharosidData, timeoutMs) -> Bool
//   Core.logout() -> count
//   Core.connect(bundleName, profileName, protoPref, tunFd) -> Session
//   Session.stats() -> JSON  // {rx,tx,proto,endpoint}
//   Session.stop()
//
// The xcframework is built in parallel by the human (caravel/dist/Caravel.
// xcframework via `./build-bindings.sh ios`) and may not exist yet. So the engine
// calls are guarded by `#if canImport(Caravel)`: when the framework is linked the
// real engine runs; until then a thin local fallback keeps the app + store + UI
// fully functional (import, list, parse, controller pin) and reports a clear
// "engine not linked" error on connect. See NOTES.md.
#if canImport(Caravel)
import Caravel
#endif

// CoreError surfaces engine failures to the UI with a readable message.
struct CoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// CaravelSession is an active tunnel handle (wraps the gomobile `Session`). The
// PacketTunnel extension holds one for the life of the connection.
final class CaravelSession {
    #if canImport(Caravel)
    private let session: CoreSession
    init(_ s: CoreSession) { self.session = s }
    #else
    init() {}
    #endif

    // stats returns the live counters as raw JSON ({rx,tx,proto,endpoint}), or nil.
    func statsJSON() -> String? {
        #if canImport(Caravel)
        return session.stats()
        #else
        return nil
        #endif
    }

    func stop() {
        #if canImport(Caravel)
        session.stop()
        #endif
    }
}

enum CaravelCore {
    // engineLinked reports whether the gomobile framework is present in this build.
    static var engineLinked: Bool {
        #if canImport(Caravel)
        return true
        #else
        return false
        #endif
    }

    // version returns the linked core version (or "unlinked" before the framework
    // lands), handy for the About line + diagnostics.
    static var version: String {
        #if canImport(Caravel)
        return CoreVersion()
        #else
        return "unlinked"
        #endif
    }

    // initStore points the engine's profile store at the App Group container, so
    // the engine, the app, and the extension all read/write the same files. Call
    // once early in each process.
    static func initStore() {
        Profiles.ensureDir()
        #if canImport(Caravel)
        var err: NSError?
        CoreInitStore(Profiles.dir.path, &err)
        #endif
    }

    // importBundle adds a `.pharos` file to the store and returns the stored
    // bundle name. The engine validates + normalizes; the fallback copies the file
    // and derives the name (the store/parse logic lives in Profiles for the UI
    // either way).
    @discardableResult
    static func importBundle(at path: URL) throws -> String {
        #if canImport(Caravel)
        var err: NSError?
        let name = CoreImportBundle(path.path, &err)
        if let err { throw CoreError(message: err.localizedDescription) }
        return name
        #else
        return try fallbackImport(at: path)
        #endif
    }

    // syncAndStore performs login/sync: it dials the relay in the `.pharosid`,
    // authenticates, fetches + decrypts the account bundle, and stores it —
    // REPLACE-ALL (drops every prior cloud bundle first, cloud-sync.md §5). Returns
    // the stored bundle name. The passphrase never leaves the device for auth (the
    // device leaf authenticates); it only unwraps the e2e key locally.
    static func syncAndStore(pharosidData: Data, email: String, password: String) throws -> String {
        #if canImport(Caravel)
        var err: NSError?
        let name = CoreSyncAndStore(pharosidData, email, password, &err)
        if let err { throw CoreError(message: err.localizedDescription) }
        return name
        #else
        throw CoreError(message: "cloud sync needs the Caravel engine (link Caravel.xcframework — see BUILD.md)")
        #endif
    }

    // listProfiles returns the store's bundles flattened to profiles[] as JSON.
    // The UI prefers the local Profiles.list() (richer typed model), but this is
    // here for parity + engine-driven consumers.
    static func listProfilesJSON() -> String? {
        #if canImport(Caravel)
        return CoreListProfiles()
        #else
        return nil
        #endif
    }

    // controllerStatus returns {reachable,last_synced_at,relay,controller} JSON for
    // a cloud bundle, or nil. reachable is a short TLS dial — informational only.
    static func controllerStatusJSON(bundleName: String) -> String? {
        #if canImport(Caravel)
        return CoreControllerStatus(bundleName)
        #else
        return nil
        #endif
    }

    // reachable probes the relay named in a `.pharosid` with the device leaf (a
    // TLS handshake, no auth/fetch). Used on foreground / before sync — NOT polled
    // (cloud-sync.md §7, mind the battery).
    static func reachable(pharosidData: Data, timeoutMs: Int) -> Bool {
        #if canImport(Caravel)
        return CoreReachable(pharosidData, timeoutMs)
        #else
        return false
        #endif
    }

    // logout removes every cloud-synced bundle (each with a `.synced` marker) and
    // its sidecars, then returns how many were removed. The Keychain passphrase is
    // cleared by the caller. REPLACE-ALL's logout half (cloud-sync.md §3).
    @discardableResult
    static func logout() -> Int {
        #if canImport(Caravel)
        return Int(CoreLogout())
        #else
        return fallbackLogout()
        #endif
    }

    // prepare returns the engine's resolved network parameters for a profile as
    // JSON {address,mtu,dns,routes,endpoint,proto} — the PacketTunnel extension
    // configures NEPacketTunnelNetworkSettings from these before connect. nil
    // when the engine isn't linked (the caller falls back to defaults).
    static func prepareJSON(bundleName: String, profileName: String, protoPref: String) -> String? {
        #if canImport(Caravel)
        var err: NSError?
        let json = CorePrepare(bundleName, profileName, protoPref, &err)
        return err == nil ? json : nil
        #else
        return nil
        #endif
    }

    // connect brings up the tunnel for a named profile over the provided utun file
    // descriptor (the PacketTunnel extension's packet flow). protoPref is
    // "auto" | "amneziawg" | "xray". Returns a live Session. Engine-only.
    static func connect(bundleName: String, profileName: String,
                        protoPref: String, tunFd: Int32) throws -> CaravelSession {
        #if canImport(Caravel)
        var err: NSError?
        guard let s = CoreConnect(bundleName, profileName, protoPref, Int(tunFd), &err) else {
            throw CoreError(message: err?.localizedDescription ?? "engine failed to start the tunnel")
        }
        return CaravelSession(s)
        #else
        throw CoreError(message: "the VPN engine is not linked (build + link Caravel.xcframework — see BUILD.md / NOTES.md)")
        #endif
    }

    // MARK: - Fallback (no engine linked)

    // fallbackImport copies a `.pharos` into the store so the app remains useful
    // for browsing + the map before the engine lands. Cloud sync + connect still
    // require the engine.
    private static func fallbackImport(at src: URL) throws -> String {
        Profiles.ensureDir()
        let dest = Profiles.dir.appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest.deletingPathExtension().lastPathComponent
    }

    // fallbackLogout mirrors the engine's purge: remove every cloud-synced bundle
    // (`.synced` marker present) plus its `.pharos` / `.pharosid` / markers.
    private static func fallbackLogout() -> Int {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: Profiles.dir, includingPropertiesForKeys: nil)) ?? []
        var count = 0
        for url in items where url.pathExtension == "synced" {
            let base = url.deletingPathExtension().lastPathComponent
            for ext in ["pharos", "pharosid", "synced", "disabled"] {
                try? fm.removeItem(at: Profiles.dir.appendingPathComponent("\(base).\(ext)"))
            }
            count += 1
        }
        return count
    }
}
