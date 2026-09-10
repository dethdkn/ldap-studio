//
//  EditEntryView.swift
//  ldap-studio
//
//  A dedicated window for restructuring one entry — object classes on the
//  left with a schema-driven picker, attributes on the right grouped and
//  marked required/optional from the schema. Save diffs the working copy
//  against what the server returned and issues the minimal set of writes.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What a "edit-entry" window is opened with.
struct EditEntryRequest: Codable, Hashable {
    let connection: SavedConnection
    let dn: String
}

extension Notification.Name {
    /// Posted after a successful write from a detached window (Edit Entry,
    /// LDIF editor, …) so an open browser on the same server can refresh.
    /// `userInfo`: `"dn"` (String), `"endpoint"` ("host:port").
    static let ldapEntryDidChange = Notification.Name("ldapEntryDidChange")
}

struct EditEntryView: View {
    let connection: SavedConnection
    let dn: String

    @State private var schema: LdapSchema?
    /// Exactly what the server returned, for diffing on save.
    @State private var loadedAttributes: [LdapAttribute] = []
    @State private var originalObjectClasses: [String] = []

    @State private var objectClasses: [String] = []
    @State private var groups: [AttrGroup] = []
    @State private var classToAdd = ""
    @State private var attrToAdd = ""

    @State private var isLoading = true
    @State private var isBusy = false
    @State private var loadError: String?
    @State private var status: String?
    @State private var results: [String] = []

    @State private var passwordSheet = false

    private var password: String { KeychainService.readPassword(for: connection.id) ?? "" }
    private var actions: EntryActions { EntryActions(connection: connection) }

    struct AttrGroup: Identifiable {
        let id = UUID()
        var name: String
        var values: [Value]
        struct Value: Identifiable {
            let id = UUID()
            var text: String
            var isBinary: Bool
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Load Entry", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if isLoading {
                ProgressView("Loading \(rdn)…")
            } else {
                editor
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .navigationTitle("Edit \(rdn)\(connection.isReadOnly ? "  (Read-Only)" : "")")
        .task { await load() }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await load() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
                .help("Reload from the server, discarding unsaved edits")

                Button { revert() } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .disabled(isBusy || !hasChanges)
                .help("Undo all edits and return to the loaded values")

                Button { Task { await save() } } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(connection.isReadOnly || isBusy || !hasChanges || !missingRequired.isEmpty)
                .help("Apply every change to the server")
            }
        }
        .sheet(isPresented: $passwordSheet) {
            SetPasswordSheet { plaintext, scheme in
                Task { await runPassword(plaintext, scheme) }
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HSplitView {
                objectClassPane
                    .frame(minWidth: 210, idealWidth: 250, maxWidth: 340)
                attributesPane
                    .frame(minWidth: 440)
            }
            statusBar
        }
    }

    // MARK: - Object classes

    private var objectClassPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Object Classes", systemImage: "shippingbox")
                .font(.headline)
                .padding(12)

            Divider()

