//
//  EntryActions.swift
//  ldap-studio
//

import Foundation

/// The DN-level write operations shared by the tree's right-click menu, the
/// entry detail toolbar and Advanced Search, so all of them call the exact
/// same LDAP logic instead of drifting apart.
///
/// Anything that acts on a branch (delete, copy, export) reads the branch
/// from the server with paged searches — the tree only ever has part of the
/// directory loaded, so it can't be the source of truth for what's there.
struct EntryActions {
    let connection: SavedConnection
    /// When known, used to leave out server-maintained attributes (marked
    /// NO-USER-MODIFICATION) when copying entries.
    var schema: LdapSchema? = nil

    private var target: LdapTarget { connection.ldapTarget }
    private var readOnly: Bool { connection.isReadOnly }

    /// Moves `dn` under `newSuperiorDN`, keeping its current RDN. The server
    /// moves everything under it along with it. Returns the new dn.
    func move(_ dn: String, to newSuperiorDN: String) async throws -> String {
        let rdn = DN.rdn(of: dn)
        try await renameEntry(target, readOnly: readOnly, dn: dn, newRDN: rdn,
                              deleteOldRDN: true, newSuperior: newSuperiorDN)
        return "\(rdn),\(newSuperiorDN)"
    }

    /// Recreates `dn` and everything under it, as read from the server right
    /// now, beneath `newSuperiorDN`. Entries are added parent-first; a
    /// cancelled copy leaves what it already added. Returns the copy's dn.
    func copy(_ dn: String, to newSuperiorDN: String,
              progress: (Int) -> Void = { _ in }) async throws -> String {
        guard !readOnly else { throw ConnectionError.ReadOnly }
        let newRoot = "\(DN.rdn(of: dn)),\(newSuperiorDN)"
        var order = ParentFirstOrder(root: dn)
        var copied = 0

        func add(_ entry: LdapEntry) async throws {
            try Task.checkCancellation()
            try await addEntry(target, readOnly: readOnly,
                               dn: DN.rebase(entry.dn, from: dn, to: newRoot),
                               attributes: copyableAttributes(of: entry))
            copied += 1
            progress(copied)
        }

        try await pagedSearch(target, LdapSearchRequest(baseDn: dn, scope: .subtree)) { page, _ in
            for entry in page {
                for ready in order.add(entry) { try await add(ready) }
            }
            return true
        }.requireComplete()
        let orphans = order.leftovers()
        if !orphans.isEmpty {
            throw ConnectionError.ModifyFailed(reason: "\(orphans.count) entries weren't copied because their parent entry couldn't be read.")
        }
        return newRoot
    }

    private func copyableAttributes(of entry: LdapEntry) -> [LdapAttribute] {
        guard let schema else { return entry.attributes }
        let serverManaged = Set(
            schema.attributeTypes
                .filter(\.noUserModification)
                .flatMap(\.names)
                .map { $0.lowercased() }
        )
        return entry.attributes.filter { !serverManaged.contains($0.name.lowercased()) }
    }

    /// Every DN in the branch at `dn`, the entry itself included, read with
    /// a paged search that asks for no attributes.
    func branchDNs(_ dn: String, progress: (Int) -> Void = { _ in }) async throws -> [String] {
        var dns: [String] = []
        try await pagedSearch(target, LdapSearchRequest(baseDn: dn, scope: .subtree,
                                                       attributes: ["1.1"])) { page, status in
            dns.append(contentsOf: page.map(\.dn))
            progress(status.entries)
            return true
        }.requireComplete()
        return dns
    }

    /// Deletes every entry in `dns` (a whole branch, as `branchDNs`
    /// returned it) deepest first, a few at a time. Cancelling stops before
    /// the next entry, which always leaves a consistent — just smaller —
    /// branch behind. If the branch gained entries since it was read, the
    /// new ones are read and deleted too.
    func deleteBranch(_ dns: [String], progress: (Int) -> Void = { _ in }) async throws {
        guard !readOnly else { throw ConnectionError.ReadOnly }
        var deleted = 0
        try await deleteDeepestFirst(dns, deleted: &deleted, rereadsLeft: 3, progress: progress)
    }

