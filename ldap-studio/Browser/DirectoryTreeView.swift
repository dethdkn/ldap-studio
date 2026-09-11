//
//  DirectoryTreeView.swift
//  ldap-studio
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DirectoryTreeView: View {
    let root: DirectoryEntry
    @Binding var selection: DirectoryEntry.ID?
    let connection: SavedConnection
    /// Optional — feeds the attribute/object-class autocomplete in New
    /// Entry; nil just means no suggestions, never a blocker.
    let schema: LdapSchema?
    /// This connection's pinned DNs, and the callback to add/remove one.
    /// `BrowserView` owns the list and persists it.
    let bookmarks: [String]
    let onToggleBookmark: (String) -> Void
    @Environment(\.openWindow) private var openWindow
    /// Same contract as `EntryDetailView`'s `reload`: refetches the whole
    /// directory from the server and reselects the given dn if it still
    /// exists afterward.
    let reload: (String?) async -> Void

    private struct PickerRequest: Identifiable {
        enum Kind { case move, copy }
        let kind: Kind
        let entry: DirectoryEntry
        var id: String { "\(kind)-\(entry.id)" }
    }

    private struct NewEntryRequest: Identifiable {
        let parentDN: String
        var id: String { parentDN }
    }

    /// Carries which subtree the Advanced Search sheet should start scoped
    /// to — the entry it was launched from, rather than always the root.
    private struct AdvancedSearchRequest: Identifiable {
        let baseDN: String
        var id: String { baseDN }
    }

    @State private var pickerRequest: PickerRequest?
    @State private var entryPendingDeletion: DirectoryEntry?
    @State private var newEntryRequest: NewEntryRequest?
    @State private var groupForMembersEditing: DirectoryEntry?
    @State private var entryForRename: DirectoryEntry?
    @State private var entryForPasswordSet: DirectoryEntry?
    @State private var entryForTestBind: DirectoryEntry?

    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var searchText = ""
    @State private var advancedSearchRequest: AdvancedSearchRequest?

    @State private var isShowingGoTo = false
    @State private var goToText = ""
    @State private var goToError: String?
    @FocusState private var goToFieldFocused: Bool

    /// Which nodes are expanded — `OutlineGroup`'s simple form manages this
    /// internally with no way to control it from outside, so revealing a
    /// search result (expanding its ancestors, then scrolling to it) needs
    /// this hand-rolled instead, via `DisclosureGroup`'s `isExpanded`
    /// binding.
    @State private var expandedIDs: Set<DirectoryEntry.ID> = []

    private var actions: EntryActions {
        EntryActions(connection: connection)
    }

    /// Filtering by dn (not just the entry's own name) means a query like
    /// "People" also surfaces everything underneath that ou — matches the
    /// literal ask, and reads naturally either way.
    private var filteredRoot: DirectoryEntry? {
        root.filtered(matching: searchText)
    }

    private var selectedEntry: DirectoryEntry? {
        guard let selection else { return nil }
        return root.find(id: selection)
    }

    private var bookmarkSet: Set<String> { Set(bookmarks) }

    private var isReadOnly: Bool { connection.isReadOnly }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            ScrollViewReader { proxy in
                List(selection: $selection) {
                    if let filteredRoot {
                        DirectoryOutlineRow(entry: filteredRoot, expandedIDs: $expandedIDs, bookmarks: bookmarkSet)
                    }
                }
                .contextMenu(forSelectionType: DirectoryEntry.ID.self) { ids in
                    if let id = ids.first, let entry = root.find(id: id) {
                        contextMenuContent(for: entry)
                    }
                }
                .onChange(of: selection) { _, newValue in
                    guard let newValue else { return }
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .disabled(isPerformingAction)
        .sheet(item: $pickerRequest) { request in
            if let pruned = root.pruned(removing: request.entry.id) {
                let isMove = request.kind == .move
                DestinationPickerSheet(
                    root: pruned,
                    title: "\(isMove ? "Move" : "Copy") \(request.entry.name) To",
                    confirmLabel: isMove ? "Move" : "Copy"
                ) { destinationDN in
                    if isMove {
                        move(request.entry, to: destinationDN)
                    } else {
                        copy(request.entry, to: destinationDN)
                    }
                }
            }
        }
        .alert(
            deleteAlertTitle(for: entryPendingDeletion),
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            presenting: entryPendingDeletion
        ) { entry in
            Button(entry.subtreeCount > 1 ? "Delete \(entry.subtreeCount) Entries" : "Delete",
                   role: .destructive) {
                delete(entry)
                entryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: { entry in
            let descendants = entry.subtreeCount - 1
            if descendants > 0 {
                let noun: String = descendants == 1 ? "entry" : "entries"
                let prefix: String = "This permanently deletes \(entry.dn) and \(descendants) \(noun) beneath it"
                let suffix: String = "from the server — \(entry.subtreeCount) in total. This cannot be undone."
                Text("\(prefix) \(suffix)")
            } else {
                Text("This permanently deletes \(entry.dn) from the server. This cannot be undone.")
            }
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sheet(item: $newEntryRequest) { request in
            NewEntrySheet(parentDN: request.parentDN, schema: schema) { dn, attributes in
                createEntry(dn: dn, attributes: attributes)
            }
        }
        .sheet(item: $advancedSearchRequest) { request in
            AdvancedSearchSheet(connection: connection, defaultBaseDN: request.baseDN) { dn in
                reveal(dn)
            }
        }
        .sheet(item: $groupForMembersEditing) { group in
            GroupMembersSheet(group: group, connection: connection) {
                await reload(group.dn)
            }
        }
        .sheet(item: $entryForRename) { entry in
            RenameEntrySheet(entry: entry) { newRDN in
                rename(entry, to: newRDN)
            }
        }
        .sheet(item: $entryForPasswordSet) { entry in
            SetPasswordSheet { plaintext, scheme in
                setPassword(plaintext, scheme: scheme, for: entry)
            }
        }
        .sheet(item: $entryForTestBind) { entry in
            TestBindSheet(connection: connection, dn: entry.dn)
        }
        .focusedSceneValue(\.directoryCommands, DirectoryCommands(
            newEntry: { newEntryRequest = NewEntryRequest(parentDN: selection ?? root.dn) },
            importLDIF: { importLDIF() },
            openSchema: { openWindow(id: "schema", value: connection) },
            openLDIFEditor: { openWindow(id: "ldif", value: connection) },
            openServerInfo: { openWindow(id: "serverInfo", value: connection) },
            advancedSearch: {
                advancedSearchRequest = AdvancedSearchRequest(baseDN: selection ?? root.dn)
            },
            goToDN: { openGoTo() },
            toggleBookmark: selectedEntry.map { entry in { onToggleBookmark(entry.dn) } },
            isSelectedBookmarked: selectedEntry.map { bookmarks.contains($0.dn) } ?? false,
            isReadOnly: isReadOnly,
            editEntry: selectedEntry.map { entry in
                { openWindow(id: "editEntry", value: EditEntryRequest(connection: connection, dn: entry.dn)) }
            },
            refreshSelected: selectedEntry.map { entry in { refresh(entry) } },
            renameSelected: (selectedEntry != nil && !isReadOnly)
                ? { if let entry = selectedEntry { entryForRename = entry } } : nil,
            copyDN: selectedEntry.map { entry in { copyToPasteboard(entry.dn) } },
            setPassword: selectedEntry.flatMap { entry in
                (!isReadOnly && canSet("userPassword", on: entry)) ? { entryForPasswordSet = entry } : nil
            },
            setPhoto: selectedEntry.flatMap { entry in
                (!isReadOnly && canSet("jpegPhoto", on: entry)) ? { setPhoto(for: entry) } : nil
            },
            testBind: selectedEntry.flatMap { entry in
                hasUserPassword(entry) ? { entryForTestBind = entry } : nil
            },
            deleteSelected: (selectedEntry != nil && !isReadOnly)
                ? { if let entry = selectedEntry { entryPendingDeletion = entry } } : nil,
            editMembers: selectedEntry.flatMap { entry in
                (!isReadOnly && GroupMembersSheet.isGroup(entry)) ? { groupForMembersEditing = entry } : nil
            }
        ))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                newEntryRequest = NewEntryRequest(parentDN: selection ?? root.dn)
            } label: {
                Image(systemName: "plus")
            }
            .help("New Entry (⌘N)")
            .disabled(isReadOnly)

            Button {
                importLDIF()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Import LDIF")
            .disabled(isReadOnly)

            Button {
                openWindow(id: "schema", value: connection)
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .help("Schema")

            Button {
                openWindow(id: "ldif", value: connection)
            } label: {
                Image(systemName: "curlybraces")
            }
            .help("LDIF Editor")

            Button {
                openWindow(id: "serverInfo", value: connection)
            } label: {
                Image(systemName: "server.rack")
            }
            .help("Server Info (⌘I)")

            Spacer()

            Button {
                openGoTo()
            } label: {
                Image(systemName: "arrow.right.to.line")
            }
            .help("Go to DN (⌘L)")
            .popover(isPresented: $isShowingGoTo, arrowEdge: .bottom) {
                goToPopover
            }

            bookmarksMenu

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

            Button {
                advancedSearchRequest = AdvancedSearchRequest(baseDN: selection ?? root.dn)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Advanced Search (⇧⌘F)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var bookmarksMenu: some View {
        Menu {
            if bookmarks.isEmpty {
                Text("No bookmarks")
            } else {
                ForEach(bookmarks, id: \.self) { dn in
                    Button {
                        goTo(dn)
                    } label: {
                        Text(Self.rdn(of: dn))
                    }
                    .help(dn)
                }
            }
            if let selectedEntry {
                Divider()
                Button {
                    onToggleBookmark(selectedEntry.dn)
                } label: {
                    Label(
                        bookmarks.contains(selectedEntry.dn)
                            ? "Remove Bookmark for “\(selectedEntry.name)”"
                            : "Bookmark “\(selectedEntry.name)”",
                        systemImage: bookmarks.contains(selectedEntry.dn) ? "bookmark.slash" : "bookmark"
                    )
                }
            }
        } label: {
            Image(systemName: "bookmark")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Bookmarks (⌘D)")
    }

    private var goToPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Go to DN").font(.caption).foregroundStyle(.secondary)
            TextField("cn=…,dc=…", text: $goToText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                .focused($goToFieldFocused)
                .onSubmit { goTo(goToText) }
            if let goToError {
                Text(goToError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Go") { goTo(goToText) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(goToText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func contextMenuContent(for entry: DirectoryEntry) -> some View {
        Button {
            selection = entry.id
        } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }

        Button {
            openWindow(id: "editEntry", value: EditEntryRequest(connection: connection, dn: entry.dn))
        } label: {
            Label("Edit Entry…", systemImage: "square.and.pencil")
        }
        .keyboardShortcut("e", modifiers: .command)

        Button {
            DispatchQueue.main.async {
                newEntryRequest = NewEntryRequest(parentDN: entry.dn)
            }
        } label: {
            Label("New Entry…", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(isReadOnly)

        Button {
            // Deferred to the next run loop tick so the context menu has
            // fully dismissed before a new sheet/panel is presented —
            // presenting synchronously from inside the menu's own action
            // can crash (same issue as NSSavePanel below, and the one
            // ConnectionListPanel's export works around the same way).
            DispatchQueue.main.async { entryForRename = entry }
        } label: {
            Label("Rename…", systemImage: "pencil.line")
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(isReadOnly)

        Button {
            refresh(entry)
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)

        Button {
            DispatchQueue.main.async {
                advancedSearchRequest = AdvancedSearchRequest(baseDN: entry.dn)
            }
        } label: {
            Label("Advanced Search…", systemImage: "magnifyingglass")
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])

        Button {
            onToggleBookmark(entry.dn)
        } label: {
            Label(
                bookmarks.contains(entry.dn) ? "Remove Bookmark" : "Add Bookmark",
                systemImage: bookmarks.contains(entry.dn) ? "bookmark.slash" : "bookmark"
            )
        }
        .keyboardShortcut("d", modifiers: .command)

        Divider()

        // Shown for every entry, but only enabled when this entry's object
        // classes actually allow the attribute — the shortcuts here mirror
        // the Entry menu, which is where they're actually registered.
        Button {
            DispatchQueue.main.async { entryForPasswordSet = entry }
        } label: {
            Label("Set Password…", systemImage: "key")
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
        .disabled(isReadOnly || !canSet("userPassword", on: entry))

        Button {
            setPhoto(for: entry)
        } label: {
            Label("Set Photo…", systemImage: "photo")
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(isReadOnly || !canSet("jpegPhoto", on: entry))

        Button {
            DispatchQueue.main.async { entryForTestBind = entry }
        } label: {
            Label("Test Bind…", systemImage: "checkmark.shield")
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])
        .disabled(!hasUserPassword(entry))

        if GroupMembersSheet.isGroup(entry) {
            Button {
                DispatchQueue.main.async {
                    groupForMembersEditing = entry
                }
            } label: {
                Label("Edit Members…", systemImage: "person.2.badge.gearshape")
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(isReadOnly)
        }

        Divider()

        Button {
            DispatchQueue.main.async {
                pickerRequest = PickerRequest(kind: .move, entry: entry)
            }
        } label: {
            Label("Move to…", systemImage: "arrow.turn.up.right")
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(isReadOnly)

        Button {
            DispatchQueue.main.async {
                pickerRequest = PickerRequest(kind: .copy, entry: entry)
            }
        } label: {
            Label("Copy to…", systemImage: "square.on.square")
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(isReadOnly)

        Button {
            copyToPasteboard(entry.dn)
        } label: {
            Label("Copy DN", systemImage: "doc.on.doc")
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])

        Button {
            DispatchQueue.main.async {
                actions.exportLDIF(entry)
            }
        } label: {
            Label("Export as LDIF", systemImage: "square.and.arrow.up")
        }
        .keyboardShortcut("x", modifiers: [.command, .shift])

        Divider()

        Button(role: .destructive) {
            DispatchQueue.main.async {
                entryPendingDeletion = entry
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(isReadOnly)
    }

    /// Whether `attribute` may be set on `entry`, per the loaded schema.
    /// With no schema — or object classes the schema doesn't know — this
    /// stays permissive rather than blocking a legitimate edit.
    private func canSet(_ attribute: String, on entry: DirectoryEntry) -> Bool {
        guard let schema else { return true }
        let objectClasses = entry.objectClassNames
        guard schema.recognizesAnyObjectClass(objectClasses) else { return true }
        return schema.permitsAttribute(attribute, forObjectClasses: objectClasses)
    }

    /// Whether this entry actually has a `userPassword` value — unlike
    /// `canSet`, this isn't about what the schema *allows* (plain
    /// `organizationalUnit` legitimately permits `userPassword` per RFC
    /// 4519, so `ou=test` passes `canSet` too) but about whether trying to
    /// bind as it means anything.
    private func hasUserPassword(_ entry: DirectoryEntry) -> Bool {
        entry.attributes.contains { $0.name.caseInsensitiveCompare("userPassword") == .orderedSame }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Runs a write against the server, then refreshes the whole tree —
    /// same pattern `EntryDetailView` uses for its own actions.
    private func perform(reloadSelecting dn: String?, _ operation: @escaping () async throws -> Void) {
        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }
            do {
                try await operation()
                await reload(dn)
            } catch {
                actionError = "\(error)"
            }
        }
    }

    private func move(_ entry: DirectoryEntry, to newSuperiorDN: String) {
        let newDN = "\(entry.name),\(newSuperiorDN)"
        perform(reloadSelecting: newDN) {
            _ = try await actions.move(entry, to: newSuperiorDN)
        }
    }

    private func copy(_ entry: DirectoryEntry, to newSuperiorDN: String) {
        let newRootDN = "\(entry.name),\(newSuperiorDN)"
        perform(reloadSelecting: newRootDN) {
            _ = try await actions.copy(entry, to: newSuperiorDN)
        }
    }

    private func createEntry(dn: String, attributes: [(name: String, value: String)]) {
        perform(reloadSelecting: dn) {
            try await actions.createEntry(dn: dn, attributes: attributes)
        }
    }

    private func refresh(_ entry: DirectoryEntry) {
        let dn = entry.dn
        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }
            await reload(dn)
        }
    }

    private func rename(_ entry: DirectoryEntry, to newRDN: String) {
        let parentDN = entry.dn.contains(",")
            ? String(entry.dn.drop(while: { $0 != "," }).dropFirst())
            : ""
        let newDN = parentDN.isEmpty ? newRDN : "\(newRDN),\(parentDN)"
        perform(reloadSelecting: newDN) {
            _ = try await actions.rename(entry, toRDN: newRDN)
        }
    }

    private func setPassword(_ plaintext: String, scheme: PasswordScheme, for entry: DirectoryEntry) {
        let dn = entry.dn
        perform(reloadSelecting: dn) {
            try await actions.setPassword(plaintext, scheme: scheme, forDN: dn)
        }
    }

    private func setPhoto(for entry: DirectoryEntry) {
        let dn = entry.dn
        // Deferred so the context menu is fully gone before the panel opens
        // — same crash guard as the sheet presentations above.
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                perform(reloadSelecting: dn) {
                    try await actions.setPhoto(fileURL: url, forDN: dn, attribute: "jpegPhoto")
                }
            }
        }
    }

    private func importLDIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ldif") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        DispatchQueue.main.async {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    actionError = "Couldn't read \(url.lastPathComponent) as text."
                    return
                }
                let entries = LDIFParser.parse(text)
                guard !entries.isEmpty else {
                    actionError = "No entries found in \(url.lastPathComponent)."
                    return
                }
                perform(reloadSelecting: selection) {
                    try await actions.importLDIF(entries)
                }
            }
        }
    }

    private func delete(_ entry: DirectoryEntry) {
        // Preserve whatever's currently selected if it's unrelated to what's
        // being deleted; `reload(selecting:)` already falls back to nil if
        // that dn turns out not to exist anymore (e.g. it was the deleted
        // entry, or a descendant of it).
        perform(reloadSelecting: selection) {
            try await actions.delete(entry)
        }
    }

    private func deleteAlertTitle(for entry: DirectoryEntry?) -> String {
        guard let entry else { return "Delete Entry?" }
        return entry.subtreeCount > 1
            ? "Delete “\(entry.name)” and everything under it?"
            : "Delete “\(entry.name)”?"
    }

    /// Expands every ancestor of `dn` (so it's actually visible in the
    /// tree, not hidden inside a collapsed disclosure group) and selects
    /// it — `.onChange(of: selection)` handles the scroll. Used when a
    /// result is picked from Advanced Search, which can land anywhere in
    /// the directory regardless of what's currently expanded.
    private func reveal(_ dn: String) {
        for ancestor in Self.ancestorDNs(of: dn) {
            expandedIDs.insert(ancestor)
        }
        selection = dn
    }

    private func openGoTo() {
        goToText = selectedEntry?.dn ?? ""
        goToError = nil
        isShowingGoTo = true
        DispatchQueue.main.async { goToFieldFocused = true }
    }

    /// Jump to `input` if a matching entry exists in the loaded tree — an
    /// exact dn match first, then a whitespace/case-insensitive one so a
    /// pasted dn that differs only cosmetically still lands.
    private func goTo(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let target = root.find(id: trimmed)?.dn ?? firstDN(matching: trimmed)
        if let target {
            reveal(target)
            isShowingGoTo = false
            goToText = ""
            goToError = nil
        } else {
            goToError = "No entry with that DN in this directory."
        }
    }

    private static func normalizeDN(_ dn: String) -> String {
        dn.lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ",")
    }

    private func firstDN(matching input: String) -> String? {
        let target = Self.normalizeDN(input)
        var match: String?
        func walk(_ entry: DirectoryEntry) {
            if match != nil { return }
            if Self.normalizeDN(entry.dn) == target { match = entry.dn; return }
            for child in entry.children ?? [] { walk(child) }
        }
        walk(root)
        return match
    }

    /// The leftmost `attr=value` of a dn — the label shown for a bookmark.
    private static func rdn(of dn: String) -> String {
        String(dn.split(separator: ",").first ?? Substring(dn))
    }

    /// Every suffix of `dn` after stripping one RDN component at a time —
    /// e.g. for "uid=x,ou=People,dc=corp,dc=com" that's
    /// ["ou=People,dc=corp,dc=com", "dc=corp,dc=com", "dc=com"]. The dn
    /// itself isn't included; expanding a leaf's own (nonexistent) children
    /// isn't needed to reveal it.
    private static func ancestorDNs(of dn: String) -> [String] {
        var result: [String] = []
        var remaining = Substring(dn)
        while let commaIndex = remaining.firstIndex(of: ",") {
            remaining = remaining[remaining.index(after: commaIndex)...]
            result.append(String(remaining))
        }
        return result
    }
}

/// A tree row with an externally controllable expanded state — plain
/// `OutlineGroup` manages this internally with no way to set it from
/// outside, which is what `DirectoryTreeView.reveal(_:)` needs.
private struct DirectoryOutlineRow: View {
    let entry: DirectoryEntry
    @Binding var expandedIDs: Set<DirectoryEntry.ID>
    let bookmarks: Set<String>

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(entry.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedIDs.insert(entry.id)
                } else {
                    expandedIDs.remove(entry.id)
                }
            }
        )
    }

    var body: some View {
        if let children = entry.children, !children.isEmpty {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { child in
                    DirectoryOutlineRow(entry: child, expandedIDs: $expandedIDs, bookmarks: bookmarks)
                }
            } label: {
                rowLabel(name: "\(entry.name) (\(children.count))")
                    .tag(entry.id)
            }
            .id(entry.id)
        } else {
            rowLabel(name: entry.name)
                .tag(entry.id)
                .id(entry.id)
        }
    }

    private func rowLabel(name: String) -> some View {
        HStack(spacing: 4) {
            Label(name, systemImage: entry.icon)
            if bookmarks.contains(entry.id) {
                Spacer(minLength: 4)
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Bookmarked")
            }
        }
    }
}

#Preview {
    DirectoryTreeView(
        root: .mockRoot,
        selection: .constant(nil),
        connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "", bindDN: ""),
        schema: nil,
        bookmarks: ["ou=People,dc=corp,dc=example,dc=com"],
        onToggleBookmark: { _ in },
        reload: { _ in }
    )
    .frame(width: 260, height: 400)
}
