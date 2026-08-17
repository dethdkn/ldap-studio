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

    private var selectedEntryBinding: Binding<DirectoryEntry>? {
        guard let selection, root?.find(id: selection) != nil else { return nil }
        return Binding(
            get: { root?.find(id: selection) ?? DirectoryEntry(name: "", dn: "", icon: "", attributes: [], children: nil) },
            set: { newValue in root?.update(id: selection) { $0 = newValue } }
        )
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Load Directory", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        retry()
                    }
                }
            } else if let root {
                NavigationSplitView {
                    DirectoryTreeView(
                        root: root,
                        selection: $selection,
                        connection: connection,
                        reload: { dn in await reload(selecting: dn) }
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 260)
                } detail: {
                    if let selectedEntryBinding {
                        EntryDetailView(
                            entry: selectedEntryBinding,
                            root: root,
                            connection: connection,
                            reload: { dn in await reload(selecting: dn) }
                        )
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
        .navigationTitle("Ldap Studio - \(connection.name)")
        .task {
            await loadDirectory()
        }
    }

    private func retry() {
        loadError = nil
        Task {
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

    /// Re-fetches the whole directory (used after any write from the detail
    /// view) and re-selects whichever dn should still be selected — `nil`
    /// when the entry that was selected no longer exists, e.g. after Delete
    /// Value emptied it out or a Move relocated it and the caller doesn't
    /// know its new dn.
    private func reload(selecting dn: String?) async {
        await loadDirectory()
        if let dn, root?.find(id: dn) != nil {
            selection = dn
        } else {
            selection = nil
        }
    }
}

#Preview {
    BrowserView(connection: SavedConnection(name: "Corp Directory", host: "ldap.corp.example.com", port: 389, useSSL: false, baseDN: "dc=corp,dc=example,dc=com", bindDN: ""))
}
