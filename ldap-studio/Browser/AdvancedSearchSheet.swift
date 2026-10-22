//
//  AdvancedSearchSheet.swift
//  ldap-studio
//

import SwiftUI

/// A real LDAP search — base DN, scope, and a raw RFC 4515 filter string,
/// evaluated by the server itself. The quick search over the tree only
/// matches names; this is for everything a filter can do (attribute values,
/// AND/OR/NOT, substrings, presence, …). Results are read with paged
/// searches, so every match comes back however many there are; a long
/// search shows its progress and can be cancelled.
struct AdvancedSearchSheet: View {
    let connection: SavedConnection
    let tree: DirectoryTree
    let schema: LdapSchema?
    let onSelect: (String) -> Void
    let onChange: (DirectoryChange) async -> Void
    let onUpdateSavedFilters: ([SavedLDAPFilter]) -> Void

    @Environment(\.dismiss) private var dismiss

    /// One match — just enough to list it; anything else is read when used.
    struct Hit: Identifiable, Hashable {
        let dn: String
        var id: String { dn }
        var name: String { DN.rdn(of: dn) }
    }

    @State private var baseDN: String
    @State private var scope: LdapSearchScope = .subtree
    @State private var filter = "(objectClass=*)"
    /// Every match, kept out of SwiftUI's sight: re-diffing a list of
    /// 100,000 rows on each page would slow the search to a crawl.
    @State private var store = HitStore()
    /// The matches the list draws — the first `displayLimit` of them.
    @State private var results: [Hit] = []
    @State private var displayLimit = AdvancedSearchSheet.displayStep
    @State private var totalFound = 0
    private static let displayStep = 5_000
    @State private var searchTask: Task<Void, Never>?
    @State private var foundSoFar = 0
    /// The request the current results came from — what Export re-runs.
    @State private var lastRequest: LdapSearchRequest?
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var wasCancelled = false
    /// The server cut the results short (it ignored paging).
    @State private var wasTruncated = false
    @State private var selection: Set<String> = []
    @State private var isChoosingMoveDestination = false
    @State private var operations: BranchOperations
    @State private var savedFilters: [SavedLDAPFilter]
    @State private var isNamingPinnedFilter = false
    @State private var pinnedFilterName = ""
    @State private var filterEditorMode: LDAPFilterEditorMode = .raw
    @State private var filterJoin: LDAPFilterJoin = .and
    @State private var filterClauses = [LDAPFilterClause()]

    init(
        connection: SavedConnection,
        tree: DirectoryTree,
        schema: LdapSchema?,
        defaultBaseDN: String,
        onSelect: @escaping (String) -> Void,
        onChange: @escaping (DirectoryChange) async -> Void,
        onUpdateSavedFilters: @escaping ([SavedLDAPFilter]) -> Void
    ) {
        self.connection = connection
        self.tree = tree
        self.schema = schema
        self.onSelect = onSelect
        self.onChange = onChange
        self.onUpdateSavedFilters = onUpdateSavedFilters
        _baseDN = State(initialValue: defaultBaseDN)
        _savedFilters = State(initialValue: connection.savedFilters)
        _operations = State(initialValue: BranchOperations(connection: connection, schema: schema))
    }

    private var isSearching: Bool { searchTask != nil }

