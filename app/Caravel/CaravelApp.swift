// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import SwiftUI

@main
struct CaravelApp: App {
    @StateObject private var tunnel = TunnelController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tunnel)
                .onAppear { tunnel.start() }
        }
    }
}
