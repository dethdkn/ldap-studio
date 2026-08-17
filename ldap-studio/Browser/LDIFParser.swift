//
//  LDIFParser.swift
//  ldap-studio
//

import Foundation

struct LDIFEntry {
    var dn: String
    var attributes: [(name: String, value: String, isBinary: Bool)]
}

/// A minimal RFC 2849 reader — enough for entries produced by this app's own
/// export, or by most other LDAP tools' plain exports. It does not handle
/// line folding (continuation lines starting with a single leading space),
/// which some exporters use for long values.
enum LDIFParser {
    static func parse(_ text: String) -> [LDIFEntry] {
        var entries: [LDIFEntry] = []
        var currentDN: String?
        var currentAttributes: [(name: String, value: String, isBinary: Bool)] = []

        func flush() {
            if let dn = currentDN {
                entries.append(LDIFEntry(dn: dn, attributes: currentAttributes))
            }
            currentDN = nil
            currentAttributes = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            if rawLine.isEmpty {
                flush()
                continue
            }
            if rawLine.hasPrefix("#") || rawLine.hasPrefix("version:") {
                continue
            }
            guard let colonIndex = rawLine.firstIndex(of: ":") else { continue }

            let name = String(rawLine[rawLine.startIndex..<colonIndex])
            var rest = rawLine[rawLine.index(after: colonIndex)...]
            var isBinary = false
            if rest.first == ":" {
                isBinary = true
                rest = rest.dropFirst()
            }
            if rest.first == " " {
                rest = rest.dropFirst()
            }
            let value = String(rest)

            if name == "dn" {
                flush()
                if isBinary {
                    currentDN = Data(base64Encoded: value).flatMap { String(data: $0, encoding: .utf8) } ?? value
                } else {
                    currentDN = value
                }
            } else {
                currentAttributes.append((name: name, value: value, isBinary: isBinary))
            }
        }
        flush()

        return entries
    }
}
