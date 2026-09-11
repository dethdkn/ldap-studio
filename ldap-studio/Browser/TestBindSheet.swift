//
//  TestBindSheet.swift
//  ldap-studio
//
//  "Is this the user's actual password?" — a quick diagnostic straight
//  from the tree instead of copy-pasting a DN into a separate LDAP
//  client. Read-only: it only ever opens a connection, attempts one bind
//  as the entry's DN, and closes it — never touches data, so it works
//  even on a read-only connection.
//

import SwiftUI

struct TestBindSheet: View {
    let connection: SavedConnection
    let dn: String

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isTesting = false
    @State private var result: Result<Void, Error>?
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Test Bind")
                .font(.headline)
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(dn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isPasswordFocused)
                    .onSubmit(test)

                statusLine
            }
            .padding()
            .frame(minHeight: 84, alignment: .top)

            Divider()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Test") { test() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isTesting)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear { isPasswordFocused = true }
    }

    @ViewBuilder
    private var statusLine: some View {
        if isTesting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Binding…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let result {
            switch result {
            case .success:
                Label("Password is correct.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .failure(let error):
                Label((error as? LocalizedError)?.errorDescription ?? "\(error)",
                      systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func test() {
        guard !password.isEmpty, !isTesting else { return }
        isTesting = true
        result = nil
        Task {
            do {
                try await testConnection(
                    host: connection.host,
                    port: UInt16(clamping: connection.port),
                    useSsl: connection.useSSL,
                    startTLS: connection.useStartTLS,
                    pinnedCertSHA256: connection.trustedCertSHA256,
                    bindDn: dn,
                    password: password
                )
                result = .success(())
            } catch {
                result = .failure(error)
            }
            isTesting = false
        }
    }
}
