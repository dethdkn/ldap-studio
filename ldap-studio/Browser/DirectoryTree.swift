//
//  DirectoryTree.swift
//  ldap-studio
//
//  The directory tree, loaded on demand. Opening a connection reads the
//  base entry and its direct children; every other level is read with a
//  one-level search the first time it's expanded, then kept for the rest
//  of the session. Nothing ever reads the whole directory, so memory grows
//  with what the user has opened rather than with the directory's size.
//
//  Tree searches only ask for what drawing a row needs (objectClass and
//  the few attributes that pick its icon or say whether it has children);
//  an entry's full attributes are read when it's selected.
//

import Foundation
import Observation

/// One entry in the tree. A class, so SwiftUI only redraws the rows whose
/// node actually changed when a branch loads or refreshes.
@MainActor
@Observable
final class TreeNode: Identifiable {
    enum Children: Equatable {
        /// Never read, or dropped by a refresh while collapsed.
        case notLoaded
        /// First read in progress; `children` fills in page by page.
        case loading
        case loaded
        case failed(String)
    }

    let dn: String
    var id: String { dn }
    /// `dn` normalized — the tree's index key.
    let key: String
    let name: String
    /// Children sort case-insensitively by RDN, like the old full-tree load.
    let sortKey: String
    private(set) var icon: String
    private(set) var objectClasses: [String]
    /// Whether the server (or, failing that, the entry's object classes)
    /// says this entry may have children — what decides the expand arrow
    /// before the children have been read.
    private(set) var mayHaveChildren: Bool

    var isExpanded = false
    fileprivate(set) var childrenState: Children = .notLoaded
    /// Sorted by RDN. Complete once `childrenState` is `.loaded`.
    fileprivate(set) var children: [TreeNode] = []
    /// True while a refresh re-reads children that are already showing.
    fileprivate(set) var isRefreshing = false
    /// How many entries the current read has received so far.
    fileprivate(set) var loadedCount = 0
    /// The server returned only part of the children (it ignored paging
    /// and hit its size limit) — the row says so rather than passing the
    /// partial list off as complete.
    fileprivate(set) var isTruncated = false
    /// Bumped by every read of the children, so a read that's been
    /// superseded (collapse and re-expand, a second refresh) can tell and
    /// leave the node alone.
    fileprivate var loadGeneration = 0

    /// Large branches are drawn a slice at a time — see `visibleChildren`.
    /// Every drawn row costs SwiftUI time on each update of its branch
    /// (about 0.3s per 10,000), so a branch is never drawn whole past
    /// `maxShowAll`; the rest is reached with Search or Go to DN.
    static let displayStep = 1_000
    static let maxShowAll = 10_000
    var displayLimit = TreeNode.displayStep
    /// Children shown even past `displayLimit`, because Go to DN or a
    /// search result revealed them.
    fileprivate(set) var pinnedChildren: Set<String> = []

    fileprivate init(row: TreeRow) {
        dn = row.dn
        key = row.key
        name = row.name
        sortKey = row.sortKey
        objectClasses = row.objectClasses
        mayHaveChildren = row.mayHaveChildren
        icon = row.icon
    }

    fileprivate convenience init(entry: LdapEntry) {
        self.init(row: TreeRow(entry))
    }

    fileprivate func update(from row: TreeRow) {
        // Assign only what changed: every assignment notifies observers.
        if objectClasses != row.objectClasses { objectClasses = row.objectClasses }
        if mayHaveChildren != row.mayHaveChildren { mayHaveChildren = row.mayHaveChildren }
        if icon != row.icon { icon = row.icon }
    }

    fileprivate func update(from entry: LdapEntry) {
        update(from: TreeRow(entry))
    }

    /// Marks that a child was just created under this entry.
    fileprivate func noteHasChildren() {
        if !mayHaveChildren { mayHaveChildren = true }
    }

    /// Whether to draw an expand arrow: until the children have been read
    /// that's the server's or the heuristic's guess; afterwards it's
    /// whether there turned out to be any.
    var showsDisclosure: Bool {
        switch childrenState {
        case .loaded: return !children.isEmpty
        case .loading, .failed: return true
        case .notLoaded: return mayHaveChildren
        }
    }

