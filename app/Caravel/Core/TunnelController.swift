// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import Combine
import Foundation
import NetworkExtension
import SwiftUI

// TunnelController is the app's view-model: it lists stored profiles, drives the
// PacketTunnel extension through TunnelManager, reads the live state file the
// extension writes, and runs the cloud-sync flow through CaravelCore. It is the
// iOS port of caravel-mac's TunnelController — same shape, NetworkExtension +
// gomobile engine instead of a root helper + CLI worker.
@MainActor
final class TunnelController: ObservableObject {
    @Published var status: TunnelStatus = .disconnected
    @Published var state: TunnelState?
    @Published var profiles: [ProfileInfo] = []
    @Published var selectedProfile: String = ""
    // Data-plane protocol: "auto" (prefer AmneziaWG), "amneziawg", or "xray".
    @Published var proto: String = "auto"
    @Published var lastError: String?
    // controller is the cloud session's liveness (reachable + last sync); nil
    // until refreshed or when no cloud profile is present.
    @Published var controller: ControllerStatus?
    // needsLogin asks the UI to open the sync sheet (no stored passphrase).
    @Published var needsLogin = false
    // busy is set during sync/login (a spinner) — separate from the tunnel status.
    @Published var busy = false

    private let tunnel = TunnelManager()
    private var stateTimer: Timer?
    private var statusObserver: AnyCancellable?

    // start wires up the engine store, loads profiles + the VPN config, and begins
    // observing tunnel status. Called once on appear.
    func start() {
        CaravelCore.initStore()
        reloadProfiles()
        Task {
            let neStatus = await tunnel.load()
            apply(neStatus: neStatus)
            observeStatus()
            // Foreground refresh of controller liveness (no timer — battery,
            // cloud-sync.md §7). The state poll is light (a local file) so it ticks.
            refreshController()
            startStatePolling()
        }
    }

