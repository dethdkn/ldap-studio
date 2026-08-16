//
//  DirectoryEntry.swift
//  ldap-studio
//

import AppKit
import Foundation

struct DirectoryEntry: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var icon: String
    var attributes: [Attribute]
    var children: [DirectoryEntry]?
}

struct Attribute: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var value: String
    var isBinary: Bool = false

    /// Non-nil only when this is a binary attribute whose bytes actually
    /// decode as an image (e.g. jpegPhoto) — other binary data (certificates
    /// and the like) simply won't produce an NSImage here.
    var decodedImage: NSImage? {
        guard isBinary, let data = Data(base64Encoded: value) else { return nil }
        return NSImage(data: data)
    }
}

extension DirectoryEntry {
    func find(id: DirectoryEntry.ID) -> DirectoryEntry? {
        if self.id == id { return self }
        for child in children ?? [] {
            if let match = child.find(id: id) { return match }
        }
        return nil
    }
}

extension DirectoryEntry {
    /// Builds the UI model from the raw data Rust fetched over LDAP. Rust
    /// returns the whole subtree in one shot, so this recurses through
    /// `entry.children` all the way down, not just one level.
    init(ldapEntry entry: LdapEntry) {
        let objectClasses = entry.attributes
            .filter { $0.name == "objectClass" }
            .map(\.value)

        self.init(
            name: entry.name,
            icon: DirectoryEntry.icon(forObjectClasses: objectClasses),
            attributes: entry.attributes.map { Attribute(name: $0.name, value: $0.value, isBinary: $0.isBinary) },
            children: entry.children.isEmpty ? nil : entry.children.map { DirectoryEntry(ldapEntry: $0) }
        )
    }

    private static func icon(forObjectClasses classes: [String]) -> String {
        let lowercased = Set(classes.map { $0.lowercased() })
        if lowercased.contains("domain") || lowercased.contains("dcobject") {
            return "globe"
        }
        if lowercased.contains("organizationalunit") || lowercased.contains("container") {
            return "folder.fill"
        }
        if lowercased.contains("locality") {
            return "building.2.fill"
        }
        if lowercased.contains("groupofnames") || lowercased.contains("group") {
            return "person.2.fill"
        }
        if lowercased.contains("device") || lowercased.contains("computer") {
            return "desktopcomputer"
        }
        if lowercased.contains("inetorgperson") || lowercased.contains("person") {
            return "person.fill"
        }
        return "questionmark.folder"
    }
}

extension DirectoryEntry {
    static let mockRoot = DirectoryEntry(
        name: "dc=corp,dc=example,dc=com",
        icon: "globe",
        attributes: [
            Attribute(name: "objectClass", value: "dcObject, domain"),
            Attribute(name: "dc", value: "corp"),
        ],
        children: [
            DirectoryEntry(
                name: "ou=People",
                icon: "folder.fill",
                attributes: [
                    Attribute(name: "objectClass", value: "organizationalUnit"),
                    Attribute(name: "ou", value: "People"),
                ],
                children: [
                    DirectoryEntry(
                        name: "cn=Alice Johnson",
                        icon: "person.fill",
                        attributes: [
                            Attribute(name: "objectClass", value: "inetOrgPerson"),
                            Attribute(name: "cn", value: "Alice Johnson"),
                            Attribute(name: "sn", value: "Johnson"),
                            Attribute(name: "uid", value: "ajohnson"),
                            Attribute(name: "mail", value: "alice.johnson@corp.example.com"),
                        ],
                        children: nil
                    ),
                    DirectoryEntry(
                        name: "cn=Bob Smith",
                        icon: "person.fill",
                        attributes: [
                            Attribute(name: "objectClass", value: "inetOrgPerson"),
                            Attribute(name: "cn", value: "Bob Smith"),
                            Attribute(name: "sn", value: "Smith"),
                            Attribute(name: "uid", value: "bsmith"),
                            Attribute(name: "mail", value: "bob.smith@corp.example.com"),
                        ],
                        children: nil
                    ),
                ]
            ),
            DirectoryEntry(
                name: "ou=Groups",
                icon: "folder.fill",
                attributes: [
                    Attribute(name: "objectClass", value: "organizationalUnit"),
                    Attribute(name: "ou", value: "Groups"),
                ],
                children: [
                    DirectoryEntry(
                        name: "cn=Admins",
                        icon: "person.2.fill",
                        attributes: [
                            Attribute(name: "objectClass", value: "groupOfNames"),
                            Attribute(name: "cn", value: "Admins"),
                            Attribute(name: "member", value: "cn=Alice Johnson,ou=People,dc=corp,dc=example,dc=com"),
                        ],
                        children: nil
                    ),
                ]
            ),
            DirectoryEntry(
                name: "ou=Computers",
                icon: "folder.fill",
                attributes: [
                    Attribute(name: "objectClass", value: "organizationalUnit"),
                    Attribute(name: "ou", value: "Computers"),
                ],
                children: [
                    DirectoryEntry(
                        name: "cn=WORKSTATION01",
                        icon: "desktopcomputer",
                        attributes: [
                            Attribute(name: "objectClass", value: "device"),
                            Attribute(name: "cn", value: "WORKSTATION01"),
                        ],
                        children: nil
                    ),
                ]
            ),
        ]
    )
}
