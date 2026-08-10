//
//  ConnectionStore.swift
//  ldap-studio
//

import Foundation

@Observable
final class ConnectionStore {
    private(set) var connections: [SavedConnection] = []

    private var fileURL: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "LDAPStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("connections.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        connections = (try? JSONDecoder().decode([SavedConnection].self, from: data)) ?? []
    }

    func add(_ connection: SavedConnection) {
        connections.append(connection)
        persist()
    }

    func update(_ connection: SavedConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        persist()
    }

    func delete(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        KeychainService.deletePassword(for: connection.id)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
