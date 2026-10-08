//
//  ExportableConnection.swift
//  ldap-studio
//

import Foundation

/// The on-disk shape used for exporting/importing connections — unlike
/// `SavedConnection`, this includes the password, since export is an
/// explicit, one-off user action rather than the app's own persisted store.
/// The portable, shareable form of a saved connection. File references for a
/// client certificate, client key or SSH private key are deliberately NOT
/// included: they are security-scoped bookmarks, which only resolve on the
/// Mac and sandbox that created them, so on another machine they would just
/// silently fail. The importer asks the user to pick those files again.
struct ExportableConnection: Codable {
    var name: String
    var host: String
    var port: Int
    var useSSL: Bool
    var useStartTLS: Bool
    var baseDN: String
    var bindDN: String
    var bookmarks: [String]
    var savedFilters: [SavedLDAPFilter]
    var isFavorite: Bool
    var isReadOnly: Bool
    var trustedCertSHA256: String?
    var chaseReferrals: Bool
    var timeoutSeconds: Int
    var authentication: LDAPAuthentication
    var saslAuthID: String
    var saslRealm: String
    var useSSHTunnel: Bool
    var sshHost: String
    var sshPort: Int
    var sshUsername: String
    var sshAuthentication: SSHAuthentication
    var sshHostKeySHA256: String?
    var password: String
    /// Whether `password` is base64-encoded rather than plain text — an
    /// explicit flag rather than guessing from the string's shape on
    /// import, since a real plaintext password could coincidentally look
    /// like valid base64 too. Defaults to `false` for files exported before
    /// this existed, which always wrote plain text.
    var passwordIsBase64: Bool
    var sshPassword: String
    var sshPasswordIsBase64: Bool

    enum CodingKeys: String, CodingKey {
        case name, host, port, useSSL, useStartTLS, baseDN, bindDN, bookmarks, savedFilters, isFavorite, isReadOnly
        case trustedCertSHA256, chaseReferrals, timeoutSeconds, authentication, saslAuthID, saslRealm
        case useSSHTunnel, sshHost, sshPort, sshUsername, sshAuthentication, sshHostKeySHA256
        case password, passwordIsBase64, sshPassword, sshPasswordIsBase64
    }

    init(name: String, host: String, port: Int, useSSL: Bool, useStartTLS: Bool = false,
         baseDN: String, bindDN: String, bookmarks: [String] = [],
         savedFilters: [SavedLDAPFilter] = [], isFavorite: Bool = false,
         isReadOnly: Bool = false, trustedCertSHA256: String? = nil,
         chaseReferrals: Bool = false, timeoutSeconds: Int = 15,
         authentication: LDAPAuthentication = .simple, saslAuthID: String = "",
         saslRealm: String = "", useSSHTunnel: Bool = false,
         sshHost: String = "", sshPort: Int = 22, sshUsername: String = "",
         sshAuthentication: SSHAuthentication = .password,
         sshHostKeySHA256: String? = nil,
         password: String, passwordIsBase64: Bool = false,
         sshPassword: String = "", sshPasswordIsBase64: Bool = false) {
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.useStartTLS = useStartTLS
        self.baseDN = baseDN
        self.bindDN = bindDN
        self.bookmarks = bookmarks
        self.savedFilters = savedFilters
        self.isFavorite = isFavorite
        self.isReadOnly = isReadOnly
        self.trustedCertSHA256 = trustedCertSHA256
        self.chaseReferrals = chaseReferrals
        self.timeoutSeconds = timeoutSeconds
        self.authentication = authentication
        self.saslAuthID = saslAuthID
        self.saslRealm = saslRealm
        self.useSSHTunnel = useSSHTunnel
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshAuthentication = sshAuthentication
        self.sshHostKeySHA256 = sshHostKeySHA256
        self.password = password
        self.passwordIsBase64 = passwordIsBase64
        self.sshPassword = sshPassword
        self.sshPasswordIsBase64 = sshPasswordIsBase64
    }

