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
    /// Optional — feeds Add Attribute's autocomplete; nil just means no
    /// suggestions, never a blocker.
    let schema: LdapSchema?
    /// Whether this entry's DN is pinned, and the toggle — owned/persisted
    /// by `BrowserView`.
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void
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

    @State private var isShowingMovePicker = false
    @State private var isShowingCopyPicker = false
    @State private var isShowingGroupMembers = false

    @State private var attributeBeingViewed: Attribute?

    @State private var attributeBeingPasswordSet: Attribute?

    @State private var isPerformingAction = false
    @State private var actionError: String?

    @State private var showOperational = false
    @State private var operationalRows: [Attribute] = []
    @State private var isLoadingOperational = false

    private var password: String {
        KeychainService.readPassword(for: connection.id) ?? ""
    }

    private var actions: EntryActions {
        EntryActions(connection: connection)
    }

    /// User attributes from the tree, plus the operational ones fetched on
    /// demand when the toggle is on.
    private var allAttributes: [Attribute] {
        showOperational ? entry.attributes + operationalRows : entry.attributes
    }

    private var filteredAttributes: [Attribute] {
        // Operational attributes are always pinned above the user ones; the
        // table's column sort applies within each group.
        let sorted = allAttributes.sorted { lhs, rhs in
            if lhs.isOperational != rhs.isOperational { return lhs.isOperational }
            for comparator in sortOrder {
                switch comparator.compare(lhs, rhs) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedAttribute: Attribute? {
        guard let selection else { return nil }
        return allAttributes.first { $0.id == selection }
    }

    /// Re-fetch the entry's operational attributes whenever the toggle
    /// flips or the entry (or its user attributes) change.
    private var operationalFetchKey: String {
        "\(entry.dn)|\(showOperational)|\(entry.attributes.hashValue)"
    }

    private func loadOperational() async {
        guard showOperational, !entry.dn.isEmpty else {
            operationalRows = []
            return
        }
        isLoadingOperational = true
        defer { isLoadingOperational = false }
        do {
            let results = try await searchDirectory(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                startTLS: connection.useStartTLS,
                pinnedCertSHA256: connection.trustedCertSHA256,
                bindDn: connection.bindDN,
                password: password,
                baseDn: entry.dn,
                scope: .base,
                filter: "(objectClass=*)",
                includeOperational: true
            )
            let userNames = Set(entry.attributes.map { $0.name.lowercased() })
            operationalRows = (results.first?.attributes ?? [])
                .filter { !userNames.contains($0.name.lowercased()) }
                .map { Attribute(name: $0.name, value: $0.value, isBinary: $0.isBinary, isOperational: true) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            operationalRows = []
        }
    }

    /// This entry's current objectClass values — used to figure out which
    /// attribute names actually apply here.
    private var currentObjectClassNames: [String] {
        entry.attributes
            .filter { $0.name.caseInsensitiveCompare("objectClass") == .orderedSame }
            .map(\.value)
    }

    private var attributeNameSuggestions: [String] {
        schema?.allowedAttributeNames(forObjectClasses: currentObjectClassNames) ?? []
    }

    private var isGroup: Bool { GroupMembersSheet.isGroup(entry) }

    private func valueSuggestions(for attributeName: String) -> [String] {
        guard attributeName.caseInsensitiveCompare("objectClass") == .orderedSame else { return [] }
        return schema?.allObjectClassNames ?? []
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
                TableColumn("Attribute", value: \.name) { attribute in
                    HStack(spacing: 4) {
                        Text(attribute.name)
                        if attribute.isOperational {
                            Image(systemName: "lock")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Operational — maintained by the server, read-only")
                        }
                    }
                    .foregroundStyle(attribute.isOperational ? .secondary : .primary)
                }
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
                                .foregroundStyle(attribute.isOperational ? .secondary : .primary)
                        }
                    }
                    .overlay(DoubleClickObserver { attributeBeingViewed = attribute })
                }
            }
            .contextMenu(forSelectionType: Attribute.ID.self) { ids in
                if let id = ids.first, let attribute = allAttributes.first(where: { $0.id == id }) {
                    contextMenuContent(for: attribute)
                }
            }
        }
        .disabled(isPerformingAction)
        .task(id: operationalFetchKey) { await loadOperational() }
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
        .sheet(isPresented: $isShowingGroupMembers) {
            GroupMembersSheet(group: entry, connection: connection) {
                await reload(entry.dn)
            }
        }
        .sheet(isPresented: $isShowingAddAttribute) {
            AddAttributeSheet(nameSuggestions: attributeNameSuggestions, valueSuggestions: valueSuggestions) { name, value in
                addAttribute(name: name, value: value)
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
        .sheet(item: $attributeBeingPasswordSet) { attribute in
            SetPasswordSheet { plaintext, scheme in
                savePassword(plaintext, scheme: scheme, for: attribute)
            }
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
        .focusedSceneValue(\.entryDetailCommands, EntryDetailCommands(
            addAttribute: { isShowingAddAttribute = true },
            editAttribute: (selectedAttribute?.isBinary == false && selectedAttribute?.isOperational == false)
                ? { beginEdit(selectedAttribute) } : nil,
            deleteAttribute: selectedAttribute.flatMap { attribute in
                attribute.isOperational ? nil : { attributePendingDeletion = attribute }
            },
            moveDN: { isShowingMovePicker = true },
            copyDN: { isShowingCopyPicker = true },
            exportLDIF: { actions.exportLDIF(entry) },
            refresh: { refresh() },
            viewValue: selectedAttribute.map { attribute in { attributeBeingViewed = attribute } },
            copyFull: selectedAttribute.map { attribute in { copyToPasteboard("\(attribute.name): \(attribute.value)") } },
            copyAttributeName: selectedAttribute.map { attribute in { copyToPasteboard(attribute.name) } },
            copyValue: selectedAttribute.map { attribute in { copyToPasteboard(attribute.value) } },
            setPassword: selectedAttribute?.name.caseInsensitiveCompare("userPassword") == .orderedSame ? {
                attributeBeingPasswordSet = selectedAttribute
            } : nil,
            setPhoto: selectedAttribute?.name.caseInsensitiveCompare("jpegPhoto") == .orderedSame ? {
                if let selectedAttribute { setPhoto(for: selectedAttribute) }
            } : nil,
            toggleOperational: { showOperational.toggle() },
            showsOperational: showOperational
        ))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
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
            .disabled(selectedAttribute == nil || selectedAttribute?.isBinary == true
                || selectedAttribute?.isOperational == true)

            Button {
                attributePendingDeletion = selectedAttribute
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete Attribute")
            .disabled(selectedAttribute == nil || selectedAttribute?.isOperational == true)

            Divider().frame(height: 16)

            Button {
                isShowingMovePicker = true
            } label: {
                Image(systemName: "arrow.turn.up.right")
            }
            .help("Move to… (⇧⌘M)")

            Button {
                isShowingCopyPicker = true
            } label: {
                Image(systemName: "square.on.square")
            }
            .help("Copy to… (⇧⌘D)")

            Button {
                actions.exportLDIF(entry)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export as LDIF (⇧⌘X)")

            Button {
                onToggleBookmark()
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
            }
            .help(isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark This Entry (⌘D)")

            if isGroup {
                Button {
                    isShowingGroupMembers = true
                } label: {
                    Image(systemName: "person.2.badge.gearshape")
                }
                .help("Edit Members (⇧⌘U)")
            }

            Divider().frame(height: 16)

            Button {
                showOperational.toggle()
            } label: {
                Image(systemName: showOperational ? "clock.fill" : "clock")
            }
            .help("Operational Attributes (⌥⌘O)")
            .foregroundStyle(showOperational ? Color.accentColor : Color.primary)

            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh (⌘R)")

            if isLoadingOperational {
                ProgressView().controlSize(.small)
            }

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

        if !attribute.isOperational {
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
        guard let attribute, !attribute.isBinary, !attribute.isOperational else { return }
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

    private func addAttribute(name: String, value: String) {
        let dn = entry.dn
        perform(reloadSelecting: dn) {
            try await addAttributeValue(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                startTLS: connection.useStartTLS,
                pinnedCertSHA256: connection.trustedCertSHA256,
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
                startTLS: connection.useStartTLS,
                pinnedCertSHA256: connection.trustedCertSHA256,
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

    private func savePassword(_ plaintext: String, scheme: PasswordScheme, for attribute: Attribute) {
        let dn = entry.dn
        let name = attribute.name
        let oldValue = attribute.value
        perform(reloadSelecting: dn) {
            try await actions.setPassword(plaintext, scheme: scheme, replacing: oldValue, forDN: dn, attribute: name)
        }
    }

    private func setPhoto(for attribute: Attribute) {
        let dn = entry.dn
        let name = attribute.name

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
                    try await actions.setPhoto(fileURL: url, forDN: dn, attribute: name)
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
                startTLS: connection.useStartTLS,
                pinnedCertSHA256: connection.trustedCertSHA256,
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
        schema: nil,
        isBookmarked: false,
        onToggleBookmark: {},
        reload: { _ in }
    )
    .frame(width: 500, height: 400)
}
