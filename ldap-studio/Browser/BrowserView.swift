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
    /// An SSH host key seen for the first time, waiting on the user's say-so.
    @State private var pendingSSHHostKey: PendingSSHHostKey?

    private struct PendingSSHHostKey {
        let host: String
        let port: UInt16
        /// Hex SHA-256 of the key, as reported by the core.
        let fingerprint: String
    }
    @State private var selection: DirectoryEntry.ID?
    /// Fetched alongside the tree for attribute/object-class autocomplete —
    /// optional and non-blocking on purpose: if it fails to load (or the
    /// server doesn't expose a usable schema), autocomplete just has no
    /// suggestions rather than the whole browser failing to open.
    @State private var schema: LdapSchema?

    @State private var isLogExpanded = false
    @State private var operationLog = OperationLog.shared

    private var endpoint: String {
        "\(connection.host):\(UInt16(clamping: connection.port))"
    }

    private var selectedEntryBinding: Binding<DirectoryEntry>? {
        guard let selection, root?.find(id: selection) != nil else { return nil }
        return Binding(
            get: { root?.find(id: selection) ?? DirectoryEntry(name: "", dn: "", icon: "", attributes: [], children: nil) },
            set: { newValue in root?.update(id: selection) { $0 = newValue } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            logStrip
        }
        .onReceive(NotificationCenter.default.publisher(for: .ldapEntryDidChange)) { note in
            // A detached window (Edit Entry, …) wrote to this server — pull
            // the fresh tree so the detail table reflects it.
            guard note.userInfo?["endpoint"] as? String == endpoint else { return }
            let dn = note.userInfo?["dn"] as? String
            Task { await reload(selecting: dn ?? selection) }
        }
    }

    @ViewBuilder
    private var content: some View {
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
                        onUpdateSavedFilters: updateSavedFilters,
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
        .alert(
            "Trust SSH Host Key?",
            isPresented: Binding(
                get: { pendingSSHHostKey != nil },
                set: { if !$0 { pendingSSHHostKey = nil } }
            ),
            presenting: pendingSSHHostKey
        ) { pending in
            Button("Trust and Connect") {
                connection.sshHostKeySHA256 = pending.fingerprint
                store.update(connection)
                pendingSSHHostKey = nil
                retry()
            }
            Button("Cancel", role: .cancel) {
                pendingSSHHostKey = nil
                loadError = "The SSH host key for \(pending.host):\(pending.port) wasn't trusted, so no connection was made."
            }
        } message: { pending in
            Text("""
                LDAP Studio hasn't connected through \(pending.host):\(pending.port) before. \
                Check this fingerprint against the server's own (for example with \
                `ssh-keygen -lf` on its host key) before trusting it:

                \(SSHHostKeyFingerprint.openSSH(fromHex: pending.fingerprint))
                """)
        }
    }

    private var logStrip: some View {
        let mine = operationLog.entries.filter { $0.endpoint == endpoint }
        return VStack(spacing: 0) {
            Divider()

            Button {
                withAnimation(.easeOut(duration: 0.15)) { isLogExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isLogExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Operation Log")
                        .font(.caption.weight(.semibold))
                    if !mine.isEmpty {
                        Text("\(mine.count)")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    if let last = mine.last {
                        Text("·").foregroundStyle(.tertiary)
                        Text(last.summary)
                            .foregroundStyle(last.outcome.isOK ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text("⇧⌘Y")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("y", modifiers: [.command, .shift])

            if isLogExpanded {
                Divider()
                OperationLogPanel(endpoint: endpoint)
                    .frame(height: 220)
            }
        }
        .background(.bar)
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

    private func updateSavedFilters(_ filters: [SavedLDAPFilter]) {
        connection.savedFilters = filters
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
            options: connection.ldapOptions,
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
            options: connection.ldapOptions,
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
            } else if case let .SSHHostKeyUntrusted(host, port, fingerprint) = error {
                if connection.sshHostKeySHA256 == nil {
                    pendingSSHHostKey = PendingSSHHostKey(host: host, port: port, fingerprint: fingerprint)
                } else {
                    // A key we already trusted no longer matches. Unlike a
                    // first sighting, that is never a one-click decision —
                    // it can mean the connection is being intercepted.
                    loadError = """
                        The SSH host key for \(host):\(port) has changed since you trusted it.

                        It is now \(SSHHostKeyFingerprint.openSSH(fromHex: fingerprint)).

                        This can mean the server was rebuilt, or that someone is intercepting the connection. \
                        If you know the change is legitimate, clear the trusted host key under Edit Connection \
                        › SSH Tunnel, then connect again.
                        """
                }
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
