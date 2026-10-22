//
//  LDIFParser.swift
//  ldap-studio
//

import Foundation

struct LDIFEntry {
    var dn: String
    var attributes: [(name: String, value: String, isBinary: Bool)]
}

/// One logical LDIF line after unfolding, with the 1-based source line it
/// started on. Handles CRLF files (Foundation's `.newlines` would otherwise
/// see an empty line inside every "\r\n") and RFC 2849 folding, where a line
/// starting with one space continues the previous one — `ldapsearch` and
/// most exporters fold long values that way.
private func unfoldedLDIFLines(_ text: String) -> [(text: String, number: Int)] {
    var out: [(text: String, number: Int)] = []
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
    for (idx, raw) in lines.enumerated() {
        if raw.hasPrefix(" "), !out.isEmpty {
            out[out.count - 1].text += String(raw.dropFirst())
        } else {
            out.append((text: raw, number: idx + 1))
        }
    }
    return out
}

/// Splits "name: value" / "name:: base64" after its colon — every space of
/// the RFC 2849 FILL is dropped, not just the first.
private func ldifValue(after colon: String.Index, in line: String) -> (value: String, isBinary: Bool) {
    var rest = line[line.index(after: colon)...]
    let isBinary = rest.first == ":"
    if isBinary { rest = rest.dropFirst() }
    return (String(rest.drop(while: { $0 == " " })), isBinary)
}

/// A base64 (`name::`) value decoded as UTF-8 text, for fields that are
/// always text (dn, newrdn, newsuperior). Falls back to the raw value.
private func ldifText(_ value: String, isBinary: Bool) -> String {
    guard isBinary else { return value }
    return Data(base64Encoded: value).flatMap { String(data: $0, encoding: .utf8) } ?? value
}

/// A minimal RFC 2849 reader — enough for entries produced by this app's own
/// export, or by most other LDAP tools' plain exports.
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

        for (rawLine, _) in unfoldedLDIFLines(text) {
            if rawLine.isEmpty {
                flush()
                continue
            }
            if rawLine.hasPrefix("#") || rawLine.hasPrefix("version:") {
                continue
            }
            guard let colonIndex = rawLine.firstIndex(of: ":") else { continue }

            let name = String(rawLine[rawLine.startIndex..<colonIndex])
            let (value, isBinary) = ldifValue(after: colonIndex, in: rawLine)

            if name == "dn" {
                flush()
                currentDN = ldifText(value, isBinary: isBinary)
            } else {
                currentAttributes.append((name: name, value: value, isBinary: isBinary))
            }
        }
        flush()

        return entries
    }
}

// MARK: - Change records (for the LDIF editor's Run)

struct LDIFModification {
    enum Kind { case add, delete, replace }
    var kind: Kind
    var attribute: String
    /// Empty for a whole-attribute delete / replace-with-nothing. `value`
    /// stays base64-encoded when `isBinary`.
    var values: [(value: String, isBinary: Bool)]
}

enum LDIFChange {
    case add(attributes: [(name: String, value: String, isBinary: Bool)])
    case delete
    case modify(ops: [LDIFModification])
    case modrdn(newRDN: String, deleteOldRDN: Bool, newSuperior: String?)
}

struct LDIFRecord {
    var dn: String
    var change: LDIFChange
    /// 1-based line number where the record's `dn:` appeared.
    var line: Int
}

enum LDIFChangeParser {
    struct ParseError: LocalizedError {
        let line: Int
        let message: String
        var errorDescription: String? { "Line \(line): \(message)" }
    }

    private typealias Line = (text: String, number: Int)

    static func parse(_ text: String) throws -> [LDIFRecord] {
        let logical = unfoldedLDIFLines(text)
        var records: [LDIFRecord] = []

        var i = 0
        while i < logical.count {
            // Skip blank lines, comments, and the version header between records.
            while i < logical.count {
                let t = logical[i].text
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("version:") {
                    i += 1
                } else {
                    break
                }
            }
            guard i < logical.count else { break }

            // Collect this record's lines (until a blank line).
            var block: [Line] = []
            while i < logical.count, !logical[i].text.isEmpty {
                if !logical[i].text.hasPrefix("#") {
                    block.append(logical[i])
                }
                i += 1
            }
            if block.isEmpty { continue }
            records.append(try parseRecord(block))
        }
        return records
    }

