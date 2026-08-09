//
//  DirectoryTreeView.swift
//  ldap-studio
//

import SwiftUI

struct DirectoryTreeView: View {
    let root: DirectoryEntry
    @Binding var selection: DirectoryEntry.ID?

    var body: some View {
        List(selection: $selection) {
            OutlineGroup(root, children: \.children) { entry in
                Label(entry.name, systemImage: entry.icon)
                    .tag(entry.id)
            }
        }
    }
}

#Preview {
    DirectoryTreeView(root: .mockRoot, selection: .constant(nil))
        .frame(width: 260, height: 400)
}