    private func deleteDeepestFirst(_ dns: [String], deleted: inout Int, rereadsLeft: Int,
                                    progress: (Int) -> Void) async throws {
        let byDepth = Dictionary(grouping: dns, by: DN.depth)
        let target = target
        let readOnly = readOnly
        for depth in byDepth.keys.sorted(by: >) {
            // Entries at the same depth never contain one another, so a few
            // can go at once.
            for batch in byDepth[depth]!.chunked(into: 4) {
                try Task.checkCancellation()
                let results = await withTaskGroup(of: (String, Error?).self) { group in
                    for dn in batch {
                        group.addTask {
                            do {
                                try await deleteEntry(target, readOnly: readOnly, dn: dn)
                                return (dn, nil)
                            } catch ConnectionError.ModifyFailed(let reason) where reason == noSuchObjectReason {
                                // Already gone (deleted meanwhile, or by a
                                // retry after a dropped connection) — fine.
                                return (dn, nil)
                            } catch {
                                return (dn, error)
                            }
                        }
                    }
                    return await group.reduce(into: []) { $0.append($1) }
                }
                for (dn, error) in results {
                    guard let error else {
                        deleted += 1
                        continue
                    }
                    if case ConnectionError.ModifyFailed(let reason) = error,
                       reason == notAllowedOnNonLeafReason, rereadsLeft > 0 {
                        // Something was added under it since the branch was
                        // read: read what's there now and delete that too.
                        try await deleteDeepestFirst(try await branchDNs(dn), deleted: &deleted,
                                                     rereadsLeft: rereadsLeft - 1, progress: progress)
                    } else {
                        throw error
                    }
                }
                progress(deleted)
            }
        }
    }

    /// Creates a brand-new entry at `dn` with `attributes`. LDAP requires
    /// the RDN's attribute=value pair (e.g. a dn starting "cn=John Doe"
    /// implies a "cn: John Doe" attribute) to also literally exist among
    /// the entry's attributes — this fills that in automatically if it's
    /// missing, so forgetting it in the form turns into a working entry
    /// instead of a schema error from the server.
    func createEntry(dn: String, attributes: [(name: String, value: String)]) async throws {
        var ldapAttributes = attributes.map { LdapAttribute(name: $0.name, value: $0.value, isBinary: false) }

        if let rdn = Self.parseRDN(dn),
           !ldapAttributes.contains(where: { $0.name.caseInsensitiveCompare(rdn.name) == .orderedSame && $0.value == rdn.value }) {
            ldapAttributes.append(LdapAttribute(name: rdn.name, value: rdn.value, isBinary: false))
        }

        try await addEntry(target, readOnly: readOnly, dn: dn, attributes: ldapAttributes)
    }