            List {
                ForEach(objectClasses, id: \.self) { name in
                    HStack {
                        Image(systemName: "cube")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(name)
                        Spacer()
                        Button {
                            removeClass(name)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .opacity(name.caseInsensitiveCompare("top") == .orderedSame ? 0.3 : 1)
                        .disabled(name.caseInsensitiveCompare("top") == .orderedSame)
                        .help("Remove this object class (and any attributes it alone allowed)")
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            HStack(spacing: 6) {
                AutocompleteTextField(placeholder: "add class", text: $classToAdd,
                                      suggestions: classSuggestions)
                Button("Add") { addClass() }
                    .disabled(classToAdd.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Add this object class")
            }
            .padding(8)
        }
    }

    private func addClass() {
        let name = classToAdd.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              !objectClasses.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        objectClasses.append(name)
        classToAdd = ""
    }

    /// Removing a class also drops any attribute that only that class (or an
    /// ancestor it brought in) allowed — otherwise the entry would fail
    /// schema validation on save with an orphaned attribute.
    private func removeClass(_ name: String) {
        guard let schema else {
            objectClasses.removeAll { $0 == name }
            return
        }
        let before = Set(schema.allowedAttributeNames(forObjectClasses: objectClasses).map { $0.lowercased() })
        objectClasses.removeAll { $0 == name }
        let after = Set(schema.allowedAttributeNames(forObjectClasses: objectClasses).map { $0.lowercased() })
        let orphaned = before.subtracting(after)
        guard !orphaned.isEmpty else { return }

        let dropped = groups.filter { orphaned.contains($0.name.lowercased()) }.map(\.name)
        groups.removeAll { orphaned.contains($0.name.lowercased()) }
        if !dropped.isEmpty {
            status = "Removed \(dropped.count) attribute\(dropped.count == 1 ? "" : "s") no longer allowed: \(dropped.joined(separator: ", "))"
        }
    }

    // MARK: - Attributes

    private var attributesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dnCard

                ForEach($groups) { $group in
                    attributeSection($group)
                }

                addAttributeControl
            }
            .padding(16)
        }
    }

