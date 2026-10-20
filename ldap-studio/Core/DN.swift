//
//  DN.swift
//  ldap-studio
//
//  Distinguished-name helpers (RFC 4514). DNs are passed around as the
//  strings the server returned; these split them without tripping over
//  escaped commas ("cn=Smith\, John,ou=People,…") and compare them the way
//  a user would expect (case and spacing don't matter).
//

import Foundation

nonisolated enum DN {
    /// The RDNs of `dn`, leaf first: "uid=a,ou=People,dc=x" gives
    /// ["uid=a", "ou=People", "dc=x"]. Escapes are kept as written.
    static func components(_ dn: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for ch in dn {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                current.append(ch)
                escaped = true
            } else if ch == "," {
                parts.append(trimmed(current))
                current = ""
            } else {
                current.append(ch)
            }
        }
        let last = trimmed(current)
        if !last.isEmpty || !parts.isEmpty { parts.append(last) }
        return parts
    }

    /// Drops spaces around an RDN, but not an escaped trailing space
    /// ("cn=foo\ " keeps its space).
    private static func trimmed(_ rdn: String) -> String {
        var s = Substring(rdn)
        while s.first == " " { s = s.dropFirst() }
        while s.last == " " {
            let beforeSpace = s.dropLast()
            let backslashes = beforeSpace.reversed().prefix { $0 == "\\" }.count
            if backslashes % 2 == 1 { break }
            s = beforeSpace
        }
        return String(s)
    }

    /// The leftmost RDN — what the tree shows for an entry.
    static func rdn(of dn: String) -> String {
        components(dn).first ?? dn
    }

    /// Everything after the leftmost RDN, or nil for a single-RDN DN.
    static func parent(of dn: String) -> String? {
        let parts = components(dn)
        guard parts.count > 1 else { return nil }
        return parts.dropFirst().joined(separator: ",")
    }

    static func depth(_ dn: String) -> Int {
        components(dn).count
    }

    /// A comparison key: attribute types and values lowercased, spaces
    /// around separators dropped. Two DNs that name the same entry the way
    /// people type them ("OU=People, DC=Corp" vs "ou=people,dc=corp") get
    /// the same key.
    static func normalize(_ dn: String) -> String {
        components(dn).map { rdn in
            splitUnescaped(rdn, on: "+").map { ava in
                guard let eq = ava.firstIndex(of: "=") else {
                    return ava.trimmingCharacters(in: .whitespaces).lowercased()
                }
                let type = ava[..<eq].trimmingCharacters(in: .whitespaces)
                let value = canonicalValue(String(ava[ava.index(after: eq)...]))
                return "\(type)=\(value)".lowercased()
            }.joined(separator: "+")
        }.joined(separator: ",")
    }

    /// Splits on `separator` where it isn't escaped.
    private static func splitUnescaped(_ s: String, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for ch in s {
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == separator {
                parts.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        parts.append(current)
        return parts
    }

    /// An attribute value with every escape written one way, so "\2C",
    /// "\2c" and "\," compare equal: escapes are decoded, then the
    /// characters that need it are escaped again with a backslash.
    private static func canonicalValue(_ raw: String) -> String {
        let value = trimmed(raw)
        var bytes: [UInt8] = []
        let utf8 = Array(value.utf8)
        var i = 0
        while i < utf8.count {
            if utf8[i] == UInt8(ascii: "\\"), i + 1 < utf8.count {
                if i + 2 < utf8.count,
                   let hex = UInt8(String(decoding: utf8[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                    bytes.append(hex)
                    i += 3
                } else {
                    bytes.append(utf8[i + 1])
                    i += 2
                }
            } else {
                bytes.append(utf8[i])
                i += 1
            }
        }
        var out = ""
        for scalar in String(decoding: bytes, as: UTF8.self).unicodeScalars {
            if ",+\"\\<>;=".unicodeScalars.contains(scalar) { out += "\\" }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    static func same(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    /// Whether `dn` is `ancestor` itself or anywhere beneath it.
    static func isWithin(_ dn: String, _ ancestor: String) -> Bool {
        let d = components(normalize(dn))
        let a = components(normalize(ancestor))
        guard d.count >= a.count else { return false }
        return Array(d.suffix(a.count)) == a
    }

    /// `isWithin` for two keys that already came from `normalize(_:)` — a
    /// plain suffix check, cheap enough to run over 100,000 DNs.
    static func keyIsWithin(_ key: String, _ ancestorKey: String) -> Bool {
        guard key.hasSuffix(ancestorKey) else { return false }
        if key.count == ancestorKey.count { return true }
        let rest = key.dropLast(ancestorKey.count)
        guard rest.last == "," else { return false }
        // That comma must separate RDNs, not be an escaped one.
        let backslashes = rest.dropLast().reversed().prefix { $0 == "\\" }.count
        return backslashes % 2 == 0
    }

    /// The DNs from `base` down to `dn`'s parent, in that order — the
    /// nodes to expand to reveal `dn` in a tree rooted at `base`. Nil when
    /// `dn` isn't under `base`. Built from `dn`'s own spelling.
    static func path(to dn: String, from base: String) -> [String]? {
        let parts = components(dn)
        let baseDepth = components(base).count
        guard isWithin(dn, base), parts.count > baseDepth else {
            return isWithin(dn, base) ? [] : nil
        }
        var path: [String] = []
        for depth in stride(from: baseDepth, to: parts.count, by: 1) {
            path.append(parts.suffix(depth).joined(separator: ","))
        }
        return path
    }

    /// `dn` with its `ancestor` suffix swapped for `newAncestor` — where an
    /// entry ends up when a branch above it is moved or renamed.
    static func rebase(_ dn: String, from ancestor: String, to newAncestor: String) -> String {
        let parts = components(dn)
        let keep = parts.count - components(ancestor).count
        guard keep > 0 else { return newAncestor }
        return (parts.prefix(keep) + [newAncestor]).joined(separator: ",")
    }

    /// Escapes a value for use inside an LDAP filter (RFC 4515).
    static func escapeFilterValue(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "*": out += "\\2a"
            case "(": out += "\\28"
            case ")": out += "\\29"
            case "\\": out += "\\5c"
            case "\0": out += "\\00"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
