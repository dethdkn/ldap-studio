//
//  DirectoryEntry.swift
//  ldap-studio
//

import AppKit
import Foundation

struct DirectoryEntry: Identifiable, Hashable {
    var name: String
    /// The full distinguished name, e.g. "cn=Alice Johnson,ou=People,dc=corp,dc=example,dc=com" — `name` is just the first component of this.
    var dn: String
    var icon: String
    var attributes: [Attribute]
    var children: [DirectoryEntry]?

    /// `dn` is already unique within the directory, and using it as the
    /// identity (rather than a random UUID) means selection survives a
    /// reload after a write — the same entry gets the same id again as long
    /// as it hasn't moved.
    var id: String { dn }
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
    /// This entry plus every descendant currently loaded — what a
    /// recursive delete would actually remove.
    var subtreeCount: Int {
        1 + (children ?? []).reduce(0) { $0 + $1.subtreeCount }
    }

    /// This entry's `objectClass` values.
    var objectClassNames: [String] {
        attributes
            .filter { $0.name.caseInsensitiveCompare("objectClass") == .orderedSame }
            .map(\.value)
    }

    func find(id: DirectoryEntry.ID) -> DirectoryEntry? {
        if self.id == id { return self }
        for child in children ?? [] {
            if let match = child.find(id: id) { return match }
        }
        return nil
    }

    /// Recurses into `children` to mutate the entry with `id` in place —
    /// this is what lets edits made in the detail view (a `Binding` built
    /// from this method) flow back up into the tree `BrowserView` owns.
    mutating func update(id targetID: DirectoryEntry.ID, transform: (inout DirectoryEntry) -> Void) {
        if id == targetID {
            transform(&self)
            return
        }
        guard children != nil else { return }
        for index in children!.indices {
            children![index].update(id: targetID, transform: transform)
        }
    }

    /// Returns a copy of the tree with `excludedID` and everything under it
    /// removed — used by the move/copy destination picker so an entry can't
    /// be relocated into itself or one of its own descendants.
    func pruned(removing excludedID: DirectoryEntry.ID) -> DirectoryEntry? {
        guard id != excludedID else { return nil }
        var copy = self
        copy.children = children?.compactMap { $0.pruned(removing: excludedID) }
        return copy
    }

    /// Returns a copy of the tree containing only entries whose dn matches
    /// `query`, plus whatever ancestors are needed to reach them — an
    /// ancestor that doesn't itself match keeps only its matching
    /// descendants (non-matching siblings are pruned), but an entry that
    /// does match keeps its whole subtree as-is, so browsing continues
    /// normally past a hit. `nil` (or an empty query) means "no filtering."
    func filtered(matching query: String) -> DirectoryEntry? {
        guard !query.isEmpty else { return self }
        if dn.localizedCaseInsensitiveContains(query) {
            return self
        }
        let matchingChildren = children?.compactMap { $0.filtered(matching: query) } ?? []
        guard !matchingChildren.isEmpty else { return nil }
        var copy = self
        copy.children = matchingChildren
        return copy
    }
}

extension DirectoryEntry {
    /// Builds the UI model from the raw data the C core fetched over LDAP.
    /// The core returns the whole subtree in one shot, so this recurses
    /// through `entry.children` all the way down, not just one level.
    init(ldapEntry entry: LdapEntry) {
        let objectClasses = entry.attributes
            .filter { $0.name == "objectClass" }
            .map(\.value)

        let univentionType = entry.attributes
            .first { $0.name == "univentionObjectType" }?.value

        self.init(
            name: entry.name,
            dn: entry.dn,
            icon: DirectoryEntry.icon(forObjectClasses: objectClasses,
                                      univentionType: univentionType,
                                      hasChildren: entry.hasChildren),
            attributes: entry.attributes.map { Attribute(name: $0.name, value: $0.value, isBinary: $0.isBinary) },
            children: entry.children.isEmpty ? nil : entry.children.map { DirectoryEntry(ldapEntry: $0) }
        )
    }

    /// Picks an SF Symbol for a tree row.
    ///
    /// Univention (UCS) directories carry the real entry type in
    /// `univentionObjectType` as `module/type` — that's checked first
    /// because the objectClasses on a UCS entry (`univentionObject`, a
    /// bare `cn` container, …) often don't say much. Otherwise it goes by
    /// objectClass: an entry carries several (one structural plus any
    /// number of auxiliaries) and we don't have the schema here to tell
    /// which is structural, so the checks are ordered so the class that
    /// best describes the entry wins. Anything unrecognised falls back to
    /// a folder or a document rather than a question mark.
    static func icon(forObjectClasses classes: [String],
                     univentionType: String? = nil,
                     hasChildren: Bool) -> String {
        if let ut = univentionType?.lowercased() {
            let module = ut.split(separator: "/").first.map(String.init) ?? ut
            switch module {
            case "users": return "person.fill"
            case "groups": return "person.2.fill"
            case "container": return "folder.fill"
            case "computers":
                return (ut.contains("domaincontroller") || ut.contains("memberserver"))
                    ? "server.rack" : "desktopcomputer"
            case "dns", "dhcp", "networks": return "network"
            case "shares": return ut.contains("printer") ? "printer.fill" : "externaldrive.fill"
            case "printers": return "printer.fill"
            case "mail", "oxmail", "oxresources": return "envelope.fill"
            case "policies": return "slider.horizontal.3"
            case "settings", "appcenter", "uvmm": return "gearshape.fill"
            case "portals": return "square.grid.2x2.fill"
            case "kerberos", "saml": return "key.fill"
            default: break  // fall through to the objectClass checks
            }
        }
        return objectClassIcon(classes, hasChildren: hasChildren)
    }

