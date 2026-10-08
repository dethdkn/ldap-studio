//
//  NewConnectionSheet.swift
//  ldap-studio
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A numeric text field that updates its binding on every keystroke.
///
/// `TextField(value:format:)` only commits when the user presses Return or
/// the field loses focus, and clicking a button on macOS doesn't move focus
/// — so typing "5" into the timeout and clicking Save or Test straight away
/// silently kept the old value (the timeout stayed at its default no matter
/// what was typed). Text that isn't a whole number binds as 0, which the
/// sheet's validation rejects, so the buttons disable rather than saving a
/// stale value.
private struct IntegerField: View {
    let title: String
    @Binding var value: Int
    @State private var text: String

    init(_ title: String, value: Binding<Int>) {
        self.title = title
        _value = value
        _text = State(initialValue: String(value.wrappedValue))
    }

    private static func parse(_ text: String) -> Int {
        Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    var body: some View {
        TextField(title, text: $text)
            .onChange(of: text) { _, newText in
                let parsed = Self.parse(newText)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                // Changed from outside the field (the Stepper, or the
                // encryption picker resetting the port) — mirror it, unless
                // the text already means the same number so an empty or
                // half-typed field isn't rewritten under the cursor.
                if Self.parse(text) != newValue { text = String(newValue) }
            }
    }
}

struct NewConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionStore.self) private var store

    private let existingConnection: SavedConnection?
    private let connectionID: UUID

    /// How the connection is encrypted. LDAPS wraps the socket in TLS from
    /// the start (port 636); StartTLS connects in the clear on 389 and
    /// upgrades. `SavedConnection` stores this as two bools.
    enum Encryption: String, CaseIterable, Identifiable {
        case none = "None"
        case ldaps = "LDAPS"
        case startTLS = "StartTLS"

        var id: Self { self }
    }

    enum Page: String, CaseIterable, Identifiable {
        case server = "Server"
        case authentication = "Authentication"
        case network = "Network"
        case ssh = "SSH Tunnel"

        var id: Self { self }

        var icon: String {
            switch self {
            case .server: "server.rack"
            case .authentication: "person.badge.key"
            case .network: "network"
            case .ssh: "point.3.connected.trianglepath.dotted"
            }
        }
    }

    // MARK: State

    @State private var page: Page = .server

    // Server
    @State private var name: String
    @State private var host: String
    @State private var port: Int
    @State private var encryption: Encryption
    @State private var baseDN: String
    @State private var isReadOnly: Bool

    // Authentication
    @State private var authentication: LDAPAuthentication
    @State private var bindDN: String
    @State private var password: String
    @State private var saslAuthID: String
    @State private var saslRealm: String
    @State private var clientCertificateBookmark: Data?
    @State private var clientKeyBookmark: Data?

    // Network
    @State private var chaseReferrals: Bool
    @State private var timeoutSeconds: Int
    /// Kept from the existing connection unless the user clears it here.
    @State private var trustedCertSHA256: String?

    // SSH tunnel
    @State private var useSSHTunnel: Bool
    @State private var sshHost: String
    @State private var sshPort: Int
    @State private var sshUsername: String
    @State private var sshAuthentication: SSHAuthentication
    @State private var sshPassword: String
    @State private var sshPrivateKeyBookmark: Data?
    @State private var sshHostKeySHA256: String?
    @State private var pendingSSHHostKey: String?

    // Test Connection
    @State private var testSucceeded = false
    @State private var testResultMessage = ""
    @State private var isShowingTestResult = false
    @State private var isTesting = false

    init(existingConnection: SavedConnection? = nil) {
        self.existingConnection = existingConnection
        connectionID = existingConnection?.id ?? UUID()

        let encryption: Encryption
        if existingConnection?.useSSL == true {
            encryption = .ldaps
        } else if existingConnection?.useStartTLS == true {
            encryption = .startTLS
        } else {
            encryption = .none
        }

        _name = State(initialValue: existingConnection?.name ?? "")
        _host = State(initialValue: existingConnection?.host ?? "")
        _port = State(initialValue: existingConnection?.port ?? 389)
        _encryption = State(initialValue: encryption)
        _baseDN = State(initialValue: existingConnection?.baseDN ?? "")
        _isReadOnly = State(initialValue: existingConnection?.isReadOnly ?? false)

        _authentication = State(initialValue: existingConnection?.authentication ?? .simple)
        _bindDN = State(initialValue: existingConnection?.bindDN ?? "")
        _password = State(initialValue: existingConnection.flatMap { KeychainService.readPassword(for: $0.id) } ?? "")
        _saslAuthID = State(initialValue: existingConnection?.saslAuthID ?? "")
        _saslRealm = State(initialValue: existingConnection?.saslRealm ?? "")
        _clientCertificateBookmark = State(initialValue: existingConnection?.clientCertificateBookmark)
        _clientKeyBookmark = State(initialValue: existingConnection?.clientKeyBookmark)

        _chaseReferrals = State(initialValue: existingConnection?.chaseReferrals ?? false)
        _timeoutSeconds = State(initialValue: existingConnection?.timeoutSeconds ?? 15)
        _trustedCertSHA256 = State(initialValue: existingConnection?.trustedCertSHA256)

        _useSSHTunnel = State(initialValue: existingConnection?.useSSHTunnel ?? false)
        _sshHost = State(initialValue: existingConnection?.sshHost ?? "")
        _sshPort = State(initialValue: existingConnection?.sshPort ?? 22)
        _sshUsername = State(initialValue: existingConnection?.sshUsername ?? "")
        _sshAuthentication = State(initialValue: existingConnection?.sshAuthentication ?? .password)
        _sshPassword = State(initialValue: existingConnection.flatMap { KeychainService.readSSHPassword(for: $0.id) } ?? "")
        _sshPrivateKeyBookmark = State(initialValue: existingConnection?.sshPrivateKeyBookmark)
        _sshHostKeySHA256 = State(initialValue: existingConnection?.sshHostKeySHA256)
    }

    // MARK: Validation & model

    private static let validPorts = 1...65535
    private static let validTimeouts = 1...300

    /// A tunnel forwards to one fixed server, so GSSAPI (which derives its
    /// service principal from the real hostname) and referral chasing (which
    /// can point anywhere) can't be combined with it.
    private var hasIncompatibleTunnelOptions: Bool {
        useSSHTunnel && (chaseReferrals || authentication == .gssapi)
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !host.isEmpty,
              Self.validPorts.contains(port),
              Self.validTimeouts.contains(timeoutSeconds),
              !hasIncompatibleTunnelOptions else { return false }
        if useSSHTunnel {
            return !sshHost.isEmpty && !sshUsername.isEmpty && Self.validPorts.contains(sshPort)
        }
        return true
    }

    private var builtConnection: SavedConnection {
        SavedConnection(
            id: connectionID,
            name: name,
            host: host,
            port: port,
            useSSL: encryption == .ldaps,
            useStartTLS: encryption == .startTLS,
            baseDN: baseDN,
            bindDN: bindDN,
            trustedCertSHA256: trustedCertSHA256,
            bookmarks: existingConnection?.bookmarks ?? [],
            savedFilters: existingConnection?.savedFilters ?? [],
            isFavorite: existingConnection?.isFavorite ?? false,
            isReadOnly: isReadOnly,
            chaseReferrals: chaseReferrals,
            timeoutSeconds: timeoutSeconds,
            authentication: authentication,
            saslAuthID: saslAuthID,
            saslRealm: saslRealm,
            clientCertificateBookmark: clientCertificateBookmark,
            clientKeyBookmark: clientKeyBookmark,
            useSSHTunnel: useSSHTunnel,
            sshHost: sshHost,
            sshPort: sshPort,
            sshUsername: sshUsername,
            sshAuthentication: sshAuthentication,
            sshPrivateKeyBookmark: sshPrivateKeyBookmark,
            sshHostKeySHA256: sshHostKeySHA256
        )
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                ScrollView {
                    pageContent
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 570)
        .alert(
            testSucceeded ? "Connection Successful" : "Connection Failed",
            isPresented: $isShowingTestResult
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage)
        }
        .alert(
            "Trust SSH Host Key?",
            isPresented: Binding(
                get: { pendingSSHHostKey != nil },
                set: { if !$0 { pendingSSHHostKey = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingSSHHostKey = nil }
            Button("Trust and Test Again") {
                sshHostKeySHA256 = pendingSSHHostKey
                pendingSSHHostKey = nil
                test()
            }
        } message: {
            Text("Verify this fingerprint with the server administrator (or `ssh-keygen -lf` on its host key) before trusting it:\n\n\(SSHHostKeyFingerprint.openSSH(fromHex: pendingSSHHostKey ?? ""))")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: existingConnection == nil ? "network.badge.shield.half.filled" : "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(existingConnection == nil ? "New Connection" : "Edit Connection")
                    .font(.title3.bold())
                Text("Configure directory access, authentication, and routing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(page == item ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 170)
        .background(.quaternary.opacity(0.35))
    }

    private var footer: some View {
        HStack {
            if isTesting { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Test Connection") { test() }
                .disabled(!isValid || isTesting)
            Button(existingConnection == nil ? "Add Connection" : "Save Changes") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
        }
        .padding(16)
    }

    // MARK: Pages

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .server: serverPage
        case .authentication: authenticationPage
        case .network: networkPage
        case .ssh: sshPage
        }
    }

    private var serverPage: some View {
        card("Directory Server", "server.rack") {
            TextField("Connection name", text: $name)
            HStack {
                TextField("Host", text: $host)
                IntegerField("Port", value: $port)
                    .frame(width: 100)
            }
            Picker("Encryption", selection: $encryption) {
                ForEach(Encryption.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: encryption) { _, value in
                port = value == .ldaps ? 636 : 389
            }
            TextField("Base DN", text: $baseDN, prompt: Text("dc=example,dc=com"))
            Toggle("Read-only — block every write operation", isOn: $isReadOnly)
        }
    }

    private var authenticationPage: some View {
        card("Bind & Authentication", "person.badge.key") {
            Picker("Method", selection: $authentication) {
                ForEach(LDAPAuthentication.allCases) { Text($0.title).tag($0) }
            }
            switch authentication {
            case .simple:
                TextField("Bind DN", text: $bindDN, prompt: Text("Leave empty for anonymous bind"))
                SecureField("Password", text: $password)
            case .external:
                hint("EXTERNAL authenticates with a client certificate during TLS.")
                fileRow("Client certificate", bookmark: $clientCertificateBookmark, types: ["pem", "crt", "cer"])
                fileRow("Private key", bookmark: $clientKeyBookmark, types: ["pem", "key"])
            case .gssapi:
                TextField("Authentication ID", text: $saslAuthID, prompt: Text("Kerberos principal (optional)"))
                TextField("Realm", text: $saslRealm, prompt: Text("Optional"))
                hint("Uses the current macOS Kerberos ticket.")
            case .digestMD5:
                TextField("Authentication ID", text: $saslAuthID, prompt: Text("Username"))
                TextField("Realm", text: $saslRealm, prompt: Text("Optional"))
                SecureField("Password", text: $password)
            }
        }
    }

    private var networkPage: some View {
        card("Connection Behavior", "network") {
            Toggle("Chase LDAP referrals", isOn: $chaseReferrals)
            hint("Allows the directory to redirect searches to another LDAP server.")
            LabeledContent("Operation timeout") {
                HStack(spacing: 6) {
                    IntegerField("Seconds", value: $timeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                    Text("seconds").foregroundStyle(.secondary)
                    Stepper("", value: $timeoutSeconds, in: Self.validTimeouts)
                        .labelsHidden()
                }
            }
            if let fingerprint = trustedCertSHA256 {
                LabeledContent("Trusted certificate") {
                    HStack {
                        Text(Self.shortFingerprint(fingerprint))
                            .font(.system(.caption, design: .monospaced))
                        Button("Clear") { trustedCertSHA256 = nil }
                    }
                }
            }
        }
    }

    private var sshPage: some View {
        card("Bastion / Jump Host", "point.3.connected.trianglepath.dotted") {
            Toggle("Connect through an SSH tunnel", isOn: $useSSHTunnel)
            Group {
                HStack {
                    TextField("SSH host", text: $sshHost)
                    IntegerField("Port", value: $sshPort)
                        .frame(width: 100)
                }
                TextField("Username", text: $sshUsername)
                Picker("Authentication", selection: $sshAuthentication) {
                    ForEach(SSHAuthentication.allCases) { Text($0.title).tag($0) }
                }
                if sshAuthentication == .password {
                    SecureField("SSH password", text: $sshPassword)
                } else {
                    fileRow("Private key", bookmark: $sshPrivateKeyBookmark, types: ["pem", "key"])
                }
                if let fingerprint = sshHostKeySHA256 {
                    LabeledContent("Trusted host key") {
                        HStack {
                            Text(SSHHostKeyFingerprint.openSSH(fromHex: fingerprint))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(SSHHostKeyFingerprint.openSSH(fromHex: fingerprint))
                            Button("Clear") { sshHostKeySHA256 = nil }
                        }
                    }
                }
                hint("The tunnel runs inside LDAP Studio; no external ssh process is launched.")
                if hasIncompatibleTunnelOptions {
                    Label(
                        authentication == .gssapi
                            ? "GSSAPI derives its service principal from the direct server endpoint and cannot be combined with a local SSH forward."
                            : "Referral targets cannot be safely routed through this single-server SSH tunnel. Turn off referral chasing.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .disabled(!useSSHTunnel)
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(
        _ title: String,
        _ icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            Divider()
            content()
        }
        .padding(18)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.7)) }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func fileRow(_ title: String, bookmark: Binding<Data?>, types: [String]) -> some View {
        LabeledContent(title) {
            HStack {
                Text(bookmark.wrappedValue == nil ? "Not selected" : "Selected")
                    .foregroundStyle(bookmark.wrappedValue == nil ? .secondary : .primary)
                Button("Choose…") { chooseFile(types, bookmark) }
                if bookmark.wrappedValue != nil {
                    Button("Clear") { bookmark.wrappedValue = nil }
                }
            }
        }
    }

    private func chooseFile(_ types: [String], _ bookmark: Binding<Data?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bookmark.wrappedValue = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    // MARK: Actions

    private func save() {
        let connection = builtConnection
        KeychainService.savePassword(password, for: connection.id)
        KeychainService.saveSSHPassword(sshPassword, for: connection.id)
        if existingConnection == nil {
            store.add(connection)
        } else {
            store.update(connection)
        }
        dismiss()
    }

    private func test() {
        let connection = builtConnection
        Task {
            isTesting = true
            defer { isTesting = false }
            do {
                // The SSH password lives in the field until Save writes it to
                // the Keychain, so `ldapOptions` (which reads the Keychain)
                // would hand back a stale one.
                var options = connection.ldapOptions
                options.sshPassword = sshPassword
                try await testConnection(
                    host: host,
                    port: UInt16(clamping: port),
                    useSsl: encryption == .ldaps,
                    startTLS: encryption == .startTLS,
                    pinnedCertSHA256: trustedCertSHA256,
                    options: options,
                    bindDn: bindDN,
                    password: password
                )
                testSucceeded = true
                testResultMessage = "Successfully connected and authenticated to \(host)."
            } catch let ConnectionError.SSHHostKeyUntrusted(_, _, fingerprint) {
                if sshHostKeySHA256 == nil {
                    pendingSSHHostKey = fingerprint
                    return
                }
                // Already pinned and no longer matching: never a one-click
                // "trust" — it can mean the connection is being intercepted.
                testSucceeded = false
                testResultMessage = """
                    The SSH host key has changed since you trusted it. It is now \
                    \(SSHHostKeyFingerprint.openSSH(fromHex: fingerprint)).

                    This can mean the server was rebuilt, or that someone is intercepting the connection. \
                    If you know the change is legitimate, clear the trusted host key above and test again.
                    """
            } catch {
                testSucceeded = false
                testResultMessage = "\(error)"
            }
            isShowingTestResult = true
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
