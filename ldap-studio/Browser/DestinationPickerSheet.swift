//
//  DestinationPickerSheet.swift
//  ldap-studio
//

import SwiftUI

/// Lets the user pick a destination entry for a Move or Copy. Browses the
/// same lazily loaded tree as the main window — sharing what's already been
/// read, reading more as branches are expanded here — but keeps its own
/// expansion state. The entries being relocated (and everything under
/// them) can't be picked, since nothing can be moved or copied into itself.
struct DestinationPickerSheet: View {
    let tree: DirectoryTree
    let excluding: [String]
    let title: String
    let confirmLabel: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var expanded: Set<String> = []
    @State private var typedDN = ""

    private var destination: String? {
        let typed = typedDN.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? selection : typed
    }

    private var isExcluded: Bool {
        guard let destination else { return false }
        return excluding.contains { DN.isWithin(destination, $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding()

            Divider()

            List(selection: $selection) {
                if let root = tree.root {
                    PickerRow(node: root, tree: tree, excluding: excluding, expanded: $expanded)
                }
            }
            .onChange(of: selection) { _, newValue in
                if newValue != nil { typedDN = "" }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                TextField("Or type a destination DN", text: $typedDN)
                    .textFieldStyle(.roundedBorder)
                if isExcluded {
                    Text("An entry can't go inside itself or one of its descendants.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(confirmLabel) {
                        guard let destination else { return }
                        onConfirm(destination)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(destination == nil || isExcluded)
                }
            }
            .padding()
        }
        .frame(width: 460, height: 480)
        .onAppear {
            if let root = tree.root { expanded.insert(root.id) }
        }
    }
}

private struct PickerRow: View {
    let node: TreeNode
    let tree: DirectoryTree
    let excluding: [String]
    @Binding var expanded: Set<String>

    private var isExcluded: Bool {
        excluding.contains { DN.isWithin(node.dn, $0) }
    }

    var body: some View {
        if node.showsDisclosure && !isExcluded {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(node.id) },
                set: { isExpanded in
                    if isExpanded {
                        expanded.insert(node.id)
                        tree.ensureChildren(of: node)
                    } else {
                        expanded.remove(node.id)
                    }
                }
            )) {
                ForEach(node.visibleChildren) { child in
                    PickerRow(node: child, tree: tree, excluding: excluding, expanded: $expanded)
                }
                switch node.childrenState {
                case .notLoaded, .loading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                    // The main tree shares this node; if it collapsed the
                    // node mid-load, the load was dropped — start it again.
                    .onAppear { tree.ensureChildren(of: node) }
                    .onChange(of: node.childrenState) { _, state in
                        if state == .notLoaded { tree.ensureChildren(of: node) }
                    }
                case let .failed(message):
                    HStack(spacing: 6) {
                        Text(message).foregroundStyle(.secondary).lineLimit(1)
                        Button("Retry") { tree.retry(node) }.controlSize(.small)
                    }
                case .loaded:
                    if node.hiddenChildCount > 0 {
                        Button("Show \(min(TreeNode.displayStep, node.hiddenChildCount).formatted()) More") { tree.showMore(node) }
                            .controlSize(.small)
                    }
                }
            } label: {
                label
            }
        } else {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        if isExcluded {
            Label(node.name, systemImage: node.icon)
                .foregroundStyle(.tertiary)
        } else {
            Label(node.name, systemImage: node.icon)
                .tag(node.id)
        }
    }
}
