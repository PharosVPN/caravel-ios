// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import Foundation
import NetworkExtension

// TunnelManager owns the system VPN configuration (a NETunnelProviderManager) and
// drives the PacketTunnel extension. Where the mac client shells out to a root
// helper, iOS routes through NetworkExtension: the app saves a provider profile
// (one approval prompt the first time), then starts/stops the tunnel and passes
// the chosen profile + protocol to the extension via the provider configuration.
//
// The extension (PacketTunnelProvider) reads that configuration, grabs the utun
// file descriptor, and runs the Go engine via CaravelCore.connect.
final class TunnelManager {
    private var manager: NETunnelProviderManager?

    // Keys in providerConfiguration the extension reads to know what to connect.
    enum Key {
        static let bundle = "bundle"      // store name (the .pharos file)
        static let profile = "profile"    // named profile within the bundle
        static let proto = "proto"        // "auto" | "amneziawg" | "xray"
        static let appGroup = "appGroup"  // App Group id (store + state location)
    }

    // load fetches (or creates) the saved provider manager. Returns the current
    // NEVPNStatus so the caller can seed its UI.
    func load() async -> NEVPNStatus {
        let mgr = await loadOrCreateManager()
        manager = mgr
        return mgr.connection.status
    }

    // status is the current NEVPNStatus, mapped by the caller to TunnelStatus.
    var status: NEVPNStatus { manager?.connection.status ?? .invalid }

    // statusPublisherObject is the NEVPNConnection whose status notifications the
    // controller observes (NEVPNStatusDidChange).
    var connectionObject: NEVPNConnection? { manager?.connection }

    // connect saves the chosen target into the provider configuration, enables the
    // tunnel, and starts it. The first start surfaces the system VPN-permission
    // prompt; subsequent starts are silent.
    func connect(bundle: String, profile: String, proto: String) async throws {
        let mgr: NETunnelProviderManager
        if let existing = manager {
            mgr = existing
        } else {
            mgr = await loadOrCreateManager()
        }
        manager = mgr

        let proto0 = (mgr.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto0.providerBundleIdentifier = Shared.tunnelBundleID
        // serverAddress is shown in Settings; use a friendly label, not a secret.
        proto0.serverAddress = "PharosVPN"
        proto0.providerConfiguration = [
            Key.bundle: bundle,
            Key.profile: profile,
            Key.proto: proto,
            Key.appGroup: Shared.appGroup,
        ]
        mgr.protocolConfiguration = proto0
        mgr.localizedDescription = "PharosVPN"
        mgr.isEnabled = true

        try await mgr.saveToPreferences()
        // A freshly-saved config must be reloaded before it can start.
        try await mgr.loadFromPreferences()
        try mgr.connection.startVPNTunnel()
    }

    // disconnect stops the tunnel (the extension tears the engine down).
    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    // loadOrCreateManager returns the app's single provider manager, creating it
    // if none is saved yet.
    private func loadOrCreateManager() async -> NETunnelProviderManager {
        let all = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        if let existing = all.first { return existing }
        let mgr = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Shared.tunnelBundleID
        proto.serverAddress = "PharosVPN"
        mgr.protocolConfiguration = proto
        mgr.localizedDescription = "PharosVPN"
        return mgr
    }
}
