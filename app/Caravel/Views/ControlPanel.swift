// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import SwiftUI

// ControlPanel is the floating glass card over the lower map: the profile picker,
// the protocol control, the big Connect button, live stats, the egress route, and
// the controller card. It ports caravel-mac's sidebar `detail` + `controllerCard`
// into one scrollable iOS panel.
struct ControlPanel: View {
    @EnvironmentObject var tunnel: TunnelController
    @Binding var showImporter: Bool
    var onLogin: () -> Void

    private let teal = ContentView.teal
    private var connected: Bool { tunnel.status == .connected }
    private var busy: Bool { tunnel.busy }
    private var transitioning: Bool {
        tunnel.status == .connecting || tunnel.status == .disconnecting || tunnel.status == .reasserting
    }

    @State private var expanded = true
    @State private var showLogout = false
    @State private var pendingDelete: String?

    var body: some View {
        VStack(spacing: 0) {
            grabber
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        profilesSection
                        if tunnel.profiles.isEmpty { emptyState }
                        statusRow
                        protocolControl
                        connectButton
                        if connected, let s = tunnel.state { liveStats(s) }
                        if let path = tunnel.selectedInfo?.path { RouteCard(path: path) }
                        if tunnel.cloudInfo != nil { controllerCard }
                        if let err = tunnel.lastError { errorLine(err) }
                    }
                    .padding(18)
                }
                .frame(maxHeight: 460)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .confirmationDialog("Delete “\(pendingDelete ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                if let n = pendingDelete { tunnel.deleteProfile(n) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes this imported profile from this device. You can re-import it from its .pharos file.")
        }
    }

    private var grabber: some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() } } label: {
            Capsule().fill(.white.opacity(0.35)).frame(width: 38, height: 5)
                .padding(.vertical, 9).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Profiles

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PROFILES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showImporter = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("Add a .pharos file")
                Button { onLogin() } label: { Image(systemName: "icloud.and.arrow.down") }
                    .accessibilityLabel("Get from controller (account sync)")
                    .disabled(busy)
            }
            .foregroundStyle(teal)

            ForEach(tunnel.profiles) { p in profileRow(p) }
        }
    }

    private func profileRow(_ p: ProfileInfo) -> some View {
        Button {
            tunnel.selectedProfile = p.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: p.cloudSynced ? "cloud" : "globe")
                    .font(.caption).foregroundStyle(teal.opacity(0.85))
                Text(p.name)
                    .strikethrough(p.disabled)
                    .foregroundStyle(p.disabled ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer()
                if p.disabled {
                    Text("off").font(.caption2).foregroundStyle(.secondary)
                } else if let badge = p.protoBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(teal.opacity(0.15), in: Capsule())
                        .foregroundStyle(teal)
                } else {
                    Text(p.enc).font(.caption2).foregroundStyle(.secondary)
                }
                if p.id == tunnel.selectedProfile {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(teal)
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(p.id == tunnel.selectedProfile ? teal.opacity(0.12) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if p.cloudSynced {
                Button(p.disabled ? "Enable" : "Disable",
                       systemImage: p.disabled ? "play.circle" : "pause.circle") {
                    tunnel.setProfileDisabled(p.bundle, !p.disabled)
                }
                Text("Cloud-synced — can't be deleted, only disabled")
            } else {
                Button("Delete…", systemImage: "trash", role: .destructive) {
                    pendingDelete = p.bundle
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No profiles yet").font(.subheadline.weight(.semibold))
            Text("Import a .pharos file (the + button) or sign in to your account to sync from the controller.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Status + connect

    private var statusRow: some View {
        HStack(spacing: 9) {
            Circle().fill(connected ? .green : (transitioning ? .yellow : .gray))
                .frame(width: 10, height: 10)
                .shadow(color: connected ? .green : .clear, radius: 4)
            Text(tunnel.status.label).font(.headline)
            Spacer()
            if !CaravelCore.engineLinked {
                Text("engine not linked").font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var protocolControl: some View {
        if let info = tunnel.selectedInfo {
            if info.isBoth && !connected && !transitioning {
                Picker("Protocol", selection: $tunnel.proto) {
                    Text("Auto").tag("auto")
                    Text("AmneziaWG").tag("amneziawg")
                    Text("XRay").tag("xray")
                }
                .pickerStyle(.segmented)
                .disabled(busy)
            } else if let badge = info.protoBadge {
                HStack(spacing: 6) {
                    Image(systemName: badge == "XRay" ? "eye.slash" : "bolt.horizontal")
                        .font(.caption2).foregroundStyle(teal)
                    Text(badge == "XRay" ? "\(badge) · VLESS+REALITY (stealth)" : badge)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var connectButton: some View {
        Button(action: tunnel.toggle) {
            HStack {
                if transitioning { ProgressView().controlSize(.small).tint(.white) }
                Text(connected || tunnel.status == .disconnecting ? "Disconnect" : "Connect")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(connected || tunnel.status == .disconnecting ? .red : teal)
        .disabled(busy || tunnel.selectedProfile.isEmpty || (tunnel.selectedInfo?.disabled ?? false))
    }

    private func liveStats(_ s: TunnelState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(s.endpoint, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption).foregroundStyle(.secondary)
            if let proto = s.protoLabel {
                Label("via \(proto)", systemImage: proto.hasPrefix("XRay") ? "eye.slash" : "bolt.horizontal")
                    .font(.caption).foregroundStyle(teal)
            }
            HStack(spacing: 16) {
                Label(humanBytes(s.rx ?? 0), systemImage: "arrow.down").foregroundStyle(.green)
                Label(humanBytes(s.tx ?? 0), systemImage: "arrow.up").foregroundStyle(teal)
            }
            .font(.system(.caption, design: .monospaced))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Controller card

    private var controllerCard: some View {
        let c = tunnel.controller
        let reachable = tunnel.controllerReachable
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.caption).foregroundStyle(teal)
                Text("Controller").font(.caption.weight(.semibold))
                Spacer()
                Circle().fill(reachable ? Color.green : Color.gray).frame(width: 6, height: 6)
                Text(reachable ? "reachable" : "offline").font(.caption2).foregroundStyle(.secondary)
            }
            if let ago = c?.lastSyncedAgo {
                let via = c?.relay.map { " · via \($0)" } ?? ""
                Text("Last synced \(ago)\(via)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                Text("Not synced yet").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button { tunnel.syncNow() } label: { Label("Sync now", systemImage: "arrow.clockwise") }
                    .foregroundStyle(teal).disabled(busy)
                Spacer()
                Button { showLogout = true } label: { Label("Log out", systemImage: "rectangle.portrait.and.arrow.right") }
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Log out of this controller?", isPresented: $showLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { tunnel.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes all cloud-synced profiles from this device and forgets your passphrase. Imported profiles stay — you can sync again anytime.")
        }
    }

    private func errorLine(_ err: String) -> some View {
        Text(err).font(.caption2).foregroundStyle(.red).lineLimit(3)
    }
}

// RouteCard renders the egress chain (entry → [mid] → exit) for a cascade
// profile. Ported from caravel-mac's routeCard.
struct RouteCard: View {
    let path: PathView
    private let teal = ContentView.teal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond").font(.caption).foregroundStyle(teal)
                Text("Egress path · \(path.name)").font(.caption.weight(.semibold))
            }
            ForEach(Array(path.hops.enumerated()), id: \.offset) { i, h in
                HStack(spacing: 6) {
                    Image(systemName: roleIcon(h.role)).font(.caption2)
                        .foregroundStyle(h.role == "exit" ? .green : teal)
                    Text(h.city ?? h.name).font(.caption.weight(.medium))
                    Text(h.role).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if let ip = h.ips.first {
                        Text(ip).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if i < path.hops.count - 1 {
                    Image(systemName: "arrow.down").font(.system(size: 8)).foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func roleIcon(_ role: String) -> String {
        switch role {
        case "entry": return "arrow.right.to.line"
        case "exit": return "arrow.up.right.circle.fill"
        default: return "circle.dotted"
        }
    }
}
