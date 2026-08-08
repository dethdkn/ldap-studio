//
//  Home.swift
//  ldap-studio
//

import SwiftUI

struct Home: View {
    var body: some View {
        HStack(spacing: 0) {
            InfoPanel()
            Divider()
            ConnectionListPanel()
        }
        .frame(minWidth: 700, minHeight: 420)
    }
}

#Preview {
    Home()
}