    // MARK: -

    /// Splits "name: value" / "name:: base64" — returns (name, value, isBinary).
    private static func field(_ line: Line) throws -> (name: String, value: String, isBinary: Bool) {
        guard let colon = line.text.firstIndex(of: ":") else {
            throw ParseError(line: line.number, message: "expected \"name: value\"")
        }
        let name = String(line.text[line.text.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        if line.text[line.text.index(after: colon)...].first == "<" {
            throw ParseError(line: line.number, message: "URL-valued attributes (name:< …) aren't supported")
        }
        let (value, isBinary) = ldifValue(after: colon, in: line.text)
        return (name, value, isBinary)
    }

    private static func parseRecord(_ block: [Line]) throws -> LDIFRecord {
        let first = try field(block[0])
        guard first.name.caseInsensitiveCompare("dn") == .orderedSame else {
            throw ParseError(line: block[0].number, message: "record must start with \"dn:\"")
        }
        let dn = ldifText(first.value, isBinary: first.isBinary)
        let recordLine = block[0].number

        let rest = Array(block.dropFirst())

        // changetype (optional — its absence means a plain add record).
        var changeType = "add"
        var body = rest
        if let ct = rest.first {
            let f = try field(ct)
            if f.name.caseInsensitiveCompare("changetype") == .orderedSame {
                changeType = f.value.trimmingCharacters(in: .whitespaces).lowercased()
                body = Array(rest.dropFirst())
            }
        }

        switch changeType {
        case "add":
            var attrs: [(name: String, value: String, isBinary: Bool)] = []
            for l in body {
                let f = try field(l)
                attrs.append((f.name, f.value, f.isBinary))
            }
            return LDIFRecord(dn: dn, change: .add(attributes: attrs), line: recordLine)

        case "delete":
            return LDIFRecord(dn: dn, change: .delete, line: recordLine)

        case "modrdn", "moddn":
            var newRDN: String?
            var deleteOld = true
            var newSuperior: String?
            for l in body {
                let f = try field(l)
                switch f.name.lowercased() {
                case "newrdn": newRDN = ldifText(f.value, isBinary: f.isBinary)
                case "deleteoldrdn": deleteOld = f.value.trimmingCharacters(in: .whitespaces) != "0"
                case "newsuperior": newSuperior = ldifText(f.value, isBinary: f.isBinary)
                default: break
                }
            }
            guard let rdn = newRDN, !rdn.isEmpty else {
                throw ParseError(line: recordLine, message: "modrdn record needs \"newrdn:\"")
            }
            return LDIFRecord(dn: dn,
                              change: .modrdn(newRDN: rdn, deleteOldRDN: deleteOld, newSuperior: newSuperior),
                              line: recordLine)

        case "modify":
            let ops = try parseModifyOps(body, recordLine: recordLine)
            return LDIFRecord(dn: dn, change: .modify(ops: ops), line: recordLine)

        default:
            throw ParseError(line: recordLine, message: "unknown changetype \"\(changeType)\"")
        }
    }

    private static func parseModifyOps(_ lines: [Line], recordLine: Int) throws -> [LDIFModification] {
        var ops: [LDIFModification] = []
        var idx = 0
        while idx < lines.count {
            let header = try field(lines[idx])
            let kind: LDIFModification.Kind
            switch header.name.lowercased() {
            case "add": kind = .add
            case "delete": kind = .delete
            case "replace": kind = .replace
            default:
                throw ParseError(line: lines[idx].number,
                                 message: "expected add/delete/replace, got \"\(header.name)\"")
            }
            let attribute = header.value.trimmingCharacters(in: .whitespaces)
            idx += 1

            var values: [(value: String, isBinary: Bool)] = []
            while idx < lines.count, lines[idx].text != "-" {
                let f = try field(lines[idx])
                guard f.name.caseInsensitiveCompare(attribute) == .orderedSame else {
                    throw ParseError(line: lines[idx].number,
                                     message: "\"\(f.name)\" doesn't match the \"\(attribute)\" being modified")
                }
                values.append((f.value, f.isBinary))
                idx += 1
            }
            idx += 1  // skip the "-"
            ops.append(LDIFModification(kind: kind, attribute: attribute, values: values))
        }
        if ops.isEmpty {
            throw ParseError(line: recordLine, message: "modify record has no changes")
        }
        return ops
    }
}
