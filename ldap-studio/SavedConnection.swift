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
    var useSSL: Bool
    var bindDN: String

    init(id: UUID = UUID(), name: String, host: String, port: Int, useSSL: Bool, bindDN: String) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.bindDN = bindDN
    }
}
