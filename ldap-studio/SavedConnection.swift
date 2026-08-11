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
    var baseDN: String
    var bindDN: String

    init(id: UUID = UUID(), name: String, host: String, port: Int, useSSL: Bool, baseDN: String, bindDN: String) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.baseDN = baseDN
        self.bindDN = bindDN
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, useSSL, baseDN, bindDN
    }

    // Custom decoding so older saved files (from before `baseDN` existed)
    // still load instead of silently failing the whole array — a missing
    // `baseDN` just becomes "" rather than a decode error.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        useSSL = try container.decode(Bool.self, forKey: .useSSL)
        baseDN = try container.decodeIfPresent(String.self, forKey: .baseDN) ?? ""
        bindDN = try container.decode(String.self, forKey: .bindDN)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(useSSL, forKey: .useSSL)
        try container.encode(baseDN, forKey: .baseDN)
        try container.encode(bindDN, forKey: .bindDN)
    }
}
