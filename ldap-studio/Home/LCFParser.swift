//
//  LCFParser.swift
//  ldap-studio
//

import Foundation

/// One connection extracted from an LDAP Admin (.lcf) settings file.
struct LCFAccount {
    var name: String
    var host: String
    var port: Int
    var useSSL: Bool
    var baseDN: String
    var bindDN: String
    var password: String
}

/// Reads LDAP Admin for Windows' .lcf export format — an XML tree of
/// accounts, optionally grouped into folders. We don't have a folder
/// concept of our own, so this flattens everything into one list.
enum LCFParser {
    static func parse(_ data: Data) -> [LCFAccount] {
        // LDAP Admin wraps its root account group in a literal "{Accounts}"
        // tag. Curly braces aren't valid in XML element names, so the
        // strict parser rejects the file outright unless they're stripped
        // first — confirmed via a real .lcf file that this is the only use
        // of braces anywhere in the format.
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let sanitized = text
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        guard let sanitizedData = sanitized.data(using: .utf8),
              let doc = try? XMLDocument(data: sanitizedData, options: []),
              let root = doc.rootElement() else { return [] }

        var results: [LCFAccount] = []
        collectAccounts(from: root, into: &results)
        return results
    }

    /// An element with a `<Connection>` child is an account; anything else
    /// (the `<Accounts>` wrapper, or a named folder) just gets recursed
    /// into and otherwise discarded — flattening whatever folder structure
    /// existed into a plain list.
    private static func collectAccounts(from element: XMLElement, into results: inout [LCFAccount]) {
        for case let child as XMLElement in element.children ?? [] {
            if let connectionElement = child.elements(forName: "Connection").first {
                if let account = makeAccount(name: child.name ?? "Imported", connection: connectionElement) {
                    results.append(account)
                }
            } else {
                collectAccounts(from: child, into: &results)
            }
        }
    }

    private static func makeAccount(name: String, connection: XMLElement) -> LCFAccount? {
        let host = connection.elements(forName: "Server").first?.stringValue ?? ""
        guard !host.isEmpty else { return nil }

        let portText = connection.elements(forName: "Port").first?.stringValue ?? "389"
        let port = Int(portText) ?? 389
        let useSSL = (connection.elements(forName: "SSL").first?.stringValue ?? "0") == "1"
        let baseDN = connection.elements(forName: "Base").first?.stringValue ?? ""
        let credentialsBase64 = connection.elements(forName: "Credentials").first?.stringValue ?? ""
        let (bindDN, password) = decodeCredentials(credentialsBase64)

        return LCFAccount(name: name, host: host, port: port, useSSL: useSSL, baseDN: baseDN, bindDN: bindDN, password: password)
    }

    /// `<Credentials>` is base64 of a small binary record — confirmed by
    /// decoding a real file's entry and finding the password field spell
    /// out its already-known plaintext value:
    /// `[u32 flag=1][u32 length][UTF-16LE bind DN][u32 length][UTF-16LE password]`,
    /// all little-endian. Not encrypted or obfuscated in any way.
    private static func decodeCredentials(_ base64: String) -> (bindDN: String, password: String) {
        guard let data = Data(base64Encoded: base64), data.count >= 4 else { return ("", "") }
        var offset = 4 // skip the leading flag

        func readUInt32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let bytes = data.subdata(in: offset..<(offset + 4))
            offset += 4
            return bytes.withUnsafeBytes { raw in UInt32(littleEndian: raw.load(as: UInt32.self)) }
        }

        func readString() -> String {
            guard let length = readUInt32() else { return "" }
            let len = Int(length)
            guard len > 0, offset + len <= data.count else { return "" }
            let stringData = data.subdata(in: offset..<(offset + len))
            offset += len
            return String(data: stringData, encoding: .utf16LittleEndian) ?? ""
        }

        return (readString(), readString())
    }
}
