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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("ldap-studio")
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("LDAP Studio")
                    .font(.title2.bold())
                Text("Version \(appVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                Text("© Gabriel Rosa")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
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

        for item in imported {
            let connection = SavedConnection(
                name: item.name,
                host: item.host,
                port: item.port,
                useSSL: item.useSSL,
                baseDN: item.baseDN,
                bindDN: item.bindDN
            )
            KeychainService.savePassword(item.decodedPassword, for: connection.id)
            store.add(connection)
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