    // Custom decoding so files exported before `baseDN`/`passwordIsBase64`
    // existed still import instead of silently failing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        useSSL = try container.decode(Bool.self, forKey: .useSSL)
        useStartTLS = try container.decodeIfPresent(Bool.self, forKey: .useStartTLS) ?? false
        baseDN = try container.decodeIfPresent(String.self, forKey: .baseDN) ?? ""
        bindDN = try container.decode(String.self, forKey: .bindDN)
        bookmarks = try container.decodeIfPresent([String].self, forKey: .bookmarks) ?? []
        savedFilters = try container.decodeIfPresent([SavedLDAPFilter].self, forKey: .savedFilters) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
        trustedCertSHA256 = try container.decodeIfPresent(String.self, forKey: .trustedCertSHA256)
        chaseReferrals = try container.decodeIfPresent(Bool.self, forKey: .chaseReferrals) ?? false
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 15
        authentication = try container.decodeIfPresent(LDAPAuthentication.self, forKey: .authentication) ?? .simple
        saslAuthID = try container.decodeIfPresent(String.self, forKey: .saslAuthID) ?? ""
        saslRealm = try container.decodeIfPresent(String.self, forKey: .saslRealm) ?? ""
        useSSHTunnel = try container.decodeIfPresent(Bool.self, forKey: .useSSHTunnel) ?? false
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshUsername = try container.decodeIfPresent(String.self, forKey: .sshUsername) ?? ""
        sshAuthentication = try container.decodeIfPresent(SSHAuthentication.self, forKey: .sshAuthentication) ?? .password
        sshHostKeySHA256 = try container.decodeIfPresent(String.self, forKey: .sshHostKeySHA256)
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        passwordIsBase64 = try container.decodeIfPresent(Bool.self, forKey: .passwordIsBase64) ?? false
        sshPassword = try container.decodeIfPresent(String.self, forKey: .sshPassword) ?? ""
        sshPasswordIsBase64 = try container.decodeIfPresent(Bool.self, forKey: .sshPasswordIsBase64) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(useSSL, forKey: .useSSL)
        try container.encode(useStartTLS, forKey: .useStartTLS)
        try container.encode(baseDN, forKey: .baseDN)
        try container.encode(bindDN, forKey: .bindDN)
        try container.encode(bookmarks, forKey: .bookmarks)
        if !savedFilters.isEmpty { try container.encode(savedFilters, forKey: .savedFilters) }
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(isReadOnly, forKey: .isReadOnly)
        try container.encodeIfPresent(trustedCertSHA256, forKey: .trustedCertSHA256)
        try container.encode(chaseReferrals, forKey: .chaseReferrals)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encode(authentication, forKey: .authentication)
        try container.encode(saslAuthID, forKey: .saslAuthID)
        try container.encode(saslRealm, forKey: .saslRealm)
        try container.encode(useSSHTunnel, forKey: .useSSHTunnel)
        try container.encode(sshHost, forKey: .sshHost)
        try container.encode(sshPort, forKey: .sshPort)
        try container.encode(sshUsername, forKey: .sshUsername)
        try container.encode(sshAuthentication, forKey: .sshAuthentication)
        try container.encodeIfPresent(sshHostKeySHA256, forKey: .sshHostKeySHA256)
        try container.encode(password, forKey: .password)
        try container.encode(passwordIsBase64, forKey: .passwordIsBase64)
        try container.encode(sshPassword, forKey: .sshPassword)
        try container.encode(sshPasswordIsBase64, forKey: .sshPasswordIsBase64)
    }

    /// The password ready to use — base64-decoded first if `passwordIsBase64`.
    var decodedPassword: String {
        guard passwordIsBase64 else { return password }
        guard let data = Data(base64Encoded: password), let decoded = String(data: data, encoding: .utf8) else {
            return password
        }
        return decoded
    }

    var decodedSSHPassword: String {
        guard sshPasswordIsBase64 else { return sshPassword }
        guard let data = Data(base64Encoded: sshPassword),
              let decoded = String(data: data, encoding: .utf8) else { return sshPassword }
        return decoded
    }
}

extension ExportableConnection {
    init(connection: SavedConnection, password: String, passwordIsBase64: Bool = false,
         sshPassword: String = "", sshPasswordIsBase64: Bool = false) {
        self.init(
            name: connection.name,
            host: connection.host,
            port: connection.port,
            useSSL: connection.useSSL,
            useStartTLS: connection.useStartTLS,
            baseDN: connection.baseDN,
            bindDN: connection.bindDN,
            bookmarks: connection.bookmarks,
            savedFilters: connection.savedFilters,
            isFavorite: connection.isFavorite,
            isReadOnly: connection.isReadOnly,
            trustedCertSHA256: connection.trustedCertSHA256,
            chaseReferrals: connection.chaseReferrals,
            timeoutSeconds: connection.timeoutSeconds,
            authentication: connection.authentication,
            saslAuthID: connection.saslAuthID,
            saslRealm: connection.saslRealm,
            useSSHTunnel: connection.useSSHTunnel,
            sshHost: connection.sshHost,
            sshPort: connection.sshPort,
            sshUsername: connection.sshUsername,
            sshAuthentication: connection.sshAuthentication,
            sshHostKeySHA256: connection.sshHostKeySHA256,
            password: password,
            passwordIsBase64: passwordIsBase64,
            sshPassword: sshPassword,
            sshPasswordIsBase64: sshPasswordIsBase64
        )
    }
}