    private static func objectClassIcon(_ classes: [String], hasChildren: Bool) -> String {
        // Values normally arrive one per objectClass attribute; also
        // tolerate a single comma/space-joined value (mock data, pasted
        // input).
        let names = Set(
            classes
                .flatMap { $0.lowercased().split { $0 == "," || $0 == " " } }
                .map(String.init)
        )
        func has(_ candidates: String...) -> Bool { !names.isDisjoint(with: candidates) }

        if has("alias") { return "arrowshape.turn.up.right.fill" }
        if has("referral") { return "arrow.up.forward.square.fill" }

        // People
        if has("inetorgperson", "organizationalperson", "person", "residentialperson",
               "posixaccount", "shadowaccount", "account", "inetuser", "user",
               "pkiuser", "sambasamaccount", "mailrecipient") {
            return "person.fill"
        }

        // Groups
        if has("groupofnames", "groupofuniquenames", "groupofmembers", "groupofurls",
               "posixgroup", "sambagroupmapping", "nisnetgroup", "group") {
            return "person.2.fill"
        }

        // Machines & network
        if has("device", "ieee802device", "bootabledevice", "computer") {
            return "desktopcomputer"
        }
        if has("iphost", "ipnetwork", "ipservice", "ipprotocol",
               "dnszone", "dnsnode", "oncrpc", "nisobject") {
            return "network"
        }
        if has("printerabstract", "printerservice", "slpservice") { return "printer.fill" }

        // Directory infrastructure
        if has("applicationprocess") { return "gearshape.fill" }
        if has("applicationentity", "dsa") { return "server.rack" }
        if has("simplesecurityobject") { return "key.fill" }
        if has("organizationalrole") { return "briefcase.fill" }

        // Containers
        if has("organizationalunit", "container", "nscontainer",
               "niscontainer", "posixcontainer") {
            return "folder.fill"
        }

        // Naming contexts / roots
        if has("domain", "dcobject", "domaincomponent", "dnsdomain") { return "globe" }
        if has("organization") { return "building.2.fill" }
        if has("country") { return "flag.fill" }
        if has("locality") { return "mappin.and.ellipse" }

        // Unknown — at least distinguish a branch from a leaf.
        return hasChildren ? "folder" : "doc.text"
    }
}

extension DirectoryEntry {
    static let mockRoot = DirectoryEntry(
        name: "dc=corp,dc=example,dc=com",
        dn: "dc=corp,dc=example,dc=com",
        icon: "globe",
        attributes: [
            Attribute(name: "objectClass", value: "dcObject, domain"),
            Attribute(name: "dc", value: "corp"),
        ],
        children: [
            DirectoryEntry(
                name: "ou=People",
                dn: "ou=People,dc=corp,dc=example,dc=com",
                icon: "folder.fill",
                attributes: [
                    Attribute(name: "objectClass", value: "organizationalUnit"),
                    Attribute(name: "ou", value: "People"),
                ],
                children: [
                    DirectoryEntry(
                        name: "cn=Alice Johnson",
                        dn: "cn=Alice Johnson,ou=People,dc=corp,dc=example,dc=com",
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
                        dn: "cn=Bob Smith,ou=People,dc=corp,dc=example,dc=com",
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
                dn: "ou=Groups,dc=corp,dc=example,dc=com",
                icon: "folder.fill",
                attributes: [
                    Attribute(name: "objectClass", value: "organizationalUnit"),
                    Attribute(name: "ou", value: "Groups"),
                ],
                children: [
                    DirectoryEntry(
                        name: "cn=Admins",
                        dn: "cn=Admins,ou=Groups,dc=corp,dc=example,dc=com",
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
                dn: "ou=Computers,dc=corp,dc=example,dc=com",
                icon: "folder.fill",
                attributes: [
                    Attribute(name: "objectClass", value: "organizationalUnit"),
                    Attribute(name: "ou", value: "Computers"),
                ],
                children: [
                    DirectoryEntry(
                        name: "cn=WORKSTATION01",
                        dn: "cn=WORKSTATION01,ou=Computers,dc=corp,dc=example,dc=com",
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
