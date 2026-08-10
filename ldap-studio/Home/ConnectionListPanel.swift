//
//  ConnectionListPanel.swift
//  ldap-studio
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConnectionListPanel: View {
    @Environment(ConnectionStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    @State private var searchText: String = ""
    @State private var selection: Set<SavedConnection.ID> = []
    @State private var hoveredConnectionID: SavedConnection.ID?
    @State private var connectionToEdit: SavedConnection?
    @State private var connectionsPendingDeletion: [SavedConnection] = []
    @State private var isShowingDeleteConfirmation = false

    private var filteredConnections: [SavedConnection] {
        guard !searchText.isEmpty else { return store.connections }
        return store.connections.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.host.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search for connection…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 240)
            }
            .padding(12)

            Divider()

            if store.connections.isEmpty {
                ContentUnavailableView(
                    "No Connections",
                    systemImage: "server.rack",
                    description: Text("Click + to create your first LDAP connection.")
                )
            } else {
                List(filteredConnections, selection: $selection) { connection in
                    ConnectionRow(connection: connection, isHovering: hoveredConnectionID == connection.id)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredConnectionID = hovering ? connection.id : nil
                        }
                        .overlay(
                            DoubleClickObserver {
                                openWindow(value: connection)
                            }
                            .allowsHitTesting(false)
                        )
                        .contextMenu {
                            contextMenu(for: connection)
                        }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $connectionToEdit) { connection in
            NewConnectionSheet(existingConnection: connection)
        }
        .alert(
            connectionsPendingDeletion.count > 1
                ? "Delete \(connectionsPendingDeletion.count) Connections?"
                : "Delete Connection?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                for connection in connectionsPendingDeletion {
                    store.delete(connection)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if connectionsPendingDeletion.count > 1 {
                Text("Are you sure you want to delete these \(connectionsPendingDeletion.count) connections? This cannot be undone.")
            } else {
                Text("Are you sure you want to delete \"\(connectionsPendingDeletion.first?.name ?? "")\"? This cannot be undone.")
            }
        }
    }

    /// The connections a context-menu action should apply to: the full
    /// multi-selection if the clicked row is part of one, otherwise just
    /// the row that was clicked.
    private func targets(for connection: SavedConnection) -> [SavedConnection] {
        if selection.count > 1, selection.contains(connection.id) {
            return store.connections.filter { selection.contains($0.id) }
        }
        return [connection]
    }

    @ViewBuilder
    private func contextMenu(for connection: SavedConnection) -> some View {
        let targets = targets(for: connection)

        if targets.count == 1 {
            Button("Open", systemImage: "arrow.up.forward.app") {
                openWindow(value: connection)
            }
            Button("Edit", systemImage: "pencil") {
                connectionToEdit = connection
            }
        }

        Button(
            targets.count > 1 ? "Export \(targets.count) Connections…" : "Export…",
            systemImage: "square.and.arrow.up"
        ) {
            exportConnections(targets)
        }

        Divider()

        Button(
            targets.count > 1 ? "Delete \(targets.count) Connections" : "Delete",
            systemImage: "trash",
            role: .destructive
        ) {
            connectionsPendingDeletion = targets
            isShowingDeleteConfirmation = true
        }
    }

    private struct ExportableConnection: Codable {
        var name: String
        var host: String
        var port: Int
        var useSSL: Bool
        var bindDN: String
        var password: String
    }

    private func exportable(for connection: SavedConnection) -> ExportableConnection {
        ExportableConnection(
            name: connection.name,
            host: connection.host,
            port: connection.port,
            useSSL: connection.useSSL,
            bindDN: connection.bindDN,
            password: KeychainService.readPassword(for: connection.id) ?? ""
        )
    }

    private func exportConnections(_ connections: [SavedConnection]) {
        let items = connections.map { exportable(for: $0) }

        // Deferred to the next run loop tick so the context menu has fully
        // dismissed before we present another modal panel — presenting
        // synchronously from inside the menu's own action can crash.
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = items.count == 1 ? "\(connections[0].name).json" : "Connections.json"
            panel.allowedContentTypes = [.json]

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                let data = items.count == 1
                    ? try? JSONEncoder().encode(items[0])
                    : try? JSONEncoder().encode(items)
                guard let data else { return }
                try? data.write(to: url)
            }
        }
    }
}

#Preview {
    ConnectionListPanel()
        .frame(width: 500, height: 400)
        .environment(ConnectionStore())
}
