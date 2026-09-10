//
//  BrowserView.swift
//  ldap-studio
//

import SwiftUI

struct BrowserView: View {
    @Environment(ConnectionStore.self) private var store

    /// Seeded from the value the window opened with; the only field that
    /// changes here is `trustedCertSHA256`, when the user accepts an
    /// untrusted certificate (then persisted back through the store).
    @State private var connection: SavedConnection

    init(connection: SavedConnection) {
        _connection = State(initialValue: connection)
    }

    @State private var root: DirectoryEntry?
    @State private var loadError: String?
    @State private var isShowingCertTrust = false
    @State private var selection: DirectoryEntry.ID?
    /// Fetched alongside the tree for attribute/object-class autocomplete —
    /// optional and non-blocking on purpose: if it fails to load (or the
    /// server doesn't expose a usable schema), autocomplete just has no
    /// suggestions rather than the whole browser failing to open.
    @State private var schema: LdapSchema?

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
                        schema: schema,
                        bookmarks: connection.bookmarks,
                        onToggleBookmark: toggleBookmark,
                        reload: { dn in await reload(selecting: dn) }
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 260)
                } detail: {
                    if let selectedEntryBinding {
                        EntryDetailView(
                            entry: selectedEntryBinding,
                            root: root,
                            connection: connection,
                            schema: schema,
                            isBookmarked: selection.map(connection.bookmarks.contains) ?? false,
                            onToggleBookmark: { if let dn = selection { toggleBookmark(dn) } },
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
        .navigationTitle("Ldap Studio - \(connection.name)\(connection.isReadOnly ? "  (Read-Only)" : "")")
        .task {
            await loadDirectory()
        }
        .sheet(isPresented: $isShowingCertTrust) {
            CertificateTrustSheet(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSSL: connection.useSSL,
                useStartTLS: connection.useStartTLS
            ) { sha256 in
                connection.trustedCertSHA256 = sha256
                store.update(connection)
                retry()
            }
        }
    }

    private func retry() {
        loadError = nil
        Task {
            await loadDirectory()
        }
    }

    /// Pin or unpin `dn` in this connection's bookmark list, then persist.
    private func toggleBookmark(_ dn: String) {
        if let index = connection.bookmarks.firstIndex(of: dn) {
            connection.bookmarks.remove(at: index)
        } else {
            connection.bookmarks.insert(dn, at: 0)
        }
        store.update(connection)
    }

    private func loadDirectory() async {
        let password = KeychainService.readPassword(for: connection.id) ?? ""

        // Run together rather than one after the other — the schema fetch
        // is a nice-to-have for autocomplete, not something worth making
        // the user wait an extra round trip for.
        async let entryTask = fetchRootEntry(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            startTLS: connection.useStartTLS,
            pinnedCertSHA256: connection.trustedCertSHA256,
            bindDn: connection.bindDN,
            password: password,
            baseDn: connection.baseDN
        )
        async let schemaTask: LdapSchema? = try? await fetchSchema(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            startTLS: connection.useStartTLS,
            pinnedCertSHA256: connection.trustedCertSHA256,
            bindDn: connection.bindDN,
            password: password
        )

        do {
            root = DirectoryEntry(ldapEntry: try await entryTask)
            schema = await schemaTask
        } catch let error as ConnectionError {
            // An untrusted certificate isn't a dead end — offer to inspect
            // and pin it. Anything the user already pinned that still fails
            // is a real problem, so show it plainly.
            if case .TLSUntrusted = error, connection.trustedCertSHA256 == nil {
                isShowingCertTrust = true
            } else {
                loadError = "\(error)"
            }
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
        .environment(ConnectionStore())
}
