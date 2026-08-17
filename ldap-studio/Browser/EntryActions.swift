//
//  EntryActions.swift
//  ldap-studio
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// The DN-level write operations shared by the tree's right-click menu and
/// the entry detail toolbar, so both call the exact same LDAP logic instead
/// of drifting apart.
struct EntryActions {
    let connection: SavedConnection

    private var password: String {
        KeychainService.readPassword(for: connection.id) ?? ""
    }

    /// Moves `entry` under `newSuperiorDN`, keeping its current RDN. Returns
    /// the entry's new dn, for the caller to reselect after reloading.
    func move(_ entry: DirectoryEntry, to newSuperiorDN: String) async throws -> String {
        try await moveEntry(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            bindDn: connection.bindDN,
            password: password,
            dn: entry.dn,
            newSuperior: newSuperiorDN
        )
        return "\(entry.name),\(newSuperiorDN)"
    }

    /// Recreates `entry` (and, recursively, every descendant it already has
    /// loaded) under `newSuperiorDN`. Returns the copy's new root dn.
    func copy(_ entry: DirectoryEntry, to newSuperiorDN: String) async throws -> String {
        try await addRecursively(entry, under: newSuperiorDN)
        return "\(entry.name),\(newSuperiorDN)"
    }

    private func addRecursively(_ node: DirectoryEntry, under newSuperiorDN: String) async throws {
        let newDN = "\(node.name),\(newSuperiorDN)"
        try await addEntry(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            bindDn: connection.bindDN,
            password: password,
            dn: newDN,
            attributes: node.attributes.map { LdapAttribute(name: $0.name, value: $0.value, isBinary: $0.isBinary) }
        )
        for child in node.children ?? [] {
            try await addRecursively(child, under: newDN)
        }
    }

    /// Deletes `entry` and, recursively, everything under it — LDAP only
    /// allows deleting one leaf entry at a time, so descendants go first.
    func delete(_ entry: DirectoryEntry) async throws {
        for child in entry.children ?? [] {
            try await delete(child)
        }
        try await deleteEntry(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            bindDn: connection.bindDN,
            password: password,
            dn: entry.dn
        )
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

        try await addEntry(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            bindDn: connection.bindDN,
            password: password,
            dn: dn,
            attributes: ldapAttributes
        )
    }

    private static func parseRDN(_ dn: String) -> (name: String, value: String)? {
        guard let firstComponent = dn.split(separator: ",").first,
              let equalsIndex = firstComponent.firstIndex(of: "=") else { return nil }
        let name = firstComponent[firstComponent.startIndex..<equalsIndex].trimmingCharacters(in: .whitespaces)
        let value = firstComponent[firstComponent.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !value.isEmpty else { return nil }
        return (name, value)
    }

    /// Hashes `plaintext` client-side as {PBKDF2-SHA512} before sending it —
    /// unlike a generic attribute edit, this is a hard guarantee that the
    /// stored value is always a hash, independent of whether the server
    /// itself would have auto-hashed a plain write. Replaces only
    /// `oldValue`, since userPassword can be multi-valued (e.g. during a
    /// hash migration, or multiple auth mechanisms) — the same targeted
    /// delete-old/add-new normal attribute edits use, not a wipe-everything
    /// Replace.
    func setPassword(_ plaintext: String, replacing oldValue: String, forDN dn: String, attribute: String = "userPassword") async throws {
        try await modifyAttributeValue(
            host: connection.host,
            port: UInt16(clamping: connection.port),
            useSsl: connection.useSSL,
            bindDn: connection.bindDN,
            password: password,
            dn: dn,
            attribute: attribute,
            oldValue: oldValue,
            newValue: hashPasswordPbkdf2Sha512(plaintext: plaintext)
        )
    }

    /// Adds every parsed entry to the server at the dn it specifies —
    /// ordered shallowest-first in case a child appears before its parent in
    /// the file, since a parent must exist before anything can be added
    /// under it.
    func importLDIF(_ entries: [LDIFEntry]) async throws {
        let ordered = entries.sorted { lhs, rhs in
            lhs.dn.filter { $0 == "," }.count < rhs.dn.filter { $0 == "," }.count
        }
        for entry in ordered {
            try await addEntry(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                dn: entry.dn,
                attributes: entry.attributes.map { LdapAttribute(name: $0.name, value: $0.value, isBinary: $0.isBinary) }
            )
        }
    }

    func exportLDIF(_ entry: DirectoryEntry) {
        let ldif = Self.ldifText(for: entry)
        let suggestedName = entry.name
            .replacingOccurrences(of: "=", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        DispatchQueue.main.async {
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
                try? ldif.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func ldifText(for entry: DirectoryEntry) -> String {
        var lines = [ldifLine(name: "dn", value: entry.dn, isBinary: false)]
        for attribute in entry.attributes {
            lines.append(ldifLine(name: attribute.name, value: attribute.value, isBinary: attribute.isBinary))
        }
        return lines.joined(separator: "\n") + "\n"
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
