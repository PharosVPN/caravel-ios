// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 The PharosVPN Authors

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// SyncSheet collects the account login for fetching a profile from the
// controller. The passphrase is handed to CaravelCore.syncAndStore, which uses it
// only locally to unwrap the e2e key — the controller only stores ciphertext.
// Ported from caravel-mac's syncSheetView.
struct SyncSheet: View {
    let pharosidData: Data
    let pharosidName: String
    var onSync: (_ email: String, _ password: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    private let teal = ContentView.teal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(pharosidName).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                } header: {
                    Text("Device file")
                }
                Section {
                    TextField("Account email (optional if in the bundle)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Account passphrase", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Sign in with your account passphrase. Your profile is decrypted on this device — the controller only stores ciphertext.")
                }
            }
            .navigationTitle("Sync from controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sync") {
                        onSync(email.trimmingCharacters(in: .whitespaces), password)
                        dismiss()
                    }
                    .disabled(password.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(teal)
    }
}

// DeviceIDPicker presents a UIKit document picker for a `.pharosid` device file
// and reports the chosen URL via a completion handler. (A callback-style picker
// is cleaner than a bound .fileImporter for the two-step login flow: pick file →
// then collect the passphrase.)
enum DeviceIDPicker {
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        var retain: Delegate?
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
            retain = nil
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { retain = nil }
    }

    static func present(onPick: @escaping (URL) -> Void) {
        let types: [UTType] = [.pharosDevice, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        let delegate = Delegate(onPick: onPick)
        delegate.retain = delegate
        picker.delegate = delegate
        picker.allowsMultipleSelection = false
        topViewController()?.present(picker, animated: true)
    }

    // topViewController walks to the foreground scene's top presented controller.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
