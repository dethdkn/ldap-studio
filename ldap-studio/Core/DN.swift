//
//  DN.swift
//  ldap-studio
//

import Foundation

/// Splits distinguished names into RDNs. A backslash-escaped comma
/// ("cn=Smith\, John") is part of a value, not a separator, so a plain
/// `split(separator: ",")` gets those entries wrong.
enum DN {
    /// The RDNs of `dn`, leftmost first, each exactly as written.
    static func components(of dn: String) -> [Substring] {
        var parts: [Substring] = []
        var start = dn.startIndex
        var isEscaped = false
        for index in dn.indices {
            let character = dn[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "," {
                parts.append(dn[start..<index])
                start = dn.index(after: index)
            }
        }
        parts.append(dn[start...])
        return parts
    }

    /// The leftmost RDN, e.g. "cn=Smith\, John".
    static func rdn(of dn: String) -> String {
        String(components(of: dn)[0])
    }

    /// Everything after the leftmost RDN, or "" for a single-RDN DN.
    static func parent(of dn: String) -> String {
        components(of: dn).dropFirst().joined(separator: ",")
    }

    /// Every ancestor of `dn`, nearest first — "uid=x,ou=People,dc=com"
    /// gives ["ou=People,dc=com", "dc=com"].
    static func ancestors(of dn: String) -> [String] {
        let parts = components(of: dn)
        return (1..<parts.count).map { parts[$0...].joined(separator: ",") }
    }

    /// `value` escaped for use inside an RDN (RFC 4514 §2.4), so
    /// "Smith, John" becomes "Smith\, John".
    static func escaped(_ value: String) -> String {
        let lastOffset = value.count - 1
        var out = ""
        for (offset, character) in value.enumerated() {
            let isEdge = (offset == 0 && (character == " " || character == "#"))
                || (offset == lastOffset && character == " ")
            if isEdge || ",+\"\\<>;".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// An attribute value with its RFC 4514 escapes resolved: `\,` → `,`
    /// and hex pairs like `\C3\A9` → `é`.
    static func unescaped(_ value: Substring) -> String {
        let bytes = Array(value.utf8)
        func isHex(_ byte: UInt8) -> Bool { Character(Unicode.Scalar(byte)).isHexDigit }
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "\\"), i + 1 < bytes.count {
                if i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]),
                   let byte = UInt8(String(decoding: bytes[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                    out.append(byte)
                    i += 3
                } else {
                    out.append(bytes[i + 1])
                    i += 2
                }
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}
