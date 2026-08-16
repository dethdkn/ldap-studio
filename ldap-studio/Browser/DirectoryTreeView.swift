//
//  DirectoryTreeView.swift
//  ldap-studio
//

import SwiftUI

struct DirectoryTreeView: View {
    let root: DirectoryEntry
    @Binding var selection: DirectoryEntry.ID?
    let connection: SavedConnection
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

    @State private var pickerRequest: PickerRequest?
    @State private var entryPendingDeletion: DirectoryEntry?

    @State private var isPerformingAction = false
    @State private var actionError: String?

    private var actions: EntryActions {
        EntryActions(connection: connection)
    }

    var body: some View {
        List(selection: $selection) {
            OutlineGroup(root, children: \.children) { entry in
                Label(entry.name, systemImage: entry.icon)
                    .tag(entry.id)
            }
        }
        .disabled(isPerformingAction)
        .contextMenu(forSelectionType: DirectoryEntry.ID.self) { ids in
            if let id = ids.first, let entry = root.find(id: id) {
                contextMenuContent(for: entry)
            }
        }
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

    private func delete(_ entry: DirectoryEntry) {
        // Preserve whatever's currently selected if it's unrelated to what's
        // being deleted; `reload(selecting:)` already falls back to nil if
        // that dn turns out not to exist anymore (e.g. it was the deleted
        // entry, or a descendant of it).
        perform(reloadSelecting: selection) {
            try await actions.delete(entry)
        }
    }
}

#Preview {
    DirectoryTreeView(
        root: .mockRoot,
        selection: .constant(nil),
        connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "", bindDN: ""),
        reload: { _ in }
    )
    .frame(width: 260, height: 400)
}