    private var dnCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("RDN").font(.caption).foregroundStyle(.secondary)
                Text(rdn).font(.callout.monospaced())
            }
            HStack(spacing: 6) {
                Text("in").font(.caption).foregroundStyle(.secondary)
                Text(parentDN).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func attributeSection(_ group: Binding<AttrGroup>) -> some View {
        let required = isRequired(group.wrappedValue.name)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(group.wrappedValue.name)
                    .font(.subheadline.weight(.semibold))
                if required {
                    Text("required")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
                Spacer()
                Button {
                    group.wrappedValue.values.append(.init(text: "", isBinary: false))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add another value")

                if !required {
                    Button {
                        groups.removeAll { $0.id == group.wrappedValue.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this attribute")
                }
            }

            ForEach(group.values) { $value in
                HStack(spacing: 6) {
                    if value.isBinary {
                        Text("‹binary value›")
                            .font(.callout).italic()
                            .foregroundStyle(.secondary)
                        if group.wrappedValue.name.caseInsensitiveCompare("userPassword") == .orderedSame {
                            Button("Set Password…") { passwordSheet = true }
                                .controlSize(.small)
                                .disabled(connection.isReadOnly)
                        } else if group.wrappedValue.name.caseInsensitiveCompare("jpegPhoto") == .orderedSame {
                            Button("Set Photo…") { choosePhoto() }
                                .controlSize(.small)
                                .disabled(connection.isReadOnly)
                        }
                        Spacer()
                    } else {
                        TextField(group.wrappedValue.name, text: $value.text)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    if group.wrappedValue.values.count > 1 {
                        Button {
                            group.wrappedValue.values.removeAll { $0.id == value.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove this value")
                    }
                }
            }
        }
    }

    private var addAttributeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            AutocompleteTextField(placeholder: "add attribute", text: $attrToAdd,
                                  suggestions: attributeSuggestions)
            Button("Add") { addAttribute() }
                .disabled(attrToAdd.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Add this attribute")
        }
        .padding(.top, 4)
    }

    private func addAttribute() {
        let name = attrToAdd.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              name.caseInsensitiveCompare("objectClass") != .orderedSame,
              !groups.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        groups.append(AttrGroup(name: name, values: [.init(text: "", isBinary: false)]))
        attrToAdd = ""
    }

    // MARK: - Status

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if isBusy { ProgressView().controlSize(.small) }
                if !missingRequired.isEmpty {
                    Label("Needs a value: \(missingRequired.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                } else if connection.isReadOnly {
                    Label("Read-only connection — Save is disabled", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                } else if hasChanges {
                    Text("\(pendingWrites().count) unsaved change\(pendingWrites().count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !results.isEmpty {
                    Text(results.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Derived

    private var rdn: String { String(dn.split(separator: ",").first ?? Substring(dn)) }
    private var parentDN: String {
        dn.contains(",") ? String(dn.drop(while: { $0 != "," }).dropFirst()) : ""
    }

    private var mustNames: Set<String> {
        guard let schema else { return [] }
        return Set(schema.requiredAndOptionalAttributes(forObjectClasses: objectClasses).must
            .filter { $0.caseInsensitiveCompare("objectClass") != .orderedSame }
            .map { $0.lowercased() })
    }

    private func isRequired(_ name: String) -> Bool { mustNames.contains(name.lowercased()) }

    private var missingRequired: [String] {
        mustNames.compactMap { lname in
            let has = groups.first { $0.name.lowercased() == lname }?.values
                .contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && !$0.isBinary } ?? false
            guard !has else { return nil }
            return groups.first { $0.name.lowercased() == lname }?.name ?? lname
        }
    }

    private var classSuggestions: [String] {
        guard let schema else { return [] }
        let have = Set(objectClasses.map { $0.lowercased() })
        return schema.allObjectClassNames.filter { !have.contains($0.lowercased()) }
    }

    private var attributeSuggestions: [String] {
        guard let schema else { return [] }
        let present = Set(groups.map { $0.name.lowercased() } + ["objectclass"])
        return schema.allowedAttributeNames(forObjectClasses: objectClasses)
            .filter { !present.contains($0.lowercased()) }
    }

    // MARK: - Load / revert

    private func load() async {
        isLoading = (loadedAttributes.isEmpty)
        loadError = nil
        results = []
        do {
            async let entryTask = searchDirectory(
                host: connection.host, port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL, startTLS: connection.useStartTLS,
                pinnedCertSHA256: connection.trustedCertSHA256,
                bindDn: connection.bindDN, password: password,
                baseDn: dn, scope: .base, filter: "(objectClass=*)"
            )
            async let schemaTask: LdapSchema? = try? await fetchSchema(
                host: connection.host, port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL, startTLS: connection.useStartTLS,
                pinnedCertSHA256: connection.trustedCertSHA256,
                bindDn: connection.bindDN, password: password
            )
            guard let entry = try await entryTask.first else {
                loadError = "The entry was not found."
                isLoading = false
                return
            }
            schema = await schemaTask
            loadedAttributes = entry.attributes
            applyLoaded()
            status = nil
        } catch {
            loadError = "\(error)"
        }
        isLoading = false
    }

    private func applyLoaded() {
        originalObjectClasses = loadedAttributes
            .filter { $0.name.caseInsensitiveCompare("objectClass") == .orderedSame }
            .map(\.value)
        objectClasses = orderedObjectClasses(originalObjectClasses)

        let others = loadedAttributes.filter { $0.name.caseInsensitiveCompare("objectClass") != .orderedSame }
        var byName: [String: AttrGroup] = [:]
        var order: [String] = []
        for attr in others {
            let key = attr.name.lowercased()
            if byName[key] == nil {
                byName[key] = AttrGroup(name: attr.name, values: [])
                order.append(key)
            }
            byName[key]?.values.append(.init(text: attr.value, isBinary: attr.isBinary))
        }
        // MUST first, then alphabetical.
        groups = order.map { byName[$0]! }.sorted { lhs, rhs in
            let lReq = isRequired(lhs.name), rReq = isRequired(rhs.name)
            if lReq != rReq { return lReq }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// `top` last, structural-ish first — cosmetic only.
    private func orderedObjectClasses(_ names: [String]) -> [String] {
        names.sorted { lhs, rhs in
            let lTop = lhs.caseInsensitiveCompare("top") == .orderedSame
            let rTop = rhs.caseInsensitiveCompare("top") == .orderedSame
            if lTop != rTop { return rTop }
            return false
        }
    }

    private func revert() { applyLoaded() }

    // MARK: - Diff / save

    private var hasChanges: Bool { !pendingWrites().isEmpty }

    private struct Write { let label: String; let run: () async throws -> Void }

    private func pendingWrites() -> [Write] {
        var writes: [Write] = []
        let host = connection.host
        let port = UInt16(clamping: connection.port)
        let ssl = connection.useSSL
        let sTLS = connection.useStartTLS
        let pin = connection.trustedCertSHA256
        let ro = connection.isReadOnly
        let bind = connection.bindDN
        let pw = password
        let target = dn

        func add(_ attr: String, _ value: String) {
            writes.append(Write(label: "+\(attr)") {
                try await addAttributeValue(host: host, port: port, useSsl: ssl, readOnly: ro,
                                            startTLS: sTLS, pinnedCertSHA256: pin,
                                            bindDn: bind, password: pw, dn: target,
                                            attribute: attr, value: value)
            })
        }
        func remove(_ attr: String, _ value: String) {
            writes.append(Write(label: "−\(attr)") {
                try await deleteAttributeValue(host: host, port: port, useSsl: ssl, readOnly: ro,
                                               startTLS: sTLS, pinnedCertSHA256: pin,
                                               bindDn: bind, password: pw, dn: target,
                                               attribute: attr, value: value, isBinary: false)
            })
        }

        // Object classes — adds before removes so a structural swap is legal.
        let currentOC = objectClasses
        let origOC = originalObjectClasses
        for oc in currentOC where !origOC.contains(where: { $0.caseInsensitiveCompare(oc) == .orderedSame }) {
            add("objectClass", oc)
        }
        for oc in origOC where !currentOC.contains(where: { $0.caseInsensitiveCompare(oc) == .orderedSame }) {
            remove("objectClass", oc)
        }

        // Text attributes — binary values are never diffed here (Set Photo /
        // Set Password handle those out of band).
        let origText = Dictionary(grouping: loadedAttributes.filter {
            !$0.isBinary && $0.name.caseInsensitiveCompare("objectClass") != .orderedSame
        }) { $0.name.lowercased() }

        var names = Set(groups.map { $0.name.lowercased() })
        names.formUnion(origText.keys)

        for lname in names {
            let group = groups.first { $0.name.lowercased() == lname }
            let display = group?.name ?? origText[lname]?.first?.name ?? lname
            let current = Set((group?.values ?? [])
                .filter { !$0.isBinary }
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
            let original = Set((origText[lname] ?? []).map(\.value))
            for v in current.subtracting(original) { add(display, v) }
            for v in original.subtracting(current) { remove(display, v) }
        }

        return writes
    }

    private func save() async {
        let writes = pendingWrites()
        guard !writes.isEmpty else { return }
        isBusy = true
        status = nil
        results = []
        var failures = 0
        for write in writes {
            do {
                try await write.run()
            } catch {
                failures += 1
                results.append("\(write.label): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            }
        }
        isBusy = false
        if failures == 0 {
            status = "Saved \(writes.count) change\(writes.count == 1 ? "" : "s")."
            NotificationCenter.default.post(
                name: .ldapEntryDidChange, object: nil,
                userInfo: ["dn": dn, "endpoint": endpoint])
            await load()
        } else {
            status = "\(writes.count - failures) of \(writes.count) applied · \(failures) failed"
        }
    }

    private var endpoint: String {
        "\(connection.host):\(UInt16(clamping: connection.port))"
    }

    // MARK: - Password / photo

    private func runPassword(_ plaintext: String, _ scheme: PasswordScheme) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await actions.setPassword(plaintext, scheme: scheme, forDN: dn)
            status = "Password updated."
            NotificationCenter.default.post(name: .ldapEntryDidChange, object: nil,
                                           userInfo: ["dn": dn, "endpoint": endpoint])
            await load()
        } catch {
            status = "Password: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        DispatchQueue.main.async {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task {
                    isBusy = true
                    defer { isBusy = false }
                    do {
                        try await actions.setPhoto(fileURL: url, forDN: dn, attribute: "jpegPhoto")
                        status = "Photo updated."
                        NotificationCenter.default.post(name: .ldapEntryDidChange, object: nil,
                                                       userInfo: ["dn": dn, "endpoint": endpoint])
                        await load()
                    } catch {
                        status = "Photo: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
                    }
                }
            }
        }
    }
}
