//
//  Home.swift
//  ldap-studio
//

import SwiftUI

struct Home: View {
    @State private var store = ConnectionStore()

    var body: some View {
        HStack(spacing: 0) {
            InfoPanel()
            Divider()
            ConnectionListPanel()
        }
        .frame(minWidth: 700, minHeight: 420)
        .environment(store)
        .task {
            store.load()
        }
    }
}

#Preview {
    Home()
}
