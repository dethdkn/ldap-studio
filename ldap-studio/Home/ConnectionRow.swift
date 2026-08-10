//
//  ConnectionRow.swift
//  ldap-studio
//

import SwiftUI

struct ConnectionRow: View {
    let connection: SavedConnection
    var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.headline)
                Text("\(connection.host):\(connection.port)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
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
    ConnectionRow(connection: SavedConnection(name: "Corp Directory", host: "ldap.corp.example.com", port: 389, useSSL: false, bindDN: ""))
        .padding()
}
