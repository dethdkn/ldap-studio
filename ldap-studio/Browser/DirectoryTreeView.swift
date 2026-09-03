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

    @State private var pickerRequest: PickerRequest?
    @State private var entryPendingDeletion: DirectoryEntry?
    @State private var newEntryRequest: NewEntryRequest?

    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var searchText = ""
    @State private var isShowingAdvancedSearch = false

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

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            ScrollViewReader { proxy in
                List(selection: $selection) {
                    if let filteredRoot {
                        DirectoryOutlineRow(entry: filteredRoot, expandedIDs: $expandedIDs)
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
            "Delete \(entryPendingDeletion?.name ?? "")?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            presenting: entryPendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) {
                delete(entry)
                entryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: { entry in
            if entry.children?.isEmpty == false {
                Text("\(entry.dn) has child entries — deleting it will delete all of them too. This cannot be undone.")
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
        .sheet(isPresented: $isShowingAdvancedSearch) {
            AdvancedSearchSheet(connection: connection, defaultBaseDN: root.dn) { dn in
                reveal(dn)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                newEntryRequest = NewEntryRequest(parentDN: selection ?? root.dn)
            } label: {
                Image(systemName: "plus")
            }
            .help("New Entry")

            Button {
                importLDIF()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Import LDIF")

            Button {
                openWindow(id: "schema", value: connection)
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .help("Schema")

            Spacer()

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

            Button {
                isShowingAdvancedSearch = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Advanced Search")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func contextMenuContent(for entry: DirectoryEntry) -> some View {
        Button {
            selection = entry.id
        } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }

        Divider()

        Button {
            // Deferred to the next run loop tick so the context menu has
            // fully dismissed before a new sheet/panel is presented —
            // presenting synchronously from inside the menu's own action
            // can crash (same issue as NSSavePanel below, and the one
            // ConnectionListPanel's export works around the same way).
            DispatchQueue.main.async {
                pickerRequest = PickerRequest(kind: .move, entry: entry)
            }
        } label: {
            Label("Move DN", systemImage: "arrow.turn.up.right")
        }

        Button {
            DispatchQueue.main.async {
                pickerRequest = PickerRequest(kind: .copy, entry: entry)
            }
        } label: {
            Label("Copy DN", systemImage: "square.on.square")
        }

        Button {
            DispatchQueue.main.async {
                actions.exportLDIF(entry)
            }
        } label: {
            Label("Export as LDIF", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            DispatchQueue.main.async {
                entryPendingDeletion = entry
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
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
                    DirectoryOutlineRow(entry: child, expandedIDs: $expandedIDs)
                }
            } label: {
                Label(entry.name, systemImage: entry.icon)
                    .tag(entry.id)
            }
            .id(entry.id)
        } else {
            Label(entry.name, systemImage: entry.icon)
                .tag(entry.id)
                .id(entry.id)
        }
    }
}

#Preview {
    DirectoryTreeView(
        root: .mockRoot,
        selection: .constant(nil),
        connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "", bindDN: ""),
        schema: nil,
        reload: { _ in }
    )
    .frame(width: 260, height: 400)
}
