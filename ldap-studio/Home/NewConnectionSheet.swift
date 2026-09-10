//
//  NewConnectionSheet.swift
//  ldap-studio
//

import SwiftUI

struct NewConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionStore.self) private var store

    private let existingConnection: SavedConnection?

    /// How the connection is encrypted. LDAPS wraps the socket in TLS from
    /// the start (port 636); StartTLS connects in the clear on 389 and
    /// upgrades. `SavedConnection` stores this as two bools.
    enum Encryption: String, CaseIterable, Identifiable {
        case none = "None"
        case ldaps = "LDAPS"
        case startTLS = "StartTLS"
        var id: Self { self }
    }

    @State private var name: String
    @State private var host: String
    @State private var port: Int
    @State private var encryption: Encryption
    @State private var baseDN: String
    @State private var bindDN: String
    @State private var password: String
    /// Kept from the existing connection unless the user clears it here.
    @State private var trustedCertSHA256: String?

    @State private var testSucceeded = false
    @State private var testResultMessage = ""
    @State private var isShowingTestResult = false
    @State private var isTesting = false

    init(existingConnection: SavedConnection? = nil) {
        self.existingConnection = existingConnection
        _name = State(initialValue: existingConnection?.name ?? "")
        _host = State(initialValue: existingConnection?.host ?? "")
        _port = State(initialValue: existingConnection?.port ?? 389)
        let e: Encryption
        if existingConnection?.useSSL == true {
            e = .ldaps
        } else if existingConnection?.useStartTLS == true {
            e = .startTLS
        } else {
            e = .none
        }
        _encryption = State(initialValue: e)
        _baseDN = State(initialValue: existingConnection?.baseDN ?? "")
        _bindDN = State(initialValue: existingConnection?.bindDN ?? "")
        _password = State(initialValue: existingConnection.flatMap { KeychainService.readPassword(for: $0.id) } ?? "")
        _trustedCertSHA256 = State(initialValue: existingConnection?.trustedCertSHA256)
    }

    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty
    }

    private var builtConnection: SavedConnection {
        SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: name,
            host: host,
            port: port,
            useSSL: encryption == .ldaps,
            useStartTLS: encryption == .startTLS,
            baseDN: baseDN,
            bindDN: bindDN,
            trustedCertSHA256: trustedCertSHA256
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(existingConnection == nil ? "New Connection" : "Edit Connection")
                .font(.headline)
                .padding()

            Form {
                TextField("Name", text: $name)
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number)
                Picker("Encryption", selection: $encryption) {
                    ForEach(Encryption.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: encryption) { _, newValue in
                    port = newValue == .ldaps ? 636 : 389
                }
                TextField("Base DN", text: $baseDN)
                TextField("Bind DN", text: $bindDN)
                SecureField("Password", text: $password)

                if let fingerprint = trustedCertSHA256 {
                    LabeledContent("Trusted certificate") {
                        HStack {
                            Text(Self.shortFingerprint(fingerprint))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") { trustedCertSHA256 = nil }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Test") {
                    Task {
                        isTesting = true
                        defer { isTesting = false }
                        do {
                            try await testConnection(
                                host: host,
                                port: UInt16(clamping: port),
                                useSsl: encryption == .ldaps,
                                startTLS: encryption == .startTLS,
                                pinnedCertSHA256: trustedCertSHA256,
                                bindDn: bindDN,
                                password: password
                            )
                            testSucceeded = true
                            testResultMessage = "Successfully connected and bound to \(host)."
                        } catch {
                            testSucceeded = false
                            testResultMessage = "\(error)"
                        }
                        isShowingTestResult = true
                    }
                }
                .disabled(!isValid || isTesting)

                Button(existingConnection == nil ? "Add" : "Save") {
                    let connection = builtConnection
                    KeychainService.savePassword(password, for: connection.id)
                    if existingConnection == nil {
                        store.add(connection)
                    } else {
                        store.update(connection)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 420, height: 400)
        .alert(
            testSucceeded ? "Connection Successful" : "Connection Failed",
            isPresented: $isShowingTestResult
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage)
        }
    }

    /// "ab:cd:…:yz" from a bare hex string, first and last few bytes.
    static func shortFingerprint(_ hex: String) -> String {
        let pairs = stride(from: 0, to: hex.count, by: 2).map { i -> String in
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            return String(hex[start..<end])
        }
        guard pairs.count > 6 else { return pairs.joined(separator: ":") }
        return (pairs.prefix(3) + ["…"] + pairs.suffix(3)).joined(separator: ":")
    }
}

#Preview {
    NewConnectionSheet()
        .environment(ConnectionStore())
}
