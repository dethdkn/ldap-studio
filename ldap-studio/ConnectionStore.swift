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
        var connection = connection
        connection.name = uniqueName(for: connection.name)
        connections.append(connection)
        persist()
    }

    /// If `proposedName` is already taken, appends the next free " N" suffix.
    /// A name that's already itself a numbered duplicate (e.g. "example 2")
    /// is treated as based on "example", so re-adding it produces "example 3"
    /// rather than "example 2 2".
    private func uniqueName(for proposedName: String) -> String {
        let existingNames = Set(connections.map(\.name))
        guard existingNames.contains(proposedName) else { return proposedName }

        let base = strippingNumericSuffix(from: proposedName)
        var suffix = 2
        while existingNames.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private func strippingNumericSuffix(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count > 1, Int(parts.last!) != nil {
            return parts.dropLast().joined(separator: " ")
        }
        return name
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
