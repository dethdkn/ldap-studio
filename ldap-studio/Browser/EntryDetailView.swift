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
                TableColumn("Value", sortUsing: KeyPathComparator(\.value)) { attribute in
                    if let image = attribute.decodedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator, lineWidth: 1)
                            )
                            .padding(.vertical, 4)
                    } else if attribute.isBinary {
                        Text("<binary data>")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(attribute.value)
                    }
                }
            }
        }
    }
}

#Preview {
    EntryDetailView(entry: .mockRoot)
        .frame(width: 500, height: 400)
}
