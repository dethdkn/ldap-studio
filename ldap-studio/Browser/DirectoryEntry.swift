//
//  DirectoryEntry.swift
//  ldap-studio
//

import AppKit
import Foundation

/// One entry with its full attributes, as the detail view and the sheets
/// that act on an entry see it. The tree itself is `DirectoryTree`, which
/// only holds what drawing a row needs.
struct DirectoryEntry: Identifiable, Hashable {
    var name: String
    /// The full distinguished name, e.g. "cn=Alice Johnson,ou=People,dc=corp,dc=example,dc=com" — `name` is just the first component of this.
    var dn: String
    var icon: String
    var attributes: [Attribute]

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
    /// Server-maintained (createTimestamp, entryUUID, …) — shown only when
    /// the operational-attributes toggle is on, and never editable.
    var isOperational: Bool = false

    /// Non-nil only when this is a binary attribute whose bytes actually
    /// decode as an image (e.g. jpegPhoto) — other binary data (certificates
    /// and the like) simply won't produce an NSImage here.
    var decodedImage: NSImage? {
        guard isBinary, let data = Data(base64Encoded: value) else { return nil }
        return NSImage(data: data)
    }
}

extension DirectoryEntry {
    /// This entry's `objectClass` values.
    var objectClassNames: [String] {
        attributes
            .filter { $0.name.caseInsensitiveCompare("objectClass") == .orderedSame }
            .map(\.value)
    }
}

extension DirectoryEntry {
    /// Builds the UI model from one entry the C core fetched over LDAP.
    /// `hasChildren` only matters for picking an icon when the object
    /// classes don't decide it.
    init(ldapEntry entry: LdapEntry, hasChildren: Bool = false) {
        self.init(
            name: DN.rdn(of: entry.dn),
            dn: entry.dn,
            icon: DirectoryEntry.icon(forObjectClasses: entry.values("objectClass"),
                                      univentionType: entry.values("univentionObjectType").first,
                                      hasChildren: hasChildren),
            attributes: entry.attributes.map { Attribute(name: $0.name, value: $0.value, isBinary: $0.isBinary) }
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
    nonisolated static func icon(forObjectClasses classes: [String],
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

    nonisolated private static func objectClassIcon(_ classes: [String], hasChildren: Bool) -> String {
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
    static let mockEntry = DirectoryEntry(
        name: "cn=Alice Johnson",
        dn: "cn=Alice Johnson,ou=People,dc=corp,dc=example,dc=com",
        icon: "person.fill",
        attributes: [
            Attribute(name: "objectClass", value: "inetOrgPerson"),
            Attribute(name: "cn", value: "Alice Johnson"),
            Attribute(name: "sn", value: "Johnson"),
            Attribute(name: "uid", value: "ajohnson"),
            Attribute(name: "mail", value: "alice.johnson@corp.example.com"),
        ]
    )
}
