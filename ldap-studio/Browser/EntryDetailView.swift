//
//  EntryDetailView.swift
//  ldap-studio
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EntryDetailView: View {
    @Binding var entry: DirectoryEntry
    let root: DirectoryEntry
    let connection: SavedConnection
    /// Tells `BrowserView` to refetch the whole directory from the server —
    /// every write below goes straight to LDAP, so the tree is reloaded from
    /// there afterward instead of being patched locally. Pass the dn that
    /// should stay selected once the fresh tree comes back (`nil` if the
    /// entry no longer exists, e.g. after a delete).
    let reload: (String?) async -> Void

    @State private var sortOrder = [KeyPathComparator(\Attribute.name)]
    @State private var selection: Attribute.ID?
    @State private var searchText = ""

    @State private var attributeBeingEdited: Attribute?
    @State private var editedValue = ""
    @State private var attributePendingDeletion: Attribute?

    @State private var isShowingAddAttribute = false
    @State private var newAttributeName = ""
    @State private var newAttributeValue = ""

    @State private var isShowingMovePicker = false
    @State private var isShowingCopyPicker = false

    @State private var attributeBeingViewed: Attribute?

    @State private var attributeBeingPasswordSet: Attribute?
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    @State private var isPerformingAction = false
    @State private var actionError: String?

    private var password: String {
        KeychainService.readPassword(for: connection.id) ?? ""
    }

    private var actions: EntryActions {
        EntryActions(connection: connection)
    }

    private var filteredAttributes: [Attribute] {
        let sorted = entry.attributes.sorted(using: sortOrder)
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedAttribute: Attribute? {
        guard let selection else { return nil }
        return entry.attributes.first { $0.id == selection }
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
                if isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            Divider()

            toolbar

            Divider()

            Table(filteredAttributes, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Attribute", value: \.name)
                TableColumn("Value", sortUsing: KeyPathComparator(\.value)) { attribute in
                    Group {
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
                    .overlay(DoubleClickObserver { attributeBeingViewed = attribute })
                }
            }
            .contextMenu(forSelectionType: Attribute.ID.self) { ids in
                if let id = ids.first, let attribute = entry.attributes.first(where: { $0.id == id }) {
                    contextMenuContent(for: attribute)
                }
            }
        }
        .disabled(isPerformingAction)
        .sheet(item: $attributeBeingViewed) { attribute in
            AttributeValueDetailSheet(attribute: attribute)
        }
        .sheet(isPresented: $isShowingMovePicker) {
            if let pruned = root.pruned(removing: entry.id) {
                DestinationPickerSheet(root: pruned, title: "Move \(entry.name) To", confirmLabel: "Move") { destinationDN in
                    move(to: destinationDN)
                }
            }
        }
        .sheet(isPresented: $isShowingCopyPicker) {
            if let pruned = root.pruned(removing: entry.id) {
                DestinationPickerSheet(root: pruned, title: "Copy \(entry.name) To", confirmLabel: "Copy") { destinationDN in
                    copy(to: destinationDN)
                }
            }
        }
        .alert(
            "Add Attribute",
            isPresented: $isShowingAddAttribute
        ) {
            TextField("Attribute (e.g. mail)", text: $newAttributeName)
            TextField("Value", text: $newAttributeValue)
            Button("Add") { addAttribute() }
                .disabled(newAttributeName.isEmpty)
            Button("Cancel", role: .cancel) {}
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
            "Set Password",
            isPresented: Binding(
                get: { attributeBeingPasswordSet != nil },
                set: { if !$0 { attributeBeingPasswordSet = nil } }
            ),
            presenting: attributeBeingPasswordSet
        ) { attribute in
            SecureField("New Password", text: $newPassword)
            SecureField("Confirm Password", text: $confirmPassword)
            Button("Set") {
                savePassword(for: attribute)
                attributeBeingPasswordSet = nil
            }
            .disabled(newPassword.isEmpty || newPassword != confirmPassword)
            Button("Cancel", role: .cancel) {
                attributeBeingPasswordSet = nil
            }
        } message: { _ in
            Text("Hashed ({PBKDF2-SHA512}) before being sent — the plaintext is never stored.")
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
            Text("This removes \(attribute.name) = \(attribute.value) from this entry on the server.")
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                newAttributeName = ""
                newAttributeValue = ""
                isShowingAddAttribute = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Add Attribute")

            Button {
                beginEdit(selectedAttribute)
            } label: {
                Image(systemName: "pencil")
            }
            .help("Edit Attribute")
            .disabled(selectedAttribute == nil || selectedAttribute?.isBinary == true)

            Button {
                attributePendingDeletion = selectedAttribute
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete Attribute")
            .disabled(selectedAttribute == nil)

            Divider().frame(height: 16)

            Button {
                isShowingMovePicker = true
            } label: {
                Image(systemName: "arrow.turn.up.right")
            }
            .help("Move DN")

            Button {
                isShowingCopyPicker = true
            } label: {
                Image(systemName: "square.on.square")
            }
            .help("Copy DN")

            Button {
                actions.exportLDIF(entry)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export as LDIF")

            Divider().frame(height: 16)

            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Spacer()

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func contextMenuContent(for attribute: Attribute) -> some View {
        Button {
            attributeBeingViewed = attribute
        } label: {
            Label("View Value", systemImage: "eye")
        }

        Button {
            beginEdit(attribute)
        } label: {
            Label("Edit Value", systemImage: "pencil")
        }
        .disabled(attribute.isBinary)

        if attribute.name.caseInsensitiveCompare("jpegPhoto") == .orderedSame {
            Button {
                setPhoto(for: attribute)
            } label: {
                Label("Set Photo", systemImage: "photo")
            }
        }

        if attribute.name.caseInsensitiveCompare("userPassword") == .orderedSame {
            Button {
                newPassword = ""
                confirmPassword = ""
                attributeBeingPasswordSet = attribute
            } label: {
                Label("Set Password", systemImage: "key")
            }
        }

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

    private func beginEdit(_ attribute: Attribute?) {
        guard let attribute, !attribute.isBinary else { return }
        editedValue = attribute.value
        attributeBeingEdited = attribute
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Runs a write against the server, then refreshes the whole tree from
    /// it — simpler and safer than hand-patching local state, since it can
    /// never drift from what the server actually has.
    private func perform(reloadSelecting dn: String?, _ operation: @escaping () async throws -> Void) {
        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }
            do {
                try await operation()
                await reload(dn)
            } catch {
                actionError = "\(error)"
            }
        }
    }

    private func refresh() {
        let dn = entry.dn
        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }
            await reload(dn)
        }
    }

    private func addAttribute() {
        let dn = entry.dn
        let name = newAttributeName
        let value = newAttributeValue
        perform(reloadSelecting: dn) {
            try await addAttributeValue(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                dn: dn,
                attribute: name,
                value: value
            )
        }
    }

    private func saveEdit(for attribute: Attribute) {
        let dn = entry.dn
        let name = attribute.name
        let oldValue = attribute.value
        let newValue = editedValue
        perform(reloadSelecting: dn) {
            try await modifyAttributeValue(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                dn: dn,
                attribute: name,
                oldValue: oldValue,
                newValue: newValue,
                isBinary: false
            )
        }
    }

    private func savePassword(for attribute: Attribute) {
        let dn = entry.dn
        let name = attribute.name
        let oldValue = attribute.value
        let plaintext = newPassword
        newPassword = ""
        confirmPassword = ""
        perform(reloadSelecting: dn) {
            try await actions.setPassword(plaintext, replacing: oldValue, forDN: dn, attribute: name)
        }
    }

    private func setPhoto(for attribute: Attribute) {
        let dn = entry.dn
        let name = attribute.name
        let oldValue = attribute.value

        // Deferred to the next run loop tick so the context menu has fully
        // dismissed before a new panel is presented — same crash this app
        // already hit once with NSSavePanel from a context menu action.
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                perform(reloadSelecting: dn) {
                    try await actions.setPhoto(fileURL: url, replacing: oldValue, forDN: dn, attribute: name)
                }
            }
        }
    }

    private func deleteAttribute(_ attribute: Attribute) {
        let dn = entry.dn
        perform(reloadSelecting: dn) {
            try await deleteAttributeValue(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                dn: dn,
                attribute: attribute.name,
                value: attribute.value,
                isBinary: attribute.isBinary
            )
        }
    }

    private func move(to newSuperiorDN: String) {
        let entry = entry
        let newDN = "\(entry.name),\(newSuperiorDN)"
        perform(reloadSelecting: newDN) {
            _ = try await actions.move(entry, to: newSuperiorDN)
        }
    }

    private func copy(to newSuperiorDN: String) {
        let entry = entry
        let newRootDN = "\(entry.name),\(newSuperiorDN)"
        perform(reloadSelecting: newRootDN) {
            _ = try await actions.copy(entry, to: newSuperiorDN)
        }
    }
}

#Preview {
    EntryDetailView(
        entry: .constant(.mockRoot),
        root: .mockRoot,
        connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "", bindDN: ""),
        reload: { _ in }
    )
    .frame(width: 500, height: 400)
}