    var visibleChildren: [TreeNode] {
        guard children.count > displayLimit else { return children }
        let head = children.prefix(displayLimit)
        guard !pinnedChildren.isEmpty else { return Array(head) }
        let shown = Set(head.map(\.id))
        let extra = children.dropFirst(displayLimit).filter {
            pinnedChildren.contains($0.id) && !shown.contains($0.id)
        }
        return Array(head) + extra
    }

    var hiddenChildCount: Int {
        max(0, children.count - visibleChildren.count)
    }

    /// A stand-in for the full entry, for sheets that only need the DN and
    /// object classes; anything that needs real attribute values loads the
    /// entry itself.
    var summaryEntry: DirectoryEntry {
        DirectoryEntry(
            name: name, dn: dn, icon: icon,
            attributes: objectClasses.map { Attribute(name: "objectClass", value: $0) }
        )
    }
}

// MARK: - Whether an entry has children

/// Everything a tree row needs from one search result, worked out off the
/// main actor — a branch of 100,000 entries is a lot of DNs to normalize
/// and object classes to look at.
nonisolated struct TreeRow: Sendable {
    let dn: String
    let key: String
    let name: String
    let sortKey: String
    let objectClasses: [String]
    let mayHaveChildren: Bool
    let icon: String

    init(_ entry: LdapEntry) {
        dn = entry.dn
        key = DN.normalize(entry.dn)
        name = entry.dn.isEmpty ? entry.name : DN.rdn(of: entry.dn)
        sortKey = name.lowercased()
        objectClasses = entry.values("objectClass")
        mayHaveChildren = TreeRow.mayHaveChildren(entry)
        icon = TreeRow.icon(for: entry, mayHaveChildren: mayHaveChildren)
    }

    /// What tree searches ask for: the DN comes for free; objectClass and
    /// univentionObjectType pick the icon; the rest answer "are there
    /// children?" on servers that support them.
    static let treeAttributes = [
        "objectClass",
        "hasSubordinates",                   // RFC 3045 — OpenLDAP, 389 DS, …
        "numSubordinates",                   // 389 DS, eDirectory
        "msDS-Approx-Immed-Subordinates",    // Active Directory
        "univentionObjectType",
    ]

    /// Object classes that are almost always containers.
    private static let containerClasses: Set<String> = [
        "organizationalunit", "container", "domain", "domaindns", "dcobject",
        "organization", "country", "locality", "builtindomain", "nscontainer",
        "niscontainer", "posixcontainer", "lostandfound", "configuration",
        "grouppolicycontainer", "msds-quotacontainer", "dnszone",
    ]

    /// Object classes that are almost always leaves. On Active Directory a
    /// user or computer can still have children (e.g. BitLocker recovery
    /// keys under a computer); msDS-Approx-Immed-Subordinates catches those
    /// when the server returns it, and Go to DN / Refresh still reach them
    /// when it doesn't.
    private static let leafClasses: Set<String> = [
        "person", "organizationalperson", "inetorgperson", "user", "computer",
        "contact", "group", "groupofnames", "groupofuniquenames",
        "groupofmembers", "groupofurls", "posixaccount", "posixgroup",
        "shadowaccount", "account", "inetuser", "sambasamaccount",
        "sambagroupmapping", "device", "iphost", "ipnetwork", "ipservice",
        "foreignsecurityprincipal", "msds-managedserviceaccount",
        "msds-groupmanagedserviceaccount", "dnsnode", "printqueue",
        "organizationalrole", "simplesecurityobject", "alias", "referral",
        "nisnetgroup", "mailrecipient",
    ]

    /// The server's answer when it gives one (hasSubordinates and friends);
    /// otherwise a guess from the object classes: containers yes, accounts
    /// and groups no, anything unrecognised yes — its arrow disappears if
    /// it turns out to be empty.
    static func mayHaveChildren(_ entry: LdapEntry) -> Bool {
        if let value = entry.values("hasSubordinates").first {
            return value.caseInsensitiveCompare("TRUE") == .orderedSame
        }
        if let count = entry.values("numSubordinates").first.flatMap(Int.init) {
            return count > 0
        }
        if let count = entry.values("msDS-Approx-Immed-Subordinates").first.flatMap(Int.init) {
            return count > 0
        }
        let classes = Set(entry.values("objectClass").map { $0.lowercased() })
        if !classes.isDisjoint(with: containerClasses) { return true }
        if !classes.isDisjoint(with: leafClasses) { return false }
        return true
    }

    static func icon(for entry: LdapEntry, mayHaveChildren: Bool) -> String {
        DirectoryEntry.icon(forObjectClasses: entry.values("objectClass"),
                            univentionType: entry.values("univentionObjectType").first,
                            hasChildren: mayHaveChildren)
    }
}

