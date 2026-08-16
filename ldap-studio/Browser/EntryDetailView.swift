//
//  EntryDetailView.swift
//  ldap-studio
//

import SwiftUI

struct EntryDetailView: View {
    let entry: DirectoryEntry

    @State private var sortOrder = [KeyPathComparator(\Attribute.name)]

    private var sortedAttributes: [Attribute] {
        entry.attributes.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: entry.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                Text(entry.name)
                    .font(.title2.bold())
                Spacer()
            }
            .padding()

            Divider()

            Table(sortedAttributes, sortOrder: $sortOrder) {
                TableColumn("Attribute", value: \.name)
                TableColumn("Value", value: \.value)
            }
        }
    }
}

#Preview {
    EntryDetailView(entry: .mockRoot)
        .frame(width: 500, height: 400)
}
