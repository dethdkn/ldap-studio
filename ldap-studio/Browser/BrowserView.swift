//
//  BrowserView.swift
//  ldap-studio
//

import SwiftUI

struct BrowserView: View {
    private let root = DirectoryEntry.mockRoot

    @State private var selection: DirectoryEntry.ID?

    private var selectedEntry: DirectoryEntry? {
        selection.flatMap { root.find(id: $0) }
    }

    var body: some View {
        NavigationSplitView {
            DirectoryTreeView(root: root, selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            if let selectedEntry {
                EntryDetailView(entry: selectedEntry)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.left",
                    description: Text("Select an entry from the tree to view its attributes.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 420)
    }
}

#Preview {
    BrowserView()
}
