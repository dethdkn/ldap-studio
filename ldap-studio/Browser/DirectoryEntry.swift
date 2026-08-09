//
//  DirectoryEntry.swift
//  ldap-studio
//

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
