//
//  SavedConnection.swift
//  ldap-studio
//

import Foundation

struct SavedLDAPFilter: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String?
    var filter: String
    var isPinned: Bool = false
    var lastUsed: Date = .now
}

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
    /// Named/pinned filters and the recent Advanced Search history for this
    /// connection. Unpinned history is kept newest first and bounded by the
    /// search UI; pinned filters are never evicted.
    var savedFilters: [SavedLDAPFilter]
    /// Pinned to the top of the connection list with a star.
    var isFavorite: Bool
    /// Every write path is blocked for this connection — a guard against
    /// fat-fingering a change on a production directory.
    var isReadOnly: Bool

    init(id: UUID = UUID(), name: String, host: String, port: Int, useSSL: Bool,
         useStartTLS: Bool = false, baseDN: String, bindDN: String,
         trustedCertSHA256: String? = nil, bookmarks: [String] = [],
         savedFilters: [SavedLDAPFilter] = [],
         isFavorite: Bool = false, isReadOnly: Bool = false) {
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
        self.savedFilters = savedFilters
        self.isFavorite = isFavorite
        self.isReadOnly = isReadOnly
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, useSSL, useStartTLS, baseDN, bindDN, trustedCertSHA256, bookmarks, savedFilters, isFavorite, isReadOnly
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
        savedFilters = try container.decodeIfPresent([SavedLDAPFilter].self, forKey: .savedFilters) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
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
        if !savedFilters.isEmpty { try container.encode(savedFilters, forKey: .savedFilters) }
        if isFavorite { try container.encode(true, forKey: .isFavorite) }
        if isReadOnly { try container.encode(true, forKey: .isReadOnly) }
    }
}