// MARK: - The tree

@MainActor
@Observable
final class DirectoryTree {
    /// Replaced when the user trusts a certificate or SSH host key, so
    /// later searches use the pinned value.
    var connection: SavedConnection
    let baseDN: String

    private(set) var root: TreeNode?
    /// Loading the base entry itself failed — the whole tree can't show.
    private(set) var rootError: Error?

    /// Every node read so far, by normalized DN.
    @ObservationIgnored private var nodes: [String: TreeNode] = [:]
    /// In-flight child reads, by normalized DN.
    @ObservationIgnored private var loads: [String: Task<Void, Never>] = [:]

    init(connection: SavedConnection) {
        self.connection = connection
        self.baseDN = connection.baseDN
    }

    var target: LdapTarget { connection.ldapTarget }

    func node(_ dn: String) -> TreeNode? {
        nodes[DN.normalize(dn)]
    }

    /// Reads the base entry and its direct children — all that opening a
    /// connection shows. Both searches run at once.
    func loadRoot() async {
        rootError = nil
        for task in loads.values { task.cancel() }
        loads = [:]

        let placeholder = LdapEntry(dn: baseDN, name: baseDN.isEmpty ? "Root DSE" : baseDN, attributes: [])
        let node = TreeNode(entry: placeholder)
        nodes = [DN.normalize(node.dn): node]
        node.isExpanded = true
        // The children's first page and the base entry are read side by
        // side; the tree shows as soon as the base entry is back.
        let children = loadChildren(of: node)

        if !baseDN.isEmpty {
            do {
                guard let entry = try await fetchEntry(target, dn: baseDN,
                                                       attributes: TreeRow.treeAttributes) else {
                    throw ConnectionError.SearchFailed(reason: "Base DN \"\(baseDN)\" was not found")
                }
                node.update(from: entry)
            } catch {
                children.cancel()
                nodes = [:]
                root = nil
                rootError = error
                return
            }
        }
        root = node
    }

    // MARK: Expanding

    func setExpanded(_ node: TreeNode, _ expanded: Bool) {
        guard node.isExpanded != expanded else { return }
        node.isExpanded = expanded
        if expanded {
            switch node.childrenState {
            case .notLoaded, .failed: loadChildren(of: node)
            case .loading, .loaded: break
            }
        } else if node.childrenState == .loading || node.isRefreshing {
            // Nobody's looking at it anymore — stop reading it.
            cancelLoad(of: node)
        }
    }

    func retry(_ node: TreeNode) {
        loadChildren(of: node)
    }

    /// Reads `node`'s children if they haven't been, without expanding it
    /// in the main tree — for the destination picker, which shares this
    /// cache but keeps its own expansion state.
    func ensureChildren(of node: TreeNode) {
        switch node.childrenState {
        case .notLoaded, .failed: loadChildren(of: node)
        case .loading, .loaded: break
        }
    }

    func showMore(_ node: TreeNode) {
        node.displayLimit += TreeNode.displayStep
    }

    func showAll(_ node: TreeNode) {
        guard node.children.count <= TreeNode.maxShowAll else { return }
        node.displayLimit = max(node.children.count, TreeNode.displayStep)
    }

    private func cancelLoad(of node: TreeNode) {
        node.loadGeneration += 1
        loads[node.key]?.cancel()
        loads[node.key] = nil
        if node.childrenState == .loading {
            node.childrenState = .notLoaded
            node.children = []
            node.loadedCount = 0
        }
        node.isRefreshing = false
    }

