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
    let schema: LdapSchema?
    let onSelect: (String) -> Void
    let reload: (String?) async -> Void
    let onUpdateSavedFilters: ([SavedLDAPFilter]) -> Void

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
    @State private var savedFilters: [SavedLDAPFilter]
    @State private var isNamingPinnedFilter = false
    @State private var pinnedFilterName = ""
    @State private var filterEditorMode: LDAPFilterEditorMode = .raw
    @State private var filterJoin: LDAPFilterJoin = .and
    @State private var filterClauses = [LDAPFilterClause()]

    init(
        connection: SavedConnection,
        root: DirectoryEntry,
        schema: LdapSchema?,
        defaultBaseDN: String,
        onSelect: @escaping (String) -> Void,
        reload: @escaping (String?) async -> Void,
        onUpdateSavedFilters: @escaping ([SavedLDAPFilter]) -> Void
    ) {
        self.connection = connection
        self.root = root
        self.schema = schema
        self.onSelect = onSelect
        self.reload = reload
        self.onUpdateSavedFilters = onUpdateSavedFilters
        _baseDN = State(initialValue: defaultBaseDN)
        _savedFilters = State(initialValue: connection.savedFilters)
    }

    private var isValid: Bool {
        !baseDN.isEmpty && !normalizedFilter.isEmpty
    }

    private var selectedEntries: [DirectoryEntry] {
        root.operationRoots(in: selection)
    }

    private var selectedResultEntries: [DirectoryEntry] {
        results
            .filter { selection.contains($0.dn) }
            .map { DirectoryEntry(ldapEntry: $0) }
    }

    private var selectedEntryCount: Int {
        selectedEntries.reduce(0) { $0 + $1.subtreeCount }
    }

    private var currentSavedFilter: SavedLDAPFilter? {
        savedFilters.first { $0.filter == normalizedFilter }
    }

    private var normalizedFilter: String {
        effectiveFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var effectiveFilter: String? {
        guard filterEditorMode == .builder else { return filter }
        let generated = filterClauses.compactMap(\.filter)
        guard generated.count == filterClauses.count, !generated.isEmpty else { return nil }
        if generated.count == 1 { return generated[0] }
        return "(\(filterJoin.marker)\(generated.joined()))"
    }

    private var attributeSuggestions: [String] {
        schema?.attributeTypes
            .flatMap(\.names)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } ?? []
    }

    private var pinnedFilters: [SavedLDAPFilter] {
        savedFilters
            .filter(\.isPinned)
            .sorted { ($0.name ?? $0.filter).localizedCaseInsensitiveCompare($1.name ?? $1.filter) == .orderedAscending }
    }

    private var recentFilters: [SavedLDAPFilter] {
        savedFilters
            .filter { !$0.isPinned }
            .sorted { $0.lastUsed > $1.lastUsed }
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
                Picker("Filter Editor", selection: $filterEditorMode) {
                    Text("Raw").tag(LDAPFilterEditorMode.raw)
                    Text("Builder").tag(LDAPFilterEditorMode.builder)
                }
                .pickerStyle(.segmented)

                if filterEditorMode == .raw {
                    TextField("Filter", text: $filter)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(search)
                } else {
                    LDAPFilterBuilder(
                        join: $filterJoin,
                        clauses: $filterClauses,
                        attributeSuggestions: attributeSuggestions
                    )

                    LabeledContent("Generated Filter") {
                        Text(effectiveFilter ?? "Complete every rule to generate a filter")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(effectiveFilter == nil ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack {
                    Spacer()
                    filterHistoryMenu
                    Button {
                        togglePinnedFilter()
                    } label: {
                        Image(systemName: currentSavedFilter?.isPinned == true ? "star.fill" : "star")
                    }
                    .buttonStyle(.borderless)
                    .help(currentSavedFilter?.isPinned == true ? "Unpin Filter" : "Name and Pin Filter")
                    .disabled(normalizedFilter.isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(height: filterEditorMode == .raw ? 205 : 380)

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
        .frame(width: 800, height: filterEditorMode == .raw ? 620 : 795)
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
        .alert("Pin Filter", isPresented: $isNamingPinnedFilter) {
            TextField("Name (optional)", text: $pinnedFilterName)
            Button("Pin") { pinCurrentFilter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned filters are saved for this connection.")
        }
    }

    @ViewBuilder
    private var filterHistoryMenu: some View {
        Menu {
            if !pinnedFilters.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedFilters) { item in
                        Button {
                            applySavedFilter(item)
                        } label: {
                            Label(item.name ?? item.filter, systemImage: "star.fill")
                        }
                    }
                }
            }

            if !recentFilters.isEmpty {
                Section("Recent") {
                    ForEach(recentFilters) { item in
                        Button(item.filter) { applySavedFilter(item) }
                    }
                }
                Divider()
                Button("Clear Recent Filters", role: .destructive) {
                    saveFilters(savedFilters.filter(\.isPinned))
                }
            }

            if pinnedFilters.isEmpty && recentFilters.isEmpty {
                Text("No Saved Filters")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                Image(systemName: "clock.arrow.circlepath")
                Text("Pinned & Recent")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Saved and Recent Filters")
    }

    private func search() {
        guard isValid, !isSearching else { return }
        let searchFilter = normalizedFilter
        isSearching = true
        errorMessage = nil
        selection.removeAll()
        recordCurrentFilter()
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
                    filter: searchFilter
                )
            } catch {
                errorMessage = "\(error)"
                results = []
            }
        }
    }

    private func applySavedFilter(_ item: SavedLDAPFilter) {
        filter = item.filter
        filterEditorMode = .raw
    }

    private func recordCurrentFilter() {
        guard !normalizedFilter.isEmpty else { return }
        var updated = savedFilters
        if let index = updated.firstIndex(where: { $0.filter == normalizedFilter }) {
            updated[index].lastUsed = .now
        } else {
            updated.append(SavedLDAPFilter(filter: normalizedFilter))
        }
        saveFilters(updated)
    }

    private func togglePinnedFilter() {
        if let currentSavedFilter, currentSavedFilter.isPinned {
            var updated = savedFilters
            guard let index = updated.firstIndex(where: { $0.id == currentSavedFilter.id }) else { return }
            updated[index].isPinned = false
            updated[index].name = nil
            updated[index].lastUsed = .now
            saveFilters(updated)
        } else {
            pinnedFilterName = currentSavedFilter?.name ?? ""
            isNamingPinnedFilter = true
        }
    }

    private func pinCurrentFilter() {
        guard !normalizedFilter.isEmpty else { return }
        let name = pinnedFilterName.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = savedFilters
        if let index = updated.firstIndex(where: { $0.filter == normalizedFilter }) {
            updated[index].name = name.isEmpty ? nil : name
            updated[index].isPinned = true
            updated[index].lastUsed = .now
        } else {
            updated.append(SavedLDAPFilter(
                name: name.isEmpty ? nil : name,
                filter: normalizedFilter,
                isPinned: true
            ))
        }
        saveFilters(updated)
    }

    private func saveFilters(_ filters: [SavedLDAPFilter]) {
        let pinned = filters.filter(\.isPinned)
        let recent = filters
            .filter { !$0.isPinned }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(10)
        savedFilters = pinned + recent
        onUpdateSavedFilters(savedFilters)
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
        schema: nil,
        defaultBaseDN: "dc=example,dc=com",
        onSelect: { _ in },
        reload: { _ in },
        onUpdateSavedFilters: { _ in }
    )
}
