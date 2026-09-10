//
//  RenameEntrySheet.swift
//  ldap-studio
//

import SwiftUI

/// Renames an entry's RDN — the leftmost `attr=value` of its dn. The parent
/// is untouched, so this is a rename, not a move. macOS has no F2, so this
/// is menu/right-click only.
struct RenameEntrySheet: View {
    let entry: DirectoryEntry
    let onRename: (_ newRDN: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var attribute: String
    @State private var value: String

    init(entry: DirectoryEntry, onRename: @escaping (_ newRDN: String) -> Void) {
        self.entry = entry
        self.onRename = onRename
        if let equals = entry.name.firstIndex(of: "=") {
            _attribute = State(initialValue: String(entry.name[..<equals]))
            _value = State(initialValue: String(entry.name[entry.name.index(after: equals)...]))
        } else {
            _attribute = State(initialValue: entry.name)
            _value = State(initialValue: "")
        }
    }

    private var newRDN: String {
        "\(attribute.trimmingCharacters(in: .whitespaces))=\(value.trimmingCharacters(in: .whitespaces))"
    }

    private var isValid: Bool {
        !attribute.trimmingCharacters(in: .whitespaces).isEmpty
            && !value.trimmingCharacters(in: .whitespaces).isEmpty
            && newRDN != entry.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rename Entry")
                .font(.headline)
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(entry.dn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    TextField("attribute", text: $attribute)
                        .frame(width: 120)
                    Text("=")
                        .foregroundStyle(.secondary)
                    TextField("value", text: $value)
                }
                .textFieldStyle(.roundedBorder)

                Text("Only the RDN changes; the entry keeps its place in the tree. The old RDN value is removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    onRename(newRDN)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 440)
    }
}
