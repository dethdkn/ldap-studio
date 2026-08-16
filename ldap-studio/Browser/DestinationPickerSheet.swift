//
//  DestinationPickerSheet.swift
//  ldap-studio
//

import SwiftUI

/// Lets the user pick a destination entry from the tree for a Move or Copy —
/// `root` should already have the entry being relocated (and its own
/// descendants) pruned out via `DirectoryEntry.pruned(removing:)`, since
/// nothing can be moved or copied into itself.
struct DestinationPickerSheet: View {
    let root: DirectoryEntry
    let title: String
    let confirmLabel: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: DirectoryEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding()

            Divider()

            List(selection: $selection) {
                OutlineGroup(root, children: \.children) { entry in
                    Label(entry.name, systemImage: entry.icon)
                        .tag(entry.id)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(confirmLabel) {
                    guard let selection else { return }
                    onConfirm(selection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil)
            }
            .padding()
        }
        .frame(width: 420, height: 420)
    }
}

#Preview {
    DestinationPickerSheet(root: .mockRoot, title: "Move To", confirmLabel: "Move") { _ in }
}
