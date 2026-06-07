// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import Foundation

// Shared constants for the app + its packet-tunnel extension. The two processes
// share the profile store and the live tunnel state through an App Group
// container, so both must agree on the identifiers below.
enum Shared {
    // App Group container shared by the app and the PacketTunnel extension. Both
    // entitlements list this group; the profile store + state file live inside it.
    static let appGroup = "group.org.pharosvpn.caravel"

    // Bundle identifiers (mirror the mac client's org.pharosvpn.caravel).
    static let appBundleID = "org.pharosvpn.caravel"
    static let tunnelBundleID = "org.pharosvpn.caravel.tunnel"

    // Keychain — the account passphrase for the logged-in cloud session. Shared
    // between the app and the extension via the keychain access group so the
    // extension can re-auth/sync if needed. (See Keychain.swift.)
    static let keychainService = "org.pharosvpn.caravel"
    static let keychainAccount = "account-passphrase"

    // groupContainer is the App Group's shared on-disk container, or nil if the
    // entitlement is missing (e.g. running un-provisioned). Profiles + state live
    // under here so the extension reads the same store the app writes.
    static var groupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    // storeDir is the profile store directory inside the App Group container —
    // the iOS equivalent of the mac client's Application Support/PharosVPN/profiles.
    static var storeDir: URL {
        let base = groupContainer
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PharosVPN", isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
    }

    // stateFile is the live tunnel state the extension writes while connected and
    // the app polls for status (rx/tx/proto/endpoint) — the iOS equivalent of the
    // mac worker's /Library/Application Support/PharosVPN/state.json.
    static var stateFile: URL {
        let base = groupContainer
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PharosVPN", isDirectory: true)
            .appendingPathComponent("state.json")
    }
}
