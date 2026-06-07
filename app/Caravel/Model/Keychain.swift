// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import Foundation
import Security

// Keychain stores the account passphrase for the logged-in cloud session — so
// "Sync now" is one tap and survives restart. A single item (one controller per
// the "sync is sync" rule). "Log out" deletes it. This is the iOS half of the
// cross-platform contract (docs/cloud-sync.md §4): same Keychain APIs as the mac
// client (caravel-mac/app/Caravel/Keychain.swift), accessible after first unlock.
//
// On iOS the item is placed in a Keychain Access Group shared between the app and
// the PacketTunnel extension, so the extension can read the passphrase to re-sync
// if it ever needs to. The access group is the app's team-prefixed group; Xcode
// fills the $(AppIdentifierPrefix) prefix from the signing team.
enum Keychain {
    private static let service = Shared.keychainService
    private static let account = Shared.keychainAccount
    // Shared access group — keep in sync with both targets' entitlements
    // (keychain-access-groups). The team prefix is added by the system at runtime,
    // so we do NOT hardcode it here; an unspecified group falls back to the app's
    // default group, which still works for the app target alone.
    static let accessGroup = "org.pharosvpn.caravel.shared"

    private static func base(includeGroup: Bool = true) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Only attach the access group when the entitlement is present; otherwise
        // the query fails with errSecMissingEntitlement. We try with-group first
        // and fall back below.
        if includeGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    /// store saves (or replaces) the passphrase, readable after first unlock.
    static func store(_ secret: String) {
        for includeGroup in [true, false] {
            SecItemDelete(base(includeGroup: includeGroup) as CFDictionary)
            var add = base(includeGroup: includeGroup)
            add[kSecValueData as String] = Data(secret.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    /// read returns the stored passphrase, or nil if not logged in.
    static func read() -> String? {
        for includeGroup in [true, false] {
            var q = base(includeGroup: includeGroup)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data,
               let s = String(data: data, encoding: .utf8) {
                return s
            }
        }
        return nil
    }

    /// delete clears the stored passphrase (log out).
    static func delete() {
        for includeGroup in [true, false] {
            SecItemDelete(base(includeGroup: includeGroup) as CFDictionary)
        }
    }

    static var hasCredential: Bool { read() != nil }
}