    private static func parseRDN(_ dn: String) -> (name: String, value: String)? {
        let firstComponent = DN.rdn(of: dn)
        guard let equalsIndex = firstComponent.firstIndex(of: "=") else { return nil }
        let name = firstComponent[firstComponent.startIndex..<equalsIndex].trimmingCharacters(in: .whitespaces)
        let value = firstComponent[firstComponent.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !value.isEmpty, !value.contains("\\") else { return nil }
        return (name, value)
    }

    /// Hashes `plaintext` client-side, using `scheme`, before sending it —
    /// unlike a generic attribute edit, this is a hard guarantee that the
    /// stored value is always a hash, independent of whether the server
    /// itself would have auto-hashed a plain write. Replaces only
    /// `oldValue`, since userPassword can be multi-valued (e.g. during a
    /// hash migration, or multiple auth mechanisms) — the same targeted
    /// delete-old/add-new normal attribute edits use, not a wipe-everything
    /// Replace.
    func setPassword(_ plaintext: String, scheme: PasswordScheme, replacing oldValue: String, forDN dn: String, attribute: String = "userPassword") async throws {
        try await modifyAttributeValue(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            readOnly: connection.isReadOnly,
            startTLS: connection.useStartTLS,
            pinnedCertSHA256: connection.trustedCertSHA256,
            options: connection.ldapOptions,
            bindDn: connection.bindDN,
            password: target.password,
            dn: dn,
            attribute: attribute,
            oldValue: oldValue,
            newValue: try hashPassword(plaintext: plaintext, scheme: scheme),
            isBinary: false
        )
    }

    /// Sets `userPassword` on `dn` when there's no specific existing value
    /// to target — invoked from the tree's context menu rather than a
    /// selected attribute row. Hashes `plaintext` client-side (same
    /// guarantee as the row-level variant) and Replaces the attribute,
    /// adding it if the entry doesn't have one yet.
    func setPassword(_ plaintext: String, scheme: PasswordScheme, forDN dn: String) async throws {
        try await setAttributeValue(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            readOnly: connection.isReadOnly,
            startTLS: connection.useStartTLS,
            pinnedCertSHA256: connection.trustedCertSHA256,
            options: connection.ldapOptions,
            bindDn: connection.bindDN,
            password: target.password,
            dn: dn,
            attribute: "userPassword",
            value: try hashPassword(plaintext: plaintext, scheme: scheme),
            isBinary: false
        )
    }

    /// Renames an entry's RDN in place (the parent DN is unchanged). The
    /// old RDN attribute value is dropped. Returns the entry's new dn.
    func rename(_ dn: String, toRDN newRDN: String) async throws -> String {
        try await renameEntry(target, readOnly: readOnly, dn: dn, newRDN: newRDN,
                              deleteOldRDN: true, newSuperior: nil)
        return DN.parent(of: dn).map { "\(newRDN),\($0)" } ?? newRDN
    }

    /// Resizes the image at `fileURL` to a 300x300 JPEG (center-cropped, so
    /// it's never distorted) and makes it the entry's `attribute` value —
    /// a plain Replace, so it works regardless of whatever (possibly
    /// bogus) value was there before.
    func setPhoto(fileURL: URL, forDN dn: String, attribute: String) async throws {
        let base64 = try resizePhotoToBase64(path: fileURL.path)
        try await setAttributeValue(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            readOnly: connection.isReadOnly,
            startTLS: connection.useStartTLS,
            pinnedCertSHA256: connection.trustedCertSHA256,
            options: connection.ldapOptions,
            bindDn: connection.bindDN,
            password: target.password,
            dn: dn,
            attribute: attribute,
            value: base64,
            isBinary: true
        )
    }

    /// Adds every parsed entry to the server at the dn it specifies —
    /// ordered shallowest-first in case a child appears before its parent in
    /// the file, since a parent must exist before anything can be added
    /// under it.
    func importLDIF(_ entries: [LDIFEntry], progress: (Int) -> Void = { _ in }) async throws {
        let ordered = entries.sorted { DN.depth($0.dn) < DN.depth($1.dn) }
        for (index, entry) in ordered.enumerated() {
            try Task.checkCancellation()
            try await addEntry(target, readOnly: readOnly, dn: entry.dn,
                               attributes: entry.attributes.map { LdapAttribute(name: $0.name, value: $0.value, isBinary: $0.isBinary) })
            progress(index + 1)
        }
    }

    // MARK: - LDIF

    /// Streams LDIF for `dns` to `sink`, reading from the server: each entry
    /// alone, or with `subtree`, its whole branch in parent-first order (so
    /// the file imports straight into an empty directory).
    func writeLDIF(_ dns: [String], subtree: Bool, progress: (Int) -> Void = { _ in },
                   to sink: (String) throws -> Void) async throws {
        var written = 0
        func emit(_ entry: LdapEntry) throws {
            try sink(Self.ldifText(for: entry) + "\n")
            written += 1
            progress(written)
        }
        for dn in dns {
            try Task.checkCancellation()
            guard subtree else {
                guard let entry = try await fetchEntry(target, dn: dn) else { continue }
                try emit(entry)
                continue
            }
            var order = ParentFirstOrder(root: dn)
            try await pagedSearch(target, LdapSearchRequest(baseDn: dn, scope: .subtree)) { page, _ in
                for entry in page {
                    for ready in order.add(entry) { try emit(ready) }
                }
                return true
            }.requireComplete()
            for orphan in order.leftovers() { try emit(orphan) }
        }
    }

    /// Streams LDIF for the entries `request` finds whose DN is in `only`
    /// (all of them when nil) — exporting Advanced Search results re-runs
    /// the search with every attribute rather than reading each entry.
    func writeLDIF(of request: LdapSearchRequest, only: Set<String>?, progress: (Int) -> Void = { _ in },
                   to sink: (String) throws -> Void) async throws {
        var request = request
        request.attributes = nil
        var written = 0
        try await pagedSearch(target, request) { page, _ in
            for entry in page where only?.contains(entry.dn) ?? true {
                try sink(Self.ldifText(for: entry) + "\n")
                written += 1
            }
            progress(written)
            return true
        }.requireComplete()
    }

    static func ldifText(for entry: LdapEntry) -> String {
        var lines = [ldifLine(name: "dn", value: entry.dn, isBinary: false)]
        for attribute in entry.attributes {
            lines.append(ldifLine(name: attribute.name, value: attribute.value, isBinary: attribute.isBinary))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func safeFilename(_ name: String) -> String {
        name
            .replacingOccurrences(of: "=", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    /// `attribute.value` is already base64 for genuinely binary attributes
    /// (jpegPhoto and the like) — this handles the other case LDIF also
    /// requires base64 for: plain text that isn't "safe" per RFC 2849, most
    /// commonly any character outside ASCII (e.g. "ç"), which some LDIF
    /// readers mishandle if written as a raw `attr: value` line.
    private static func ldifLine(name: String, value: String, isBinary: Bool) -> String {
        if isBinary || !isSafeLDIFString(value) {
            let base64 = isBinary ? value : Data(value.utf8).base64EncodedString()
            return "\(name):: \(base64)"
        }
        return "\(name): \(value)"
    }

    private static func isSafeLDIFString(_ value: String) -> Bool {
        guard let firstByte = value.utf8.first else { return true }

        // RFC 2849 SAFE-INIT-CHAR excludes NUL, LF, CR, space, colon,
        // less-than — and, being byte-range-based, anything non-ASCII.
        let unsafeFirstBytes: Set<UInt8> = [0x00, 0x0A, 0x0D, 0x20, 0x3A, 0x3C]
        if firstByte >= 0x80 || unsafeFirstBytes.contains(firstByte) {
            return false
        }

        for byte in value.utf8 where byte == 0x00 || byte == 0x0A || byte == 0x0D || byte >= 0x80 {
            return false
        }

        return !value.hasSuffix(" ")
    }
}

/// libldap's text for result code 66 — deleting an entry that still has
/// children.
nonisolated private let notAllowedOnNonLeafReason = String(cString: ls_ldap_error_text(66))

/// Puts a branch's entries, which a subtree search returns in whatever
/// order the server likes, into parent-first order: an entry is released
/// once its parent has been, and held until then.
struct ParentFirstOrder {
    private let root: String
    private var released = Set<String>()
    private var waiting: [String: [LdapEntry]] = [:]

    init(root: String) {
        self.root = DN.normalize(root)
    }

    /// The entries that can go now — `entry`, if its parent already went,
    /// plus anything that was waiting on it.
    mutating func add(_ entry: LdapEntry) -> [LdapEntry] {
        let key = DN.normalize(entry.dn)
        guard key == root || released.contains(DN.parent(of: key) ?? "") else {
            waiting[DN.parent(of: key) ?? "", default: []].append(entry)
            return []
        }
        var ready: [LdapEntry] = []
        var queue = [entry]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            let nextKey = DN.normalize(next.dn)
            released.insert(nextKey)
            ready.append(next)
            queue += waiting.removeValue(forKey: nextKey) ?? []
        }
        return ready
    }

    /// Entries whose parent never came (it couldn't be read), shallowest
    /// first.
    mutating func leftovers() -> [LdapEntry] {
        let rest = waiting.values.flatMap { $0 }
        waiting = [:]
        return rest.sorted { DN.depth($0.dn) < DN.depth($1.dn) }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
