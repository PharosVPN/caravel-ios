// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import SwiftUI
import UniformTypeIdentifiers

// ContentView is the app's single screen: the signature world map as the hero,
// with a control panel (profiles, the connect button, live stats, the controller
// card) below it. It is the iOS counterpart of caravel-mac's ContentView — same
// information, re-laid-out for a phone (the mac's side-by-side HSplitView becomes
// a map-on-top / panel-below stack, draggable as a sheet-like scroll).
struct ContentView: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.scenePhase) private var scenePhase

    static let teal = Color(red: 0.31, green: 0.82, blue: 0.77)
    static let maroon = Color(red: 0.353, green: 0.122, blue: 0.169) // #5A1F2B
    private var connected: Bool { tunnel.status == .connected }

    @State private var showImporter = false
    @State private var showSync = false
    @State private var pendingPharosid: Data?
    @State private var pendingPharosidName = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // The map fills the screen; the panel floats over its lower portion.
            LandMap(pins: tunnel.mapPins, arcs: tunnel.mapArcs, connected: connected)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                ControlPanel(showImporter: $showImporter,
                             onLogin: openLoginPicker)
                    .frame(maxWidth: 560)
            }
        }
        .preferredColorScheme(.dark)
        .background(Color(red: 0.03, green: 0.04, blue: 0.07).ignoresSafeArea())
        // .pharos import (document picker → core importBundle).
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType.pharosProfile, UTType.data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                tunnel.importBundle(url)
            }
        }
        // Cloud login: pick a .pharosid, then collect the passphrase.
        .sheet(isPresented: $showSync) {
            SyncSheet(pharosidData: pendingPharosid ?? Data(),
                      pharosidName: pendingPharosidName) { email, pass in
                if let data = pendingPharosid {
                    tunnel.syncFromController(pharosidData: data, email: email, password: pass)
                }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { tunnel.onForeground() }
        }
        .onChange(of: tunnel.needsLogin) { need in
            // Sync-now with no stored passphrase → reopen the login sheet for the
            // current cloud bundle.
            if need, let b = tunnel.cloudInfo?.bundle,
               let data = try? Data(contentsOf: Profiles.deviceIDPath(b)) {
                pendingPharosid = data
                pendingPharosidName = b + ".pharosid"
                showSync = true
                tunnel.needsLogin = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title2).foregroundStyle(Self.teal)
            Text("PharosVPN").font(.title2.weight(.bold)).foregroundStyle(.white)
            Spacer()
            // Document import (a .pharos file).
            Button { showImporter = true } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .foregroundStyle(Self.teal)
            .accessibilityLabel("Import a .pharos profile")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.07).opacity(0.92), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    // openLoginPicker presents a document picker for a `.pharosid`, then opens the
    // passphrase sheet. (UIKit picker via a SwiftUI representable below.)
    private func openLoginPicker() {
        DeviceIDPicker.present { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                tunnel.lastError = "could not read \(url.lastPathComponent)"
                return
            }
            pendingPharosid = data
            pendingPharosidName = url.lastPathComponent
            showSync = true
        }
    }
}

// UTType for the .pharos profile (DESIGN §9 / profile.MIMEType). Declared in the
// app's Info.plist too, so the OS routes "Open in PharosVPN" here.
extension UTType {
    static let pharosProfile = UTType(exportedAs: "org.pharosvpn.profile",
                                      conformingTo: .data)
    static let pharosDevice = UTType(exportedAs: "org.pharosvpn.deviceid",
                                     conformingTo: .data)
}