    private var isValid: Bool {
        !baseDN.isEmpty && !normalizedFilter.isEmpty
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

            List(selection: $selection) {
                ForEach(results) { entry in
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
                if totalFound > results.count, !isSearching {
                    HStack(spacing: 8) {
                        Text("Showing the first \(results.count.formatted()) of \(totalFound.formatted())")
                            .foregroundStyle(.secondary)
                        Button("Show \(min(Self.displayStep, totalFound - results.count).formatted()) More") {
                            displayLimit += Self.displayStep
                            results = Array(store.hits.prefix(displayLimit))
                        }
                        .controlSize(.small)
                    }
                    .font(.callout)
                }
            }
            .overlay {
                if isSearching && results.isEmpty {
                    ProgressView()
                } else if hasSearched && !isSearching && results.isEmpty && errorMessage == nil {
                    ContentUnavailableView.search
                }
            }

            Divider()

            HStack {
                Button("Move…", systemImage: "arrow.turn.up.right") {
                    isChoosingMoveDestination = true
                }
                .disabled(selection.isEmpty || connection.isReadOnly || isSearching)

                Button("Export LDIF…", systemImage: "square.and.arrow.up") {
                    if let lastRequest {
                        operations.exportLDIF(of: lastRequest, selected: selection.isEmpty ? nil : selection)
                    }
                }
                .disabled(totalFound == 0 || isSearching)
                .help(selection.isEmpty ? "Export every result" : "Export the selected results")

                Button("Delete", systemImage: "trash", role: .destructive) {
                    operations.requestDelete(Array(selection))
                }
                .disabled(selection.isEmpty || connection.isReadOnly || isSearching)

                statusText
                Spacer()
                Button("Close") {
                    searchTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if isSearching {
                    Button("Stop") {
                        searchTask?.cancel()
                    }
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button("Search") {
                        search()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                }
            }
            .padding()
        }
        .frame(width: 800, height: filterEditorMode == .raw ? 620 : 795)
        .branchOperations(operations)
        .onAppear {
            operations.onChange = { change in
                await onChange(change)
                await applyToResults(change)
            }
            operations.onSelect = { _ in }
        }
        .onDisappear { searchTask?.cancel() }
        .sheet(isPresented: $isChoosingMoveDestination) {
            DestinationPickerSheet(
                tree: tree,
                excluding: Array(selection),
                title: "Move \(selection.count) Selected \(selection.count == 1 ? "Entry" : "Entries") To",
                confirmLabel: "Move"
            ) { destinationDN in
                operations.requestMove(Array(selection), to: destinationDN)
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

    @ViewBuilder
    private var statusText: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if isSearching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Searching… \(foundSoFar.formatted()) found")
                        .foregroundStyle(.secondary)
                }
            } else if hasSearched {
                Text("\(totalFound.formatted()) result\(totalFound == 1 ? "" : "s")\(wasCancelled ? " (stopped)" : wasTruncated ? " — incomplete: the server's size limit cut the search short" : "")")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
    }

    /// Reads every match, page by page, listing them as they arrive (in
    /// batches, so a search with 100,000 matches doesn't redraw the list
    /// 200 times). Only DNs are requested; Export re-runs the search with
    /// every attribute.
    private func search() {
        guard isValid, !isSearching else { return }
        // The user started this one and can stop it, so it waits on a slow
        // server as long as it takes (exporting the results re-runs it the
        // same way).
        let request = LdapSearchRequest(baseDn: baseDN, scope: scope, filter: normalizedFilter,
                                        attributes: ["1.1"], idleTimeout: 0)
        errorMessage = nil
        wasCancelled = false
        wasTruncated = false
        selection.removeAll()
        store.hits = []
        results = []
        totalFound = 0
        displayLimit = Self.displayStep
        foundSoFar = 0
        recordCurrentFilter()
        searchTask = Task {
            defer {
                searchTask = nil
                hasSearched = true
            }
            var lastShown = ContinuousClock.now
            do {
                let outcome = try await pagedSearch(connection.ldapTarget, request) { page, progress in
                    store.hits += page.map { Hit(dn: $0.dn) }
                    // Each update redraws the sheet; a few a second is plenty.
                    if ContinuousClock.now - lastShown > .milliseconds(250) {
                        foundSoFar = progress.entries
                        lastShown = .now
                    }
                    // Only the first rows are drawn, so later pages don't
                    // touch the list at all.
                    if results.count < displayLimit {
                        results = Array(store.hits.prefix(displayLimit))
                    }
                    return true
                }
                wasTruncated = outcome.wasTruncated
                lastRequest = request
            } catch is CancellationError {
                wasCancelled = true
                lastRequest = request
            } catch {
                errorMessage = "\(error)"
            }
            results = Array(store.hits.prefix(displayLimit))
            totalFound = store.hits.count
        }
    }

    /// Keeps the result list honest after a delete or move from here.
    /// Keys are worked out off the main actor, once per search, so
    /// deleting or moving many results doesn't re-normalize 100,000 DNs on
    /// the main thread for each one.
    private func applyToResults(_ change: DirectoryChange) async {
        let ancestor: String
        switch change {
        case let .removed(dn): ancestor = dn
        case let .moved(from, _): ancestor = from
        case .added, .modified, .branchChanged: return
        }
        let ancestorKey = DN.normalize(ancestor)
        let keys = await store.keys()
        let affected = Set(keys.indices.filter { DN.keyIsWithin(keys[$0], ancestorKey) })
        guard !affected.isEmpty else { return }
        switch change {
        case .removed:
            store.remove(at: affected)
            selection = selection.filter { !DN.isWithin($0, ancestor) }
        case let .moved(from, to):
            store.replace(at: affected) { Hit(dn: DN.rebase($0.dn, from: from, to: to)) }
            selection.removeAll()
        default:
            return
        }
        results = Array(store.hits.prefix(displayLimit))
        totalFound = store.hits.count
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

}

/// See `AdvancedSearchSheet.store`.
private final class HitStore {
    var hits: [AdvancedSearchSheet.Hit] = [] {
        didSet { cachedKeys = nil }
    }
    /// `DN.normalize` of each hit, worked out when first needed.
    private var cachedKeys: [String]?

    func keys() async -> [String] {
        if let cachedKeys, cachedKeys.count == hits.count { return cachedKeys }
        let dns = hits.map(\.dn)
        let keys = await Task.detached(priority: .userInitiated) { dns.map(DN.normalize) }.value
        cachedKeys = keys
        return keys
    }

    func remove(at indices: Set<Int>) {
        let keys = cachedKeys
        hits = hits.indices.filter { !indices.contains($0) }.map { hits[$0] }
        cachedKeys = keys.map { k in k.indices.filter { !indices.contains($0) }.map { k[$0] } }
    }

    func replace(at indices: Set<Int>, with transform: (AdvancedSearchSheet.Hit) -> AdvancedSearchSheet.Hit) {
        var keys = cachedKeys
        var updated = hits
        for i in indices {
            updated[i] = transform(updated[i])
            keys?[i] = DN.normalize(updated[i].dn)
        }
        hits = updated
        cachedKeys = keys
    }
}

#Preview {
    let connection = SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "dc=example,dc=com", bindDN: "")
    AdvancedSearchSheet(
        connection: connection,
        tree: DirectoryTree(connection: connection),
        schema: nil,
        defaultBaseDN: "dc=example,dc=com",
        onSelect: { _ in },
        onChange: { _ in },
        onUpdateSavedFilters: { _ in }
    )
}
