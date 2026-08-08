//
//  ConnectionRow.swift
//  ldap-studio
//

import SwiftUI

struct ConnectionRow: View {
    let name: String
    let host: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ConnectionRow(name: "Corp Directory", host: "ldap.corp.example.com:389")
        .padding()
}
