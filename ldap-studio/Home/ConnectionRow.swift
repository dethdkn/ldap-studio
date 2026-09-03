//
//  ConnectionRow.swift
//  ldap-studio
//

import SwiftUI

struct ConnectionRow: View {
    let connection: SavedConnection
    var isHovering: Bool = false

    /// A bind DN with no password behind it will simply fail to bind —
    /// worth a quiet nudge. An empty bind DN (anonymous bind) is a normal,
    /// deliberate setup, not something to flag.
    private var isMissingPassword: Bool {
        !connection.bindDN.isEmpty && (KeychainService.readPassword(for: connection.id) ?? "").isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("\(connection.host):\(connection.port)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isMissingPassword {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("No password saved for this connection's bind DN")
                        Text("password not set")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if connection.bindDN.isEmpty {
                Text("anonymous connection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text(connection.bindDN)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.gray.opacity(0.15) : Color.clear)
                .allowsHitTesting(false)
        )
    }
}

#Preview {
    ConnectionRow(connection: SavedConnection(name: "Corp Directory", host: "ldap.corp.example.com", port: 389, useSSL: false, baseDN: "dc=corp,dc=example,dc=com", bindDN: ""))
        .padding()
}
