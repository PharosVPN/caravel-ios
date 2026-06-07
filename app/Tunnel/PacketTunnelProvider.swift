// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import Foundation
import NetworkExtension
import os.log

// PacketTunnelProvider is the NEPacketTunnelProvider that runs the PharosVPN data
// plane. On startTunnel it reads the target (bundle / profile / protocol) the app
// put in the provider configuration, sets the utun network settings, grabs the
// tunnel's file descriptor, and hands it to the Go engine via CaravelCore.connect.
// The Go userspace AmneziaWG/XRay engine then owns the utun for the session.
//
// This mirrors the mac worker's role (cmd/caravel-mac), but in-process: there is
// no CLI/daemon on iOS — the extension IS the worker, and it talks to the same
// shared engine through the same CaravelCore seam the app uses.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: "org.pharosvpn.caravel.tunnel", category: "provider")
    private var session: CaravelSession?
    private var stateTimer: DispatchSourceTimer?
    private var startedAt = Date()
    private var targetProfile = ""

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        CaravelCore.initStore()

        // The app stashes what to connect in the provider configuration.
        let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let bundle = conf[TunnelManager.Key.bundle] as? String ?? ""
        let profile = conf[TunnelManager.Key.profile] as? String ?? ""
        let proto = conf[TunnelManager.Key.proto] as? String ?? "auto"
        targetProfile = profile.isEmpty ? bundle : profile
        log.info("startTunnel bundle=\(bundle, privacy: .public) profile=\(profile, privacy: .public) proto=\(proto, privacy: .public)")

        guard !bundle.isEmpty else {
            completionHandler(CoreError(message: "no profile selected"))
            return
        }

        // Configure the utun. AllowedIPs route everything through the tunnel; the
        // engine handles the real per-node allowed-IPs internally. We use a
        // link-local-ish address; the engine binds the real tunnel address from the
        // profile. (The Go side reads/writes packets on the fd we pass it.)
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.86.0.2"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = 1420
        // Public resolvers so DNS works inside the tunnel by default.
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                self.log.error("setTunnelNetworkSettings failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
                return
            }
            // Hand the utun file descriptor to the engine.
            guard let fd = self.tunnelFileDescriptor() else {
                completionHandler(CoreError(message: "could not obtain the tunnel file descriptor"))
                return
            }
            do {
                self.session = try CaravelCore.connect(bundleName: bundle, profileName: profile,
                                                       protoPref: proto, tunFd: fd)
                self.startedAt = Date()
                self.startStateWriter(profile: self.targetProfile)
                self.log.info("engine connected")
                completionHandler(nil)
            } catch {
                self.log.error("engine connect failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        log.info("stopTunnel reason=\(reason.rawValue, privacy: .public)")
        stateTimer?.cancel()
        stateTimer = nil
        session?.stop()
        session = nil
        try? FileManager.default.removeItem(at: Shared.stateFile)
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        // The app reads live state from the shared state file; no IPC needed today.
        completionHandler?(nil)
    }

    // MARK: - Live state

    // startStateWriter periodically copies the engine's stats into the shared App
    // Group state file the app polls (Shared.stateFile) — the iOS equivalent of
    // the mac worker's state.json writer.
    private func startStateWriter(profile: String) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in self?.writeState(profile: profile) }
        timer.resume()
        stateTimer = timer
    }

    private func writeState(profile: String) {
        var st = TunnelState(profile: profile, proto: nil, endpoint: "",
                             since: ISO8601DateFormatter().string(from: startedAt), rx: 0, tx: 0)
        // The engine reports {rx,tx,proto,endpoint} as JSON.
        if let json = session?.statsJSON(),
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            st.rx = (obj["rx"] as? NSNumber)?.int64Value ?? Int64(obj["rx"] as? Int ?? 0)
            st.tx = (obj["tx"] as? NSNumber)?.int64Value ?? Int64(obj["tx"] as? Int ?? 0)
            st.proto = obj["proto"] as? String
            st.endpoint = obj["endpoint"] as? String ?? ""
        }
        if let data = try? JSONEncoder().encode(st) {
            try? data.write(to: Shared.stateFile, options: .atomic)
        }
    }

    // tunnelFileDescriptor returns the utun file descriptor backing this provider's
    // packet flow, which the Go engine reads/writes packets on.
    //
    // NEPacketTunnelProvider doesn't expose the fd publicly. The established
    // technique (wireguard-apple) reads it via KVC off packetFlow
    // ("socket.fileDescriptor"); if that ever stops working we fall back to
    // scanning the process's open fds for the utun control socket. Both are kept
    // so the engine always gets a valid fd.
    private func tunnelFileDescriptor() -> Int32? {
        // Preferred: KVC off the packet flow's underlying socket.
        if let fd = (packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32), fd >= 0 {
            return fd
        }
        // Fallback: find the highest open utun fd by name (getsockopt UTUN_OPT_IFNAME).
        let utunPrefix = "utun"
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd in (0..<Int32(getdtablesize())).reversed() {
            var len = socklen_t(name.count)
            let ret = getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &name, &len)
            if ret == 0, String(cString: name).hasPrefix(utunPrefix) {
                return fd
            }
        }
        return nil
    }
}
