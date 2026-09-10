//
//  SavedConnection.swift
//  ldap-studio
//

import Foundation

struct SavedConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    /// LDAPS — TLS from the first byte, on 636.
    var useSSL: Bool
    /// StartTLS — connect in the clear on 389, then upgrade. Mutually
    /// exclusive with `useSSL` in the UI.
    var useStartTLS: Bool
    var baseDN: String
    var bindDN: String
    /// SHA-256 (lowercase hex) of a server leaf certificate the user chose
    /// to trust for this connection, when it wouldn't validate against the
    /// system trust store. `nil` = normal chain verification.
    var trustedCertSHA256: String?
    /// DNs the user pinned for quick jumping, newest first.
    var bookmarks: [String]

    init(id: UUID = UUID(), name: String, host: String, port: Int, useSSL: Bool,
         useStartTLS: Bool = false, baseDN: String, bindDN: String,
         trustedCertSHA256: String? = nil, bookmarks: [String] = []) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.useStartTLS = useStartTLS
        self.baseDN = baseDN
        self.bindDN = bindDN
        self.trustedCertSHA256 = trustedCertSHA256
        self.bookmarks = bookmarks
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, useSSL, useStartTLS, baseDN, bindDN, trustedCertSHA256, bookmarks
    }

    // Custom decoding so older saved files (from before `baseDN` /
    // `useStartTLS` / `trustedCertSHA256` existed) still load instead of
    // silently failing the whole array — a missing key just takes its
    // default rather than a decode error.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        useSSL = try container.decode(Bool.self, forKey: .useSSL)
        useStartTLS = try container.decodeIfPresent(Bool.self, forKey: .useStartTLS) ?? false
        baseDN = try container.decodeIfPresent(String.self, forKey: .baseDN) ?? ""
        bindDN = try container.decode(String.self, forKey: .bindDN)
        trustedCertSHA256 = try container.decodeIfPresent(String.self, forKey: .trustedCertSHA256)
        bookmarks = try container.decodeIfPresent([String].self, forKey: .bookmarks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(useSSL, forKey: .useSSL)
        try container.encode(useStartTLS, forKey: .useStartTLS)
        try container.encode(baseDN, forKey: .baseDN)
        try container.encode(bindDN, forKey: .bindDN)
        try container.encodeIfPresent(trustedCertSHA256, forKey: .trustedCertSHA256)
        if !bookmarks.isEmpty { try container.encode(bookmarks, forKey: .bookmarks) }
    }
}
