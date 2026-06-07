// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import Foundation

// TunnelStatus is the high-level connection state shown in the UI. It mirrors the
// mac client's enum and maps from NEVPNStatus in TunnelManager.
enum TunnelStatus: Equatable {
    case disconnected, connecting, connected, disconnecting, reasserting

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting…"
        case .reasserting: return "Reconnecting…"
        }
    }
}

// TunnelState mirrors the JSON the PacketTunnel extension writes to the shared
// App Group state file while connected (Shared.stateFile). The app polls it for
// the live endpoint / protocol / byte counters — the iOS equivalent of the mac
// worker's state.json.
struct TunnelState: Codable, Equatable {
    var profile: String
    var proto: String?
    var endpoint: String
    var since: String?
    var rx: Int64?
    var tx: Int64?

    // protoLabel is the live data-plane protocol for display, or nil.
    var protoLabel: String? {
        switch proto {
        case "amneziawg": return "AmneziaWG"
        case "xray-reality", "xray": return "XRay/REALITY"
        default: return nil
        }
    }
}

// ControllerStatus mirrors Core.controllerStatus — the cloud session's liveness.
// reachable is informational (the data plane runs without it).
struct ControllerStatus: Codable, Equatable {
    var reachable: Bool
    var last_synced_at: String?
    var relay: String?
    var controller: Endpoint?

    struct Endpoint: Codable, Equatable {
        var label: String
        var city: String?
        var lat: Double
        var lon: Double
    }

    // lastSyncedAgo renders the last-sync time compactly (e.g. "3m ago").
    var lastSyncedAgo: String? {
        guard let s = last_synced_at,
              let t = ISO8601DateFormatter().date(from: s) else { return nil }
        let d = Date().timeIntervalSince(t)
        if d < 60 { return "just now" }
        if d < 3600 { return "\(Int(d / 60))m ago" }
        if d < 86_400 { return "\(Int(d / 3600))h ago" }
        return "\(Int(d / 86_400))d ago"
    }
}

// humanBytes formats a byte count compactly (e.g. "1.2 MB").
func humanBytes(_ n: Int64) -> String {
    let u: Double = 1024
    if n < 1024 { return "\(n) B" }
    var x = Double(n), i = 0
    let units = ["KB", "MB", "GB", "TB", "PB"]
    repeat { x /= u; i += 1 } while x >= u && i < units.count
    return String(format: "%.1f %@", x, units[i - 1])
}
