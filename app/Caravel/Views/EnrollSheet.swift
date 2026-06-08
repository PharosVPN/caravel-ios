// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import SwiftUI

// EnrollSheet collects a `pharosvpn://enroll` join link and an optional device
// name, then hands them to the view-model (CaravelCore.enroll). No passphrase:
// the engine generates this device's key on-device and the controller seals the
// profile to it. Mirrors SyncSheet (the account-login flow).
struct EnrollSheet: View {
    var onEnroll: (_ link: String, _ deviceName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var deviceName = ""

    private let teal = ContentView.teal
    private var validLink: Bool {
        link.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("pharosvpn://enroll")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("pharosvpn://enroll?…", text: $link, axis: .vertical)
                        .lineLimit(2...4)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                    TextField("Device name (optional)", text: $deviceName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Join link")
                } footer: {
                    Text("Paste the join link from your admin (or scan its QR and copy the link). No passphrase — your device key is generated here and your profile is sealed to it.")
                }
            }
            .navigationTitle("Enroll a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enroll") {
                        onEnroll(link.trimmingCharacters(in: .whitespacesAndNewlines),
                                 deviceName.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(!validLink)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(teal)
    }
}
