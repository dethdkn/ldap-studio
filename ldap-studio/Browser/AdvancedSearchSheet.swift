//
//  AdvancedSearchSheet.swift
//  ldap-studio
//

import SwiftUI

/// A real LDAP search — base DN, scope, and a raw RFC 4515 filter string,
/// evaluated by the server itself. The basic search field over the tree
/// only matches against dn text; this is for everything a filter can do
/// (attribute values, AND/OR/NOT, substrings, presence, …).
struct AdvancedSearchSheet: View {
    let connection: SavedConnection
    let root: DirectoryEntry
    let onSelect: (String) -> Void
    let reload: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var baseDN: String
    @State private var scope: LdapSearchScope = .subtree
    @State private var filter = "(objectClass=*)"
    @State private var results: [LdapEntry] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var selection: Set<String> = []
    @State private var isPerformingAction = false
    @State private var isConfirmingDelete = false
    @State private var isChoosingMoveDestination = false

    init(
        connection: SavedConnection,
        root: DirectoryEntry,
        defaultBaseDN: String,
        onSelect: @escaping (String) -> Void,
        reload: @escaping (String?) async -> Void
    ) {
        self.connection = connection
        self.root = root
        self.onSelect = onSelect
        self.reload = reload
        _baseDN = State(initialValue: defaultBaseDN)
    }

    private var isValid: Bool {
        !baseDN.isEmpty && !filter.isEmpty
    }

    private var selectedEntries: [DirectoryEntry] {
        root.operationRoots(in: selection)
    }

    private var selectedResultEntries: [DirectoryEntry] {
        results
            .filter { selection.contains($0.dn) }
            .map(DirectoryEntry.init(ldapEntry:))
    }

    private var selectedEntryCount: Int {
        selectedEntries.reduce(0) { $0 + $1.subtreeCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Advanced Search")
                .font(.headline)
                .padding()

            Divider()

            Form {
                TextField("Base DN", text: $baseDN)
                Picker("Scope", selection: $scope) {
                    Text("Base").tag(LdapSearchScope.base)
                    Text("One Level").tag(LdapSearchScope.oneLevel)
                    Text("Subtree").tag(LdapSearchScope.subtree)
                }
                TextField("Filter", text: $filter)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(search)
            }
            .formStyle(.grouped)
            .frame(height: 150)

            Divider()

            HStack {
                Text("Attribute").font(.caption).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
                Text("dn").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            List(results, id: \.dn, selection: $selection) { entry in
                HStack {
                    Text(entry.name)
                        .frame(width: 200, alignment: .leading)
                    Text(entry.dn)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        onSelect(entry.dn)
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Directory")
                }
                .contentShape(Rectangle())
                .tag(entry.dn)
                .onTapGesture(count: 2) {
                    onSelect(entry.dn)
                    dismiss()
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if hasSearched && results.isEmpty && errorMessage == nil {
                    ContentUnavailableView.search
                }
            }

            Divider()

            HStack {
                Button("Move…", systemImage: "arrow.turn.up.right") {
                    isChoosingMoveDestination = true
                }
                .disabled(selection.isEmpty || connection.isReadOnly || isPerformingAction)

                Button("Export LDIF…", systemImage: "square.and.arrow.up") {
                    EntryActions(connection: connection).exportLDIF(selectedResultEntries)
                }
                .disabled(selection.isEmpty || isPerformingAction)

                Button("Delete", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .disabled(selection.isEmpty || connection.isReadOnly || isPerformingAction)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(2)
                } else {
                    Text(hasSearched ? "\(results.count) result\(results.count == 1 ? "" : "s")" : "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Search") {
                    search()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isSearching)
            }
            .padding()
        }
        .frame(width: 760, height: 560)
        .overlay {
            if isPerformingAction {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .alert(
            "Delete Selected Entries?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete \(selectedEntryCount) \(selectedEntryCount == 1 ? "Entry" : "Entries")", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the selected entries and their descendants from the server. This cannot be undone.")
        }
        .sheet(isPresented: $isChoosingMoveDestination) {
            if let destinationRoot = root.pruned(removing: selection) {
                DestinationPickerSheet(
                    root: destinationRoot,
                    title: "Move \(selectedEntries.count) Selected \(selectedEntries.count == 1 ? "Entry" : "Entries") To",
                    confirmLabel: "Move"
                ) { destinationDN in
                    moveSelected(to: destinationDN)
                }
            }
        }
    }

    private func search() {
        guard isValid, !isSearching else { return }
        isSearching = true
        errorMessage = nil
        selection.removeAll()
        Task {
            defer {
                isSearching = false
                hasSearched = true
            }
            do {
                results = try await searchDirectory(
                    host: connection.host,
                    port: UInt16(clamping: connection.port),
                    useSsl: connection.useSSL,
                    startTLS: connection.useStartTLS,
                    pinnedCertSHA256: connection.trustedCertSHA256,
                    bindDn: connection.bindDN,
                    password: KeychainService.readPassword(for: connection.id) ?? "",
                    baseDn: baseDN,
                    scope: scope,
                    filter: filter
                )
            } catch {
                errorMessage = "\(error)"
                results = []
            }
        }
    }

    private func deleteSelected() {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        performBulkAction {
            let actions = EntryActions(connection: connection)
            for entry in entries.sorted(by: { $0.dn.count > $1.dn.count }) {
                try await actions.delete(entry)
            }
        }
    }

    private func moveSelected(to destinationDN: String) {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        performBulkAction {
            let actions = EntryActions(connection: connection)
            for entry in entries {
                _ = try await actions.move(entry, to: destinationDN)
            }
        }
    }

    private func performBulkAction(_ operation: @escaping () async throws -> Void) {
        Task {
            isPerformingAction = true
            errorMessage = nil
            defer { isPerformingAction = false }
            do {
                try await operation()
                selection.removeAll()
                await reload(nil)
                search()
            } catch {
                let actionError = "\(error)"
                await reload(nil)
                search()
                errorMessage = actionError
            }
        }
    }
}

#Preview {
    AdvancedSearchSheet(
        connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "dc=example,dc=com", bindDN: ""),
        root: .mockRoot,
        defaultBaseDN: "dc=example,dc=com",
        onSelect: { _ in },
        reload: { _ in }
    )
}
