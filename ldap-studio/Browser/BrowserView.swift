//
//  BrowserView.swift
//  ldap-studio
//

import SwiftUI

struct BrowserView: View {
    let connection: SavedConnection

    @State private var root: DirectoryEntry?
    @State private var loadError: String?
    @State private var selection: DirectoryEntry.ID?

    private var selectedEntry: DirectoryEntry? {
        guard let root, let selection else { return nil }
        return root.find(id: selection)
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't Load Directory",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if let root {
                NavigationSplitView {
                    DirectoryTreeView(root: root, selection: $selection)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 260)
                } detail: {
                    if let selectedEntry {
                        EntryDetailView(entry: selectedEntry)
                    } else {
                        ContentUnavailableView(
                            "No Selection",
                            systemImage: "sidebar.left",
                            description: Text("Select an entry from the tree to view its attributes.")
                        )
                    }
                }
            } else {
                ProgressView("Connecting to \(connection.host)…")
            }
        }
        .frame(minWidth: 700, minHeight: 420)
        .navigationTitle(connection.name)
        .task {
            await loadDirectory()
        }
    }

    private func loadDirectory() async {
        do {
            let entry = try await fetchRootEntry(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: KeychainService.readPassword(for: connection.id) ?? "",
                baseDn: connection.baseDN
            )
            root = DirectoryEntry(ldapEntry: entry)
        } catch {
            loadError = "\(error)"
        }
    }
}

#Preview {
    BrowserView(connection: SavedConnection(name: "Corp Directory", host: "ldap.corp.example.com", port: 389, useSSL: false, baseDN: "dc=corp,dc=example,dc=com", bindDN: ""))
}