    // observeStatus subscribes to NEVPNStatusDidChange. We observe ALL such
    // notifications (object: nil) rather than binding to one connection object, so
    // a manager (re)created/saved during connect() is still tracked — the bug of
    // missing status updates after the first save. Each tick re-reads the manager's
    // current status.
    private func observeStatus() {
        guard statusObserver == nil else { return }
        statusObserver = NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] note in
                guard let self else { return }
                let conn = note.object as? NEVPNConnection
                Task { @MainActor in
                    self.apply(neStatus: conn?.status ?? self.tunnel.status)
                }
            }
    }

    // apply maps an NEVPNStatus to the UI's TunnelStatus.
    private func apply(neStatus: NEVPNStatus) {
        switch neStatus {
        case .connected: status = .connected
        case .connecting: status = .connecting
        case .disconnecting: status = .disconnecting
        case .reasserting: status = .reasserting
        case .disconnected, .invalid: status = .disconnected
            state = nil
        @unknown default: status = .disconnected
        }
    }

    // startStatePolling reads the App Group state file the extension writes while
    // connected (endpoint / proto / rx / tx). Gentle 2s tick, like the mac client.
    private func startStatePolling() {
        pollState()
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollState() }
        }
    }

    // onForeground refreshes controller liveness + reloads profiles when the app
    // returns to the foreground (cloud-sync.md §7: probe on foreground, not on a
    // timer).
    func onForeground() {
        reloadProfiles()
        refreshController()
        Task { apply(neStatus: await tunnel.load()) }
    }

    private func pollState() {
        guard connected || status == .reasserting else {
            if state != nil { state = nil }
            return
        }
        if let data = try? Data(contentsOf: Shared.stateFile),
           let s = try? JSONDecoder().decode(TunnelState.self, from: data) {
            state = s
        }
    }

    // MARK: - Cloud session

    // cloudInfo is the cloud-synced bundle to act on — the selected one if it is
    // cloud, else the first cloud profile in the list.
    var cloudInfo: ProfileInfo? {
        if let s = selectedInfo, s.cloudSynced { return s }
        return profiles.first { $0.cloudSynced }
    }
    var loggedIn: Bool { Keychain.hasCredential }

    // refreshController re-reads the cloud bundle's controller status (reachable +
    // last sync + location) off the main actor.
    func refreshController() {
        guard let bundle = cloudInfo?.bundle else { controller = nil; return }
        Task.detached {
            let st = Self.controllerStatus(bundle: bundle)
            await MainActor.run { [weak self] in self?.controller = st }
        }
    }

    // controllerStatus reads Core.controllerStatus(bundle); falls back to the
    // local `.synced` marker + bundle control coords when the engine isn't linked,
    // so the controller card + map pin still render offline. nonisolated so it can
    // run off the main actor (Task.detached).
    nonisolated private static func controllerStatus(bundle: String) -> ControllerStatus? {
        if let json = CaravelCore.controllerStatusJSON(bundleName: bundle),
           let data = json.data(using: .utf8),
           let st = try? JSONDecoder().decode(ControllerStatus.self, from: data) {
            return st
        }
        return localControllerStatus(bundle: bundle)
    }

    // localControllerStatus assembles a controller status from on-disk data alone
    // (the `.synced` marker + the bundle's control coords) — used when the engine
    // isn't linked. reachable is left false (we don't dial without the engine).
    nonisolated private static func localControllerStatus(bundle: String) -> ControllerStatus? {
        var endpoint: ControllerStatus.Endpoint?
        if let info = Profiles.peek(Profiles.path(bundle)).first, let c = info.control {
            endpoint = .init(label: c.label, city: c.city, lat: c.lat, lon: c.lon)
        }
        var lastSynced: String?, relay: String?
        if let data = try? Data(contentsOf: Profiles.markerURL(bundle, "synced")),
           let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            lastSynced = m["synced_at"] as? String
            relay = m["relay"] as? String
        }
        if endpoint == nil && lastSynced == nil { return nil }
        return ControllerStatus(reachable: false, last_synced_at: lastSynced,
                                relay: relay, controller: endpoint)
    }

    // syncNow re-fetches the cloud bundle using the stored passphrase (one tap).
    // With no stored passphrase it asks the UI to open the sync sheet.
    func syncNow() {
        guard let info = cloudInfo else { return }
        guard let pass = Keychain.read() else { needsLogin = true; return }
        let pidPath = Profiles.deviceIDPath(info.bundle)
        guard let pidData = try? Data(contentsOf: pidPath) else {
            lastError = "missing device file for \(info.bundle)"
            return
        }
        busy = true
        lastError = nil
        Task.detached {
            let result = Self.runSync(pharosid: pidData, email: "", password: pass)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.busy = false
                if case .failure(let err) = result { self.lastError = "sync failed: \(err)" }
                self.reloadProfiles()
                self.refreshController()
            }
        }
    }

    // syncFromController fetches the account's e2e-encrypted profile through the
    // device's relay, decrypts it on-device, and stores it as a cloud profile —
    // the login flow (first sync). On success the passphrase is saved to the
    // Keychain so re-sync is one tap.
    func syncFromController(pharosidData: Data, email: String, password: String) {
        busy = true
        lastError = nil
        Task.detached {
            let result = Self.runSync(pharosid: pharosidData, email: email, password: password)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.busy = false
                switch result {
                case .failure(let err):
                    self.lastError = "sync failed: \(err)"
                case .success(let name):
                    Keychain.store(password) // logged in — one-tap re-sync from now on
                    self.needsLogin = false
                    self.reloadProfiles()
                    if let first = self.profiles.first(where: { $0.bundle == name }) {
                        self.selectedProfile = first.id
                    }
                    self.refreshController()
                    self.lastError = nil
                }
            }
        }
    }

    private enum SyncResult { case success(String), failure(String) }
    nonisolated private static func runSync(pharosid: Data, email: String, password: String) -> SyncResult {
        do {
            let name = try CaravelCore.syncAndStore(pharosidData: pharosid, email: email, password: password)
            return .success(name)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // logout disconnects a live cloud profile, purges every cloud bundle via the
    // engine (replace-all's logout half), and forgets the passphrase.
    func logout() {
        if connected || status == .reasserting { disconnect() }
        Task.detached {
            _ = CaravelCore.logout()
            await MainActor.run { [weak self] in
                guard let self else { return }
                Keychain.delete()
                self.controller = nil
                self.selectedProfile = ""
                self.reloadProfiles()
                self.lastError = nil
            }
        }
    }

    // MARK: - Profiles

    func reloadProfiles() {
        profiles = Profiles.list()
        if selectedProfile.isEmpty || !profiles.contains(where: { $0.id == selectedProfile }) {
            selectedProfile = profiles.first?.id ?? ""
        }
    }

    // importBundle adds a `.pharos` file (picked via a document picker) to the
    // store and selects it. The picker hands back a security-scoped URL.
    func importBundle(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = try CaravelCore.importBundle(at: url)
            reloadProfiles()
            if let first = profiles.first(where: { $0.bundle == name }) { selectedProfile = first.id }
            lastError = nil
        } catch {
            lastError = "import failed: \(error.localizedDescription)"
        }
    }

    // deleteProfile removes a file-imported bundle. Cloud-synced bundles can't be
    // deleted (they'd re-sync) — disable them instead.
    func deleteProfile(_ bundle: String) {
        guard !(profiles.first { $0.bundle == bundle }?.cloudSynced ?? false) else { return }
        Profiles.delete(bundle)
        if selectedInfo?.bundle == bundle { selectedProfile = "" }
        reloadProfiles()
        lastError = nil
    }

    func setProfileDisabled(_ bundle: String, _ disabled: Bool) {
        Profiles.setDisabled(bundle, disabled)
        reloadProfiles()
    }

    var selectedInfo: ProfileInfo? { profiles.first { $0.id == selectedProfile } }
    var connected: Bool { status == .connected }
    var controllerReachable: Bool { controller?.reachable ?? false }

    // clientCoord is an offline, no-permission approximation of "you": longitude
    // from the current timezone offset (no geolocation, no network).
    var clientCoord: GeoCoord {
        let lon = Double(TimeZone.current.secondsFromGMT()) / 3600.0 * 15.0
        return GeoCoord(lat: 30, lon: max(-179, min(179, lon)))
    }

    // mapPins: the "You" point + the controller pin + the selected profile's
    // placeable nodes (its egress chain, or its entry node(s)).
    var mapPins: [MapPin] {
        let nodes: [MapPin]
        if let path = selectedInfo?.path {
            nodes = path.hops.compactMap { h -> MapPin? in
                guard let c = h.coord else { return nil }
                return MapPin(coord: c, label: h.city ?? h.name, sub: h.role.capitalized,
                              active: h.role == "exit", kind: .node)
            }
        } else {
            nodes = (selectedInfo?.nodes ?? []).compactMap { n -> MapPin? in
                guard let c = n.coord else { return nil }
                return MapPin(coord: c, label: n.city ?? n.name, sub: n.activeIP,
                              active: n.activeIP != nil, kind: .node)
            }
        }
        var ctlPins: [MapPin] = []
        if let ctl = selectedInfo?.control {
            ctlPins.append(MapPin(coord: ctl.coord, label: ctl.city ?? ctl.label,
                                  sub: "Controller", active: controllerReachable, kind: .controller))
        }
        guard !nodes.isEmpty || !ctlPins.isEmpty else { return [] }
        return [MapPin(coord: clientCoord, label: "You", sub: nil, active: connected, kind: .client)]
            + ctlPins + nodes
    }

    // mapArcs: the data-plane path (dashed) — You → the hop chain — plus the
    // control-plane line (solid) — You → controller.
    var mapArcs: [MapArc] {
        var arcs: [MapArc] = []
        let coords: [GeoCoord]
        if let path = selectedInfo?.path {
            coords = path.hops.compactMap { $0.coord }
        } else {
            coords = (selectedInfo?.nodes ?? []).compactMap { $0.coord }
        }
        if !coords.isEmpty {
            let chain = [clientCoord] + coords
            arcs += (0..<(chain.count - 1)).map {
                MapArc(points: greatCircle(chain[$0], chain[$0 + 1]), style: .dataPlane)
            }
        }
        if let ctl = selectedInfo?.control {
            arcs.append(MapArc(points: greatCircle(clientCoord, ctl.coord), style: .controlPlane))
        }
        return arcs
    }

    // MARK: - Connect / disconnect

    func connect() {
        guard let info = selectedInfo else { lastError = "no profile selected"; return }
        lastError = nil
        status = .connecting // optimistic; NEVPNStatusDidChange takes over
        let bundle = info.bundle
        let pname = info.profileName
        let proto = self.proto
        Task {
            do {
                try await tunnel.connect(bundle: bundle, profile: pname, proto: proto)
                // The manager was (re)saved during connect — make sure we're seeded
                // with its current status (the observer catches later transitions).
                apply(neStatus: tunnel.status)
            } catch {
                self.lastError = "connect failed: \(error.localizedDescription)"
                self.status = .disconnected
            }
        }
    }

    func disconnect() {
        tunnel.disconnect()
    }

    func toggle() {
        if connected || status == .connecting || status == .reasserting { disconnect() } else { connect() }
    }
}
