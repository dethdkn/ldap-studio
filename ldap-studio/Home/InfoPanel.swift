//
//  InfoPanel.swift
//  ldap-studio
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InfoPanel: View {
    @Environment(ConnectionStore.self) private var store

    @State private var isPresentingNewConnection = false
    @State private var isCheckingForUpdates = false
    @State private var importNotice: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("LDAP Studio")
                    .font(.title2.bold())
                Text("Version \(appVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
                    isCheckingForUpdates = true
                    Task {
                        await UpdateChecker.shared.check(userInitiated: true)
                        isCheckingForUpdates = false
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
                .disabled(isCheckingForUpdates)
            }

            VStack(spacing: 10) {
                Button {
                    isPresentingNewConnection = true
                } label: {
                    Label("Add Connection…", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .sheet(isPresented: $isPresentingNewConnection) {
                    NewConnectionSheet()
                }
                Button {
                    importConnections()
                } label: {
                    Label("Import Connection…", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
            VStack(spacing: 4) {
                Text("© Ldap Studio")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .focusedSceneValue(\.connectionCommands, ConnectionCommands(
            addConnection: { isPresentingNewConnection = true },
            importConnection: { importConnections() }
        ))
        .alert(
            "Finish Importing",
            isPresented: Binding(
                get: { importNotice != nil },
                set: { if !$0 { importNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNotice ?? "")
        }
    }

    private func importConnections() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "lcf") ?? .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else { return }

            if url.pathExtension.lowercased() == "lcf" {
                importLCF(data)
            } else {
                importJSON(data)
            }
        }
    }

    private func importJSON(_ data: Data) {
        let decoder = JSONDecoder()
        let imported: [ExportableConnection]
        if let array = try? decoder.decode([ExportableConnection].self, from: data) {
            imported = array
        } else if let single = try? decoder.decode(ExportableConnection.self, from: data) {
            imported = [single]
        } else {
            return
        }

        var needingFiles: [String] = []
        for item in imported {
            // Certificate / key files aren't portable (see ExportableConnection).
            if item.authentication == .external || (item.useSSHTunnel && item.sshAuthentication == .privateKey) {
                needingFiles.append(item.name)
            }
            let connection = SavedConnection(
                name: item.name,
                host: item.host,
                port: item.port,
                useSSL: item.useSSL,
                useStartTLS: item.useStartTLS,
                baseDN: item.baseDN,
                bindDN: item.bindDN,
                trustedCertSHA256: item.trustedCertSHA256,
                bookmarks: item.bookmarks,
                savedFilters: item.savedFilters,
                isFavorite: item.isFavorite,
                isReadOnly: item.isReadOnly,
                chaseReferrals: item.chaseReferrals,
                timeoutSeconds: item.timeoutSeconds,
                authentication: item.authentication,
                saslAuthID: item.saslAuthID,
                saslRealm: item.saslRealm,
                useSSHTunnel: item.useSSHTunnel,
                sshHost: item.sshHost,
                sshPort: item.sshPort,
                sshUsername: item.sshUsername,
                sshAuthentication: item.sshAuthentication,
                sshHostKeySHA256: item.sshHostKeySHA256
            )
            KeychainService.savePassword(item.decodedPassword, for: connection.id)
            KeychainService.saveSSHPassword(item.decodedSSHPassword, for: connection.id)
            store.add(connection)
        }

        if !needingFiles.isEmpty {
            importNotice = "Choose the certificate or key file again (Edit Connection) for: "
                + needingFiles.joined(separator: ", ")
                + ". Those file references can't be carried between Macs."
        }
    }

    /// LDAP Admin (.lcf) files can group accounts into folders — we have no
    /// such concept, so every account gets flattened into one flat list
    /// regardless of how it was organized in the source file.
    private func importLCF(_ data: Data) {
        for account in LCFParser.parse(data) {
            let connection = SavedConnection(
                name: account.name,
                host: account.host,
                port: account.port,
                useSSL: account.useSSL,
                baseDN: account.baseDN,
                bindDN: account.bindDN
            )
            KeychainService.savePassword(account.password, for: connection.id)
            store.add(connection)
        }
    }
}

#Preview {
    InfoPanel()
        .frame(height: 500)
        .environment(ConnectionStore())
}
