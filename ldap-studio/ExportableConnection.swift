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
}

extension ExportableConnection {
    init(connection: SavedConnection, password: String) {
        self.name = connection.name
        self.host = connection.host
        self.port = connection.port
        self.useSSL = connection.useSSL
        self.baseDN = connection.baseDN
        self.bindDN = connection.bindDN
        self.password = password
    }
}
