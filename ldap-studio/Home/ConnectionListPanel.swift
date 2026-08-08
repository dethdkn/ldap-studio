//
//  ConnectionListPanel.swift
//  ldap-studio
//

import SwiftUI

struct ConnectionListPanel: View {
    @State private var searchText: String = ""

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

            ContentUnavailableView(
                "No Connections",
                systemImage: "server.rack",
                description: Text("Click + to create your first LDAP connection.")
            )
        }
    }
}

#Preview {
    ConnectionListPanel()
        .frame(width: 500, height: 400)
}
