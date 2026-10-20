//
//  BranchOperations.swift
//  ldap-studio
//
//  Delete, move, copy and LDIF export of entries that may have children.
//  These act on the real branch on the server, not on whatever part of it
//  the tree happens to have loaded: each one first counts what it's about
//  to touch (so the confirmation can say how many entries are affected),
//  then runs with progress and a Cancel button, and finally tells the tree
//  what changed so it can update in place.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What a write changed, so the tree (and the detail view) can update the
/// affected nodes instead of reloading everything.
enum DirectoryChange {
    case added(String)
    case removed(String)
    case moved(from: String, to: String)
    case modified(String)
    /// Something changed under this DN that wasn't tracked entry by entry
    /// (a cancelled or failed bulk operation, an LDIF import).
    case branchChanged(String)
}

@MainActor
@Observable
final class BranchOperations {
    struct Progress {
        var title: String
        var completed = 0
        /// nil while the total isn't known yet.
        var total: Int?
        /// Shown under the bar — what Cancel will (and won't) undo.
        var cancelNote: String?
    }

    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let actionLabel: String
        let isDestructive: Bool
        let action: () -> Void
    }

    var connection: SavedConnection
    var schema: LdapSchema?
    /// Applies a finished change to the tree.
    @ObservationIgnored var onChange: (DirectoryChange) async -> Void = { _ in }
    /// Selects an entry once an operation has created or moved it.
    @ObservationIgnored var onSelect: (String) -> Void = { _ in }

    private(set) var progress: Progress?
    var confirmation: Confirmation?
    var errorMessage: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(connection: SavedConnection, schema: LdapSchema? = nil) {
        self.connection = connection
        self.schema = schema
    }

    var isBusy: Bool { progress != nil }

    private var actions: EntryActions {
        EntryActions(connection: connection, schema: schema)
    }

    func cancel() {
        task?.cancel()
    }

    private func run(_ initial: Progress, _ work: @escaping () async throws -> Void) {
        guard task == nil else { return }
        progress = initial
        task = Task {
            defer {
                progress = nil
                task = nil
            }
            do {
                try await work()
            } catch is CancellationError {
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    private func setCompleted(_ count: Int) {
        progress?.completed = count
    }

    /// Applies `change` even when the operation that made it was just
    /// cancelled: the tree re-reads the branch with searches of its own,
    /// which would otherwise inherit the cancellation and fail.
    private func report(_ change: DirectoryChange) async {
        let onChange = onChange
        await Task { await onChange(change) }.value
    }

    /// The selected DNs minus any that sit inside another selected one —
    /// acting on the outer branch already covers them.
    static func operationRoots(_ dns: [String]) -> [String] {
        var roots: [String] = []
        for dn in dns.sorted(by: { DN.depth($0) < DN.depth($1) })
        where !roots.contains(where: { DN.isWithin(dn, $0) }) {
            roots.append(dn)
        }
        return roots
    }

    private func blockedByReadOnly() -> Bool {
        guard connection.isReadOnly else { return false }
        errorMessage = ConnectionError.ReadOnly.description
        return true
    }

    // MARK: Delete

    func requestDelete(_ dns: [String]) {
        guard !blockedByReadOnly() else { return }
        let roots = Self.operationRoots(dns)
        guard !roots.isEmpty else { return }
        run(Progress(title: "Counting entries to delete…")) { [self] in
            var branches: [(root: String, dns: [String])] = []
            var counted = 0
            for root in roots {
                let base = counted
                let dns = try await actions.branchDNs(root) { self.setCompleted(base + $0) }
                counted += dns.count
                branches.append((root, dns))
            }
            confirmation = Confirmation(
                title: Self.deleteTitle(roots: roots, total: counted),
                message: "This permanently deletes \(Self.entries(counted)) from the server, including everything under the selected \(roots.count == 1 ? "entry" : "entries"). This cannot be undone.",
                actionLabel: counted == 1 ? "Delete" : "Delete \(counted.formatted()) Entries",
                isDestructive: true
            ) { [self] in performDelete(branches, total: counted) }
        }
    }

    private static func deleteTitle(roots: [String], total: Int) -> String {
        guard roots.count == 1 else { return "Delete \(total.formatted()) Entries?" }
        let name = DN.rdn(of: roots[0])
        return total > 1
            ? "Delete “\(name)” and the \(entries(total - 1)) under it?"
            : "Delete “\(name)”?"
    }

    private static func entries(_ n: Int) -> String {
        n == 1 ? "1 entry" : "\(n.formatted()) entries"
    }

    private func performDelete(_ branches: [(root: String, dns: [String])], total: Int) {
        run(Progress(
            title: "Deleting…", total: total,
            cancelNote: "Cancel stops after the entries being deleted right now. Entries go deepest first, so whatever is left is still intact."
        )) { [self] in
            var done = 0
            for branch in branches {
                let base = done
                do {
                    try await actions.deleteBranch(branch.dns) { self.setCompleted(base + $0) }
                } catch {
                    await report(.branchChanged(DN.parent(of: branch.root) ?? branch.root))
                    throw error
                }
                done += branch.dns.count
                await report(.removed(branch.root))
            }
        }
    }

    // MARK: Move

    func requestMove(_ dns: [String], to destination: String) {
        guard !blockedByReadOnly() else { return }
        let roots = Self.operationRoots(dns)
        guard !roots.isEmpty else { return }
        guard !roots.contains(where: { DN.isWithin(destination, $0) }) else {
            errorMessage = "An entry cannot be moved into itself or one of its descendants."
            return
        }
        let moving = roots.filter { !DN.same(DN.parent(of: $0) ?? "", destination) }
        guard !moving.isEmpty else {
            errorMessage = "The selected \(roots.count == 1 ? "entry is" : "entries are") already under \(destination)."
            return
        }
        run(Progress(title: "Counting entries to move…")) { [self] in
            var counted = 0
            for root in moving {
                let base = counted
                counted += try await actions.branchDNs(root) { self.setCompleted(base + $0) }.count
            }
            let title = moving.count == 1 ? "Move “\(DN.rdn(of: moving[0]))”?" : "Move \(moving.count) Entries?"
            let message = moving.count == 1 && counted > 1
                ? "“\(DN.rdn(of: moving[0]))” and the \(Self.entries(counted - 1)) under it will be moved under \(destination)."
                : "\(Self.entries(counted).capitalizedFirst) will be moved under \(destination)."
            confirmation = Confirmation(title: title, message: message, actionLabel: "Move",
                                        isDestructive: false) { [self] in
                performMove(moving, to: destination)
            }
        }
    }

    private func performMove(_ roots: [String], to destination: String) {
        run(Progress(title: "Moving…", total: roots.count)) { [self] in
            var moved: [String] = []
            for root in roots {
                try Task.checkCancellation()
                let newDN = try await actions.move(root, to: destination)
                moved.append(newDN)
                await report(.moved(from: root, to: newDN))
                setCompleted(moved.count)
            }
            if let first = moved.first { onSelect(first) }
        }
    }

    // MARK: Copy

    func requestCopy(_ dn: String, to destination: String) {
        guard !blockedByReadOnly() else { return }
        guard !DN.isWithin(destination, dn) else {
            errorMessage = "An entry cannot be copied into itself or one of its descendants."
            return
        }
        run(Progress(title: "Counting entries to copy…")) { [self] in
            let count = try await actions.branchDNs(dn) { self.setCompleted($0) }.count
            confirmation = Confirmation(
                title: "Copy “\(DN.rdn(of: dn))”?",
                message: count > 1
                    ? "“\(DN.rdn(of: dn))” and the \(Self.entries(count - 1)) under it will be copied under \(destination)."
                    : "“\(DN.rdn(of: dn))” will be copied under \(destination).",
                actionLabel: count > 1 ? "Copy \(count.formatted()) Entries" : "Copy",
                isDestructive: false
            ) { [self] in performCopy(dn, to: destination, total: count) }
        }
    }

    private func performCopy(_ dn: String, to destination: String, total: Int) {
        run(Progress(title: "Copying…", total: total,
                     cancelNote: "Cancel stops after the current entry; entries already copied stay.")) { [self] in
            do {
                let newDN = try await actions.copy(dn, to: destination) { self.setCompleted($0) }
                await report(.added(newDN))
                onSelect(newDN)
            } catch {
                await report(.branchChanged(destination))
                throw error
            }
        }
    }

    // MARK: LDIF

    /// Asks whether to include what's under the entries, when any of them
    /// might have something under it. nil = cancelled.
    private func askIncludeSubtree(_ roots: [String], mayHaveChildren: Bool, verb: String) -> Bool? {
        guard mayHaveChildren else { return false }
        let alert = NSAlert()
        alert.messageText = roots.count == 1 ? "\(verb) Entry or Entire Branch?" : "\(verb) Entries or Entire Branches?"
        alert.informativeText = roots.count == 1
            ? "“\(DN.rdn(of: roots[0]))” may have entries under it. The whole branch is read from the server."
            : "Some of the selected entries may have entries under them. Branches are read from the server."
        alert.addButton(withTitle: roots.count == 1 ? "Entry Only" : "Entries Only")
        alert.addButton(withTitle: roots.count == 1 ? "Entry + Subtree" : "Entries + Subtrees")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    /// Writes LDIF for `dns` (and, if the user wants, everything under
    /// them) to a file they choose, streaming it from the server.
    func exportLDIF(_ dns: [String], mayHaveChildren: Bool) {
        let roots = Self.operationRoots(dns)
        guard !roots.isEmpty, !isBusy else { return }
        // Deferred so a context menu has fully closed before a modal opens.
        DispatchQueue.main.async { [self] in
            guard let subtree = askIncludeSubtree(roots, mayHaveChildren: mayHaveChildren, verb: "Export") else { return }
            let name = roots.count == 1
                ? EntryActions.safeFilename(DN.rdn(of: roots[0])) + (subtree ? "_tree" : "")
                : "ldap-entries"
            chooseFile(suggestedName: name) { [self] url in
                stream(to: url) { sink, progress in
                    try await self.actions.writeLDIF(roots, subtree: subtree, progress: progress, to: sink)
                }
            }
        }
    }

    /// Writes LDIF for every result of `request`, or only those in
    /// `selected`, re-running the search with all attributes.
    func exportLDIF(of request: LdapSearchRequest, selected: Set<String>?) {
        guard !isBusy else { return }
        chooseFile(suggestedName: "ldap-search-results") { [self] url in
            stream(to: url) { sink, progress in
                try await self.actions.writeLDIF(of: request, only: selected, progress: progress, to: sink)
            }
        }
    }

    private func chooseFile(suggestedName: String, then: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        // NSSavePanel appends the allowed type's extension itself — since
        // UTType(filenameExtension:) makes an ad-hoc type here (there's
        // no system-registered "ldif" UTType), the panel doesn't
        // recognize an extension already in the name field as matching,
        // and appends a second one. So the name field carries no
        // extension at all; the panel adds it.
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [UTType(filenameExtension: "ldif") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            then(url)
        }
    }

    private func stream(to url: URL,
                        _ write: @escaping (_ sink: (String) throws -> Void, _ progress: (Int) -> Void) async throws -> Void) {
        run(Progress(title: "Exporting LDIF…")) { [self] in
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            do {
                try await write({ text in try handle.write(contentsOf: Data(text.utf8)) },
                                { self.setCompleted($0) })
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }
    }

    private static let clipboardWarningThreshold = 1_048_576

    /// Copies LDIF for `dns` (optionally with their branches) to the
    /// clipboard. Large results ask first — multi-megabyte clipboard
    /// contents are expensive for the app they're pasted into.
    func copyLDIF(_ dns: [String], mayHaveChildren: Bool) {
        let roots = Self.operationRoots(dns)
        guard !roots.isEmpty, !isBusy else { return }
        DispatchQueue.main.async { [self] in
            guard let subtree = askIncludeSubtree(roots, mayHaveChildren: mayHaveChildren, verb: "Copy") else { return }
            run(Progress(title: "Reading LDIF…")) { [self] in
                var ldif = ""
                try await actions.writeLDIF(roots, subtree: subtree, progress: { self.setCompleted($0) }) {
                    ldif += $0
                }
                let byteCount = ldif.lengthOfBytes(using: .utf8)
                if byteCount > Self.clipboardWarningThreshold {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Large LDIF Clipboard Content"
                    alert.informativeText = "This LDIF is \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)). Copying it may temporarily slow this app or the app where you paste it."
                    alert.addButton(withTitle: "Copy Anyway")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ldif, forType: .string)
            }
        }
    }

    // MARK: Import

    func importLDIF(_ entries: [LDIFEntry]) {
        guard !blockedByReadOnly() else { return }
        run(Progress(title: "Importing LDIF…", total: entries.count,
                     cancelNote: "Cancel stops after the current entry; entries already added stay.")) { [self] in
            defer {
                // Refresh the branches the file touched, once each.
                let parents = Set(entries.compactMap { DN.parent(of: $0.dn) }.map(DN.normalize))
                let touched = Self.operationRoots(Array(parents))
                Task { for dn in touched { await self.onChange(.branchChanged(dn)) } }
            }
            try await actions.importLDIF(entries) { self.setCompleted($0) }
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Presentation

extension View {
    /// Shows `operations`' progress over this view (with Cancel), its
    /// confirmations, and its errors.
    func branchOperations(_ operations: BranchOperations) -> some View {
        modifier(BranchOperationsPresenter(operations: operations))
    }
}

private struct BranchOperationsPresenter: ViewModifier {
    @Bindable var operations: BranchOperations

    func body(content: Content) -> some View {
        content
            .disabled(operations.isBusy)
            .overlay {
                if let progress = operations.progress {
                    ZStack {
                        Color.black.opacity(0.08)
                        BranchProgressCard(progress: progress) { operations.cancel() }
                    }
                }
            }
            .alert(
                operations.confirmation?.title ?? "",
                isPresented: Binding(
                    get: { operations.confirmation != nil },
                    set: { if !$0 { operations.confirmation = nil } }
                ),
                presenting: operations.confirmation
            ) { confirmation in
                Button(confirmation.actionLabel, role: confirmation.isDestructive ? .destructive : nil) {
                    operations.confirmation = nil
                    confirmation.action()
                }
                Button("Cancel", role: .cancel) {
                    operations.confirmation = nil
                }
            } message: { confirmation in
                Text(confirmation.message)
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { operations.errorMessage != nil },
                    set: { if !$0 { operations.errorMessage = nil } }
                ),
                presenting: operations.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }
}

private struct BranchProgressCard: View {
    let progress: BranchOperations.Progress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(progress.title).font(.headline)
            if let total = progress.total, total > 0 {
                ProgressView(value: Double(min(progress.completed, total)), total: Double(total))
                Text("\(progress.completed.formatted()) of \(total.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().progressViewStyle(.linear)
                Text(progress.completed > 0 ? "\(progress.completed.formatted()) entries so far" : "Starting…")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let note = progress.cancelNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }
}
