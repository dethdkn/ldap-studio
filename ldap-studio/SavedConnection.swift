//
//  SavedConnection.swift
//  ldap-studio
//

import Foundation

enum LDAPAuthentication: String, Codable, CaseIterable, Identifiable {
    case simple, external, gssapi, digestMD5
    var id: Self { self }
    var title: String {
        switch self {
        case .simple: "Simple Bind"
        case .external: "SASL EXTERNAL"
        case .gssapi: "SASL GSSAPI / Kerberos"
        case .digestMD5: "SASL DIGEST-MD5"
        }
    }
}

enum SSHAuthentication: String, Codable, CaseIterable, Identifiable {
    case password, privateKey
    var id: Self { self }
    var title: String { self == .password ? "Password" : "Private Key" }
}

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
    var chaseReferrals: Bool
    var timeoutSeconds: Int
    var authentication: LDAPAuthentication
    var saslAuthID: String
    var saslRealm: String
    var clientCertificateBookmark: Data?
    var clientKeyBookmark: Data?
    var useSSHTunnel: Bool
    var sshHost: String
    var sshPort: Int
    var sshUsername: String
    var sshAuthentication: SSHAuthentication
    var sshPrivateKeyBookmark: Data?
    var sshHostKeySHA256: String?

    init(id: UUID = UUID(), name: String, host: String, port: Int, useSSL: Bool,
         useStartTLS: Bool = false, baseDN: String, bindDN: String,
         trustedCertSHA256: String? = nil, bookmarks: [String] = [],
         savedFilters: [SavedLDAPFilter] = [],
         isFavorite: Bool = false, isReadOnly: Bool = false,
         chaseReferrals: Bool = false, timeoutSeconds: Int = 15,
         authentication: LDAPAuthentication = .simple,
         saslAuthID: String = "", saslRealm: String = "",
         clientCertificateBookmark: Data? = nil, clientKeyBookmark: Data? = nil,
         useSSHTunnel: Bool = false, sshHost: String = "", sshPort: Int = 22,
         sshUsername: String = "", sshAuthentication: SSHAuthentication = .password,
         sshPrivateKeyBookmark: Data? = nil, sshHostKeySHA256: String? = nil) {
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
        self.chaseReferrals = chaseReferrals
        self.timeoutSeconds = timeoutSeconds
        self.authentication = authentication
        self.saslAuthID = saslAuthID
        self.saslRealm = saslRealm
        self.clientCertificateBookmark = clientCertificateBookmark
        self.clientKeyBookmark = clientKeyBookmark
        self.useSSHTunnel = useSSHTunnel
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshAuthentication = sshAuthentication
        self.sshPrivateKeyBookmark = sshPrivateKeyBookmark
        self.sshHostKeySHA256 = sshHostKeySHA256
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, useSSL, useStartTLS, baseDN, bindDN, trustedCertSHA256, bookmarks, savedFilters, isFavorite, isReadOnly
        case chaseReferrals, timeoutSeconds, authentication, saslAuthID, saslRealm
        case clientCertificateBookmark, clientKeyBookmark
        case useSSHTunnel, sshHost, sshPort, sshUsername, sshAuthentication, sshPrivateKeyBookmark, sshHostKeySHA256
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
        chaseReferrals = try container.decodeIfPresent(Bool.self, forKey: .chaseReferrals) ?? false
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 15
        authentication = try container.decodeIfPresent(LDAPAuthentication.self, forKey: .authentication) ?? .simple
        saslAuthID = try container.decodeIfPresent(String.self, forKey: .saslAuthID) ?? ""
        saslRealm = try container.decodeIfPresent(String.self, forKey: .saslRealm) ?? ""
        clientCertificateBookmark = try container.decodeIfPresent(Data.self, forKey: .clientCertificateBookmark)
        clientKeyBookmark = try container.decodeIfPresent(Data.self, forKey: .clientKeyBookmark)
        useSSHTunnel = try container.decodeIfPresent(Bool.self, forKey: .useSSHTunnel) ?? false
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshUsername = try container.decodeIfPresent(String.self, forKey: .sshUsername) ?? ""
        sshAuthentication = try container.decodeIfPresent(SSHAuthentication.self, forKey: .sshAuthentication) ?? .password
        sshPrivateKeyBookmark = try container.decodeIfPresent(Data.self, forKey: .sshPrivateKeyBookmark)
        sshHostKeySHA256 = try container.decodeIfPresent(String.self, forKey: .sshHostKeySHA256)
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
        if chaseReferrals { try container.encode(true, forKey: .chaseReferrals) }
        if timeoutSeconds != 15 { try container.encode(timeoutSeconds, forKey: .timeoutSeconds) }
        if authentication != .simple { try container.encode(authentication, forKey: .authentication) }
        if !saslAuthID.isEmpty { try container.encode(saslAuthID, forKey: .saslAuthID) }
        if !saslRealm.isEmpty { try container.encode(saslRealm, forKey: .saslRealm) }
        try container.encodeIfPresent(clientCertificateBookmark, forKey: .clientCertificateBookmark)
        try container.encodeIfPresent(clientKeyBookmark, forKey: .clientKeyBookmark)
        if useSSHTunnel { try container.encode(true, forKey: .useSSHTunnel) }
        if !sshHost.isEmpty { try container.encode(sshHost, forKey: .sshHost) }
        if sshPort != 22 { try container.encode(sshPort, forKey: .sshPort) }
        if !sshUsername.isEmpty { try container.encode(sshUsername, forKey: .sshUsername) }
        if sshAuthentication != .password { try container.encode(sshAuthentication, forKey: .sshAuthentication) }
        try container.encodeIfPresent(sshPrivateKeyBookmark, forKey: .sshPrivateKeyBookmark)
        try container.encodeIfPresent(sshHostKeySHA256, forKey: .sshHostKeySHA256)
    }
}

extension SavedConnection {
    var ldapOptions: LDAPConnectionOptions {
        let method: LdapAuthenticationMethod = switch authentication {
        case .simple: .simple
        case .external: .external
        case .gssapi: .gssapi
        case .digestMD5: .digestMD5
        }
        return LDAPConnectionOptions(
            chaseReferrals: chaseReferrals,
            timeoutSeconds: timeoutSeconds,
            authentication: method,
            authID: saslAuthID,
            realm: saslRealm,
            clientCertificateBookmark: clientCertificateBookmark,
            clientKeyBookmark: clientKeyBookmark,
            useSSHTunnel: useSSHTunnel,
            sshHost: sshHost,
            sshPort: sshPort,
            sshUsername: sshUsername,
            sshUsesPrivateKey: sshAuthentication == .privateKey,
            // Every LDAP operation builds these options, so don't hit the
            // Keychain for a password that only matters through a tunnel.
            sshPassword: useSSHTunnel ? (KeychainService.readSSHPassword(for: id) ?? "") : "",
            sshPrivateKeyBookmark: sshPrivateKeyBookmark,
            sshHostKeySHA256: sshHostKeySHA256
        )
    }
}