    /// Reads `node`'s direct children with a paged one-level search. The
    /// first page shows as soon as it arrives and later pages are merged in
    /// as they come. If children were already showing (a refresh), they
    /// stay up until the new list is complete, and every node that's still
    /// there keeps its own state — what's expanded below it, what's loaded.
    @discardableResult
    func loadChildren(of node: TreeNode) -> Task<Void, Never> {
        let key = node.key
        loads[key]?.cancel()
        node.loadGeneration += 1
        let generation = node.loadGeneration
        let isRefresh = node.childrenState == .loaded
        if isRefresh {
            node.isRefreshing = true
        } else {
            node.childrenState = .loading
            node.children = []
        }
        node.loadedCount = 0

        let task = Task { [weak self] in
            guard let self else { return }
            await self.readChildren(of: node, isRefresh: isRefresh, generation: generation)
            if node.loadGeneration == generation { self.loads[key] = nil }
        }
        loads[key] = task
        return task
    }

    private func readChildren(of node: TreeNode, isRefresh: Bool, generation: Int) async {
        var received: [TreeRow] = []
        var truncated = false
        var lastShown = ContinuousClock.now
        // Every write to the node below happens only while this is still
        // its latest read.
        func isCurrent() -> Bool { node.loadGeneration == generation && !Task.isCancelled }
        do {
            if node.dn.isEmpty {
                received = try await namingContexts().map(TreeRow.init)
            } else {
                let request = LdapSearchRequest(
                    baseDn: node.dn, scope: .oneLevel,
                    attributes: TreeRow.treeAttributes,
                    idleTimeout: max(30, connection.timeoutSeconds * 2)
                )
                let outcome = try await pagedSearch(target, request) { page, progress in
                    received += await Self.prepare(page)
                    // Show the first page right away, then merge in batches
                    // so a branch of 100,000 doesn't redraw 200 times.
                    if progress.pages == 1 || ContinuousClock.now - lastShown > .milliseconds(500) {
                        guard isCurrent() else { return false }
                        node.loadedCount = progress.entries
                        if !isRefresh {
                            let sorted = await Self.sorted(received)
                            guard isCurrent() else { return false }
                            self.setChildren(of: node, to: sorted, complete: false)
                        }
                        lastShown = .now
                    }
                    return true
                }
                truncated = outcome.wasTruncated
            }
            guard isCurrent() else { return }
            let sorted = await Self.sorted(received)
            guard isCurrent() else { return }
            setChildren(of: node, to: sorted, complete: true)
            node.isTruncated = truncated
            node.childrenState = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent() else { return }
            if isRefresh {
                // Keep the children already showing; just say why the
                // refresh didn't happen.
                node.childrenState = .failed("\(error)")
            } else {
                node.children = []
                node.childrenState = .failed("\(error)")
            }
        }
        node.isRefreshing = false
    }

    nonisolated private static func prepare(_ page: [LdapEntry]) async -> [TreeRow] {
        await Task.detached(priority: .userInitiated) { page.map(TreeRow.init) }.value
    }

    nonisolated private static func sorted(_ rows: [TreeRow]) async -> [TreeRow] {
        await Task.detached(priority: .userInitiated) { rows.sorted { $0.sortKey < $1.sortKey } }.value
    }

