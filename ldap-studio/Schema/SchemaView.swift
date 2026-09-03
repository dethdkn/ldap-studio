//
//  SchemaView.swift
//  ldap-studio
//

import SwiftUI

struct SchemaView: View {
    let connection: SavedConnection

    @State private var schema: LdapSchema?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Load Schema", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            } else if let schema {
                TabView {
                    SchemaObjectClassesTab(objectClasses: schema.objectClasses)
                        .tabItem {
                            Label("Object Classes", systemImage: "square.stack.3d.up")
                        }

                    SchemaAttributesTab(objectClasses: schema.objectClasses, attributeTypes: schema.attributeTypes)
                        .tabItem {
                            Label("Attributes", systemImage: "list.bullet")
                        }
                }
            } else {
                ProgressView("Loading Schema…")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle("Ldap Studio - \(connection.name) Schema")
        .task {
            await load()
        }
    }

    private func load() async {
        loadError = nil
        do {
            schema = try await fetchSchema(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: KeychainService.readPassword(for: connection.id) ?? ""
            )
        } catch {
            loadError = "\(error)"
        }
    }
}

/// A "Label / value" pair stacked vertically, matching how the object class
/// and attribute detail panels present each schema field.
struct SchemaField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    SchemaView(connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "", bindDN: ""))
}
