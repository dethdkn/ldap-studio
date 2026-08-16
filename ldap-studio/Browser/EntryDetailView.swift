//
//  EntryDetailView.swift
//  ldap-studio
//

import AppKit
import SwiftUI

struct EntryDetailView: View {
    @Binding var entry: DirectoryEntry

    @State private var sortOrder = [KeyPathComparator(\Attribute.name)]
    @State private var selection: Attribute.ID?

    @State private var attributeBeingEdited: Attribute?
    @State private var editedValue = ""
    @State private var attributePendingDeletion: Attribute?

    private var sortedAttributes: [Attribute] {
        entry.attributes.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: entry.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.title2.bold())
                    Text(entry.dn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            Table(sortedAttributes, selection: $selection, sortOrder: $sortOrder) {
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
            .contextMenu(forSelectionType: Attribute.ID.self) { ids in
                if let id = ids.first, let attribute = entry.attributes.first(where: { $0.id == id }) {
                    contextMenuContent(for: attribute)
                }
            }
        }
        .alert(
            "Edit Value",
            isPresented: Binding(
                get: { attributeBeingEdited != nil },
                set: { if !$0 { attributeBeingEdited = nil } }
            ),
            presenting: attributeBeingEdited
        ) { attribute in
            TextField(attribute.name, text: $editedValue)
            Button("Save") {
                saveEdit(for: attribute)
                attributeBeingEdited = nil
            }
            Button("Cancel", role: .cancel) {
                attributeBeingEdited = nil
            }
        } message: { attribute in
            Text("Attribute: \(attribute.name)")
        }
        .alert(
            "Delete Value?",
            isPresented: Binding(
                get: { attributePendingDeletion != nil },
                set: { if !$0 { attributePendingDeletion = nil } }
            ),
            presenting: attributePendingDeletion
        ) { attribute in
            Button("Delete", role: .destructive) {
                deleteAttribute(attribute)
                attributePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                attributePendingDeletion = nil
            }
        } message: { attribute in
            Text("This removes \(attribute.name) = \(attribute.value) from this entry.")
        }
    }

    @ViewBuilder
    private func contextMenuContent(for attribute: Attribute) -> some View {
        Button {
            editedValue = attribute.value
            attributeBeingEdited = attribute
        } label: {
            Label("Edit Value", systemImage: "pencil")
        }
        .disabled(attribute.isBinary)

        Button(role: .destructive) {
            attributePendingDeletion = attribute
        } label: {
            Label("Delete Value", systemImage: "trash")
        }

        Divider()

        Button {
            copyToPasteboard("\(attribute.name): \(attribute.value)")
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            copyToPasteboard(attribute.name)
        } label: {
            Label("Copy Attribute", systemImage: "tag")
        }

        Button {
            copyToPasteboard(attribute.value)
        } label: {
            Label("Copy Value", systemImage: "doc.plaintext")
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func saveEdit(for attribute: Attribute) {
        guard let index = entry.attributes.firstIndex(where: { $0.id == attribute.id }) else { return }
        entry.attributes[index].value = editedValue
    }

    private func deleteAttribute(_ attribute: Attribute) {
        entry.attributes.removeAll { $0.id == attribute.id }
    }
}

#Preview {
    EntryDetailView(entry: .constant(.mockRoot))
        .frame(width: 500, height: 400)
}