    /// With an empty base DN, the tree's children are the server's naming
    /// contexts (from the root DSE).
    private func namingContexts() async throws -> [LdapEntry] {
        let dse = try await fetchEntry(target, dn: "", attributes: ["namingContexts"])
        var entries: [LdapEntry] = []
        for context in dse?.values("namingContexts") ?? [] {
            if let entry = try? await fetchEntry(target, dn: context, attributes: TreeRow.treeAttributes) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Replaces `node`'s children with `rows` (already sorted), reusing the
    /// node objects of children that were already there. When `complete`,
    /// children no longer present are forgotten along with everything
    /// under them.
    private func setChildren(of node: TreeNode, to rows: [TreeRow], complete: Bool) {
        var seen = Set<String>(minimumCapacity: rows.count)
        var children: [TreeNode] = []
        children.reserveCapacity(rows.count)
        for row in rows {
            guard seen.insert(row.key).inserted else { continue }
            if let existing = nodes[row.key] {
                if complete { existing.update(from: row) }
                children.append(existing)
            } else {
                let child = TreeNode(row: row)
                nodes[row.key] = child
                children.append(child)
            }
        }
        if complete {
            for old in node.children where !seen.contains(old.key) {
                forget(old)
            }
            let ids = Set(children.map(\.id))
            node.pinnedChildren = node.pinnedChildren.filter(ids.contains)
        }
        node.children = children
    }

    /// Drops `node` and everything loaded under it from the index.
    private func forget(_ node: TreeNode) {
        loads[node.key]?.cancel()
        loads[node.key] = nil
        nodes[node.key] = nil
        for child in node.children { forget(child) }
    }

    // MARK: Refreshing

    /// Re-reads `node` and its children from the server. Below it, branches
    /// that are expanded are re-read too (in parallel); collapsed branches
    /// that had been loaded are dropped and re-read when next expanded.
    /// Expansion and selection survive wherever the entries still exist.
    func refresh(_ node: TreeNode) async {
        if !node.dn.isEmpty {
            do {
                guard let entry = try await fetchEntry(target, dn: node.dn,
                                                       attributes: TreeRow.treeAttributes) else {
                    entryRemoved(node.dn)
                    return
                }
                node.update(from: entry)
            } catch {
                node.childrenState = .failed("\(error)")
                return
            }
        }
        await refreshChildren(of: node)
    }

    private func refreshChildren(of node: TreeNode) async {
        switch node.childrenState {
        case .notLoaded:
            guard node.isExpanded else { return }
            await loadChildren(of: node).value
        case .loading:
            // A first read is already under way and will be current.
            await loads[node.key]?.value
        case .failed:
            guard node.isExpanded else {
                drop(childrenOf: node)
                return
            }
            await loadChildren(of: node).value
        case .loaded:
            await loadChildren(of: node).value
        }
        guard node.childrenState == .loaded else { return }

        await withTaskGroup(of: Void.self) { group in
            for child in node.children {
                if child.isExpanded {
                    group.addTask { await self.refreshChildren(of: child) }
                } else if child.childrenState != .notLoaded {
                    drop(childrenOf: child)
                }
            }
        }
    }

    /// Forgets a collapsed node's cached children so the next expand
    /// re-reads them.
    private func drop(childrenOf node: TreeNode) {
        cancelLoad(of: node)
        for child in node.children { forget(child) }
        node.children = []
        node.childrenState = .notLoaded
        node.displayLimit = TreeNode.displayStep
        node.pinnedChildren = []
    }

    func refreshAll() async {
        guard let root else {
            await loadRoot()
            return
        }
        await refresh(root)
    }

    // MARK: Revealing

    enum RevealError: LocalizedError {
        case outsideBase(String)
        case notFound(String)
        case failed(String, String)

        var errorDescription: String? {
            switch self {
            case let .outsideBase(base): return "That DN isn't under this connection's base DN (\(base))."
            case .notFound: return "No entry with that DN in this directory."
            case let .failed(dn, reason): return "Couldn't load \(dn): \(reason)"
            }
        }
    }

    /// Expands the tree down to `dn`, reading each ancestor's children on
    /// the way as needed, and returns the DN as the server spells it.
    @discardableResult
    func reveal(_ dn: String) async throws -> String {
        guard let root else { throw RevealError.notFound(dn) }
        if DN.same(dn, root.dn) { return root.dn }

        // The steps from the root down to `dn`. With an empty base DN the
        // root's children are whole naming contexts, so the path starts at
        // whichever of those contains `dn`.
        var steps: [String]
        if baseDN.isEmpty {
            try await waitForChildren(of: root)
            guard let context = root.children.first(where: { DN.isWithin(dn, $0.dn) }),
                  let path = DN.path(to: dn, from: context.dn) else {
                throw RevealError.notFound(dn)
            }
            steps = [context.dn] + path.dropFirst() + [dn]
            if DN.same(dn, context.dn) { steps = [context.dn] }
        } else {
            guard let path = DN.path(to: dn, from: baseDN) else {
                throw RevealError.outsideBase(baseDN)
            }
            steps = Array(path.dropFirst()) + [dn]
        }

        var current = root
        for step in steps {
            current.isExpanded = true
            try await waitForChildren(of: current)
            var next = nodes[DN.normalize(step)].flatMap { candidate in
                current.children.contains { $0 === candidate } ? candidate : nil
            }
            if next == nil {
                // Not among the children read earlier — it may have been
                // added since. Ask the server before calling it missing.
                guard let entry = try await fetchEntry(target, dn: step, attributes: TreeRow.treeAttributes) else {
                    throw RevealError.notFound(dn)
                }
                next = insert(entry, under: current)
            }
            guard let next, let index = current.children.firstIndex(where: { $0 === next }) else {
                throw RevealError.notFound(dn)
            }
            if index >= current.displayLimit { current.pinnedChildren.insert(next.id) }
            current = next
        }
        return current.dn
    }

    /// Waits until `node`'s children have been read, starting the read if
    /// needed. A load can be replaced while we wait (collapsed and expanded
    /// again elsewhere), so this waits until one actually finishes.
    private func waitForChildren(of node: TreeNode) async throws {
        for _ in 0..<3 where node.childrenState != .loaded {
            if case .failed = node.childrenState { break }
            if node.childrenState != .loading || loads[node.key] == nil { loadChildren(of: node) }
            await loads[node.key]?.value
            try Task.checkCancellation()
        }
        if case let .failed(reason) = node.childrenState {
            throw RevealError.failed(node.dn, reason)
        }
    }

    /// Slots `entry` into `parent`'s loaded children in sort order (or
    /// updates the node if it's already there).
    @discardableResult
    private func insert(_ entry: LdapEntry, under parent: TreeNode) -> TreeNode {
        let row = TreeRow(entry)
        if let existing = nodes[row.key], parent.children.contains(where: { $0 === existing }) {
            existing.update(from: row)
            return existing
        }
        let child = nodes[row.key] ?? TreeNode(row: row)
        nodes[row.key] = child
        var children = parent.children
        let index = children.firstIndex { $0.sortKey > child.sortKey } ?? children.endIndex
        children.insert(child, at: index)
        parent.children = children
        if index >= parent.displayLimit { parent.pinnedChildren.insert(child.id) }
        return child
    }

    /// Stops every read in flight — the window showing this tree closed.
    func cancelAll() {
        for task in loads.values { task.cancel() }
        loads = [:]
    }

    // MARK: Keeping up with writes

    /// A new entry exists at `dn`. If its parent's children are showing,
    /// it's read and slotted in; otherwise the parent just gains an arrow.
    func entryAdded(_ dn: String) async {
        guard let parentDN = DN.parent(of: dn), let parent = node(parentDN) else { return }
        parent.noteHasChildren()
        guard parent.childrenState == .loaded,
              let entry = try? await fetchEntry(target, dn: dn, attributes: TreeRow.treeAttributes)
        else { return }
        insert(entry, under: parent)
    }

    /// `dn` (and everything under it) no longer exists.
    func entryRemoved(_ dn: String) {
        guard let node = node(dn) else { return }
        forget(node)
        if let parentDN = DN.parent(of: node.dn), let parent = self.node(parentDN) {
            parent.children.removeAll { $0 === node }
            parent.pinnedChildren.remove(node.id)
        }
    }

    /// `dn`'s attributes changed — its icon or arrow might have too.
    func entryModified(_ dn: String) async {
        guard let node = node(dn),
              let entry = try? await fetchEntry(target, dn: dn, attributes: TreeRow.treeAttributes)
        else { return }
        node.update(from: entry)
    }

    /// A branch moved or was renamed: drop the old node, show the new one.
    func entryMoved(from oldDN: String, to newDN: String) async {
        entryRemoved(oldDN)
        await entryAdded(newDN)
    }

    /// Something changed under `dn` in ways not worth tracking one by one
    /// (an LDIF import, a partly finished bulk operation).
    func branchChanged(_ dn: String) async {
        var ancestor: String? = dn
        while let current = ancestor, node(current) == nil {
            ancestor = DN.parent(of: current)
        }
        if let current = ancestor, let node = node(current) {
            await refresh(node)
        }
    }
}

extension SavedConnection {
    /// This connection as the core's pool knows it, with its password
    /// from the Keychain.
    var ldapTarget: LdapTarget {
        LdapTarget(host: host, port: UInt16(clamping: port), useSsl: useSSL,
                   startTLS: useStartTLS, pinnedCertSHA256: trustedCertSHA256,
                   options: ldapOptions, bindDn: bindDN,
                   password: KeychainService.readPassword(for: id) ?? "")
    }

    /// "host:port" — matches `LdapTarget.endpoint` and the Operation Log.
    var endpoint: String { "\(host):\(UInt16(clamping: port))" }
}
