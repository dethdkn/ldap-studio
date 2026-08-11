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

    enum CodingKeys: String, CodingKey {
        case name, host, port, useSSL, baseDN, bindDN, password
    }

    init(name: String, host: String, port: Int, useSSL: Bool, baseDN: String, bindDN: String, password: String) {
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.baseDN = baseDN
        self.bindDN = bindDN
        self.password = password
    }

    // Custom decoding so files exported before `baseDN` existed still
    // import instead of silently failing — a missing `baseDN` becomes "".
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        useSSL = try container.decode(Bool.self, forKey: .useSSL)
        baseDN = try container.decodeIfPresent(String.self, forKey: .baseDN) ?? ""
        bindDN = try container.decode(String.self, forKey: .bindDN)
        password = try container.decode(String.self, forKey: .password)
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
    }
}

extension ExportableConnection {
    init(connection: SavedConnection, password: String) {
        self.init(
            name: connection.name,
            host: connection.host,
            port: connection.port,
            useSSL: connection.useSSL,
            baseDN: connection.baseDN,
            bindDN: connection.bindDN,
            password: password
        )
    }
}
