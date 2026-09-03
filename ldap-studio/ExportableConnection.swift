//
//  ExportableConnection.swift
//  ldap-studio
//

import Foundation

/// The on-disk shape used for exporting/importing connections — unlike
/// `SavedConnection`, this includes the password, since export is an
/// explicit, one-off user action rather than the app's own persisted store.
struct ExportableConnection: Codable {
    var name: String
    var host: String
    var port: Int
    var useSSL: Bool
    var baseDN: String
    var bindDN: String
    var password: String
    /// Whether `password` is base64-encoded rather than plain text — an
    /// explicit flag rather than guessing from the string's shape on
    /// import, since a real plaintext password could coincidentally look
    /// like valid base64 too. Defaults to `false` for files exported before
    /// this existed, which always wrote plain text.
    var passwordIsBase64: Bool

    enum CodingKeys: String, CodingKey {
        case name, host, port, useSSL, baseDN, bindDN, password, passwordIsBase64
    }

    init(name: String, host: String, port: Int, useSSL: Bool, baseDN: String, bindDN: String, password: String, passwordIsBase64: Bool = false) {
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.baseDN = baseDN
        self.bindDN = bindDN
        self.password = password
        self.passwordIsBase64 = passwordIsBase64
    }

    // Custom decoding so files exported before `baseDN`/`passwordIsBase64`
    // existed still import instead of silently failing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        useSSL = try container.decode(Bool.self, forKey: .useSSL)
        baseDN = try container.decodeIfPresent(String.self, forKey: .baseDN) ?? ""
        bindDN = try container.decode(String.self, forKey: .bindDN)
        password = try container.decode(String.self, forKey: .password)
        passwordIsBase64 = try container.decodeIfPresent(Bool.self, forKey: .passwordIsBase64) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(useSSL, forKey: .useSSL)
        try container.encode(baseDN, forKey: .baseDN)
        try container.encode(bindDN, forKey: .bindDN)
        try container.encode(password, forKey: .password)
        try container.encode(passwordIsBase64, forKey: .passwordIsBase64)
    }

    /// The password ready to use — base64-decoded first if `passwordIsBase64`.
    var decodedPassword: String {
        guard passwordIsBase64 else { return password }
        guard let data = Data(base64Encoded: password), let decoded = String(data: data, encoding: .utf8) else {
            return password
        }
        return decoded
    }
}

extension ExportableConnection {
    init(connection: SavedConnection, password: String, passwordIsBase64: Bool = false) {
        self.init(
            name: connection.name,
            host: connection.host,
            port: connection.port,
            useSSL: connection.useSSL,
            baseDN: connection.baseDN,
            bindDN: connection.bindDN,
            password: password,
            passwordIsBase64: passwordIsBase64
        )
    }
}
