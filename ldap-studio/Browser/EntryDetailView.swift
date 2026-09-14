//
//  EntryDetailView.swift
//  ldap-studio
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Fields are sourced from whichever password-policy convention the server
/// actually implements — OpenLDAP's ppolicy overlay (`pwdAccountLockedTime`,
/// `pwdChangedTime`, `pwdFailureTime`) or 389 Directory Server's own plugin
/// (`accountUnlockTime`, `passwordExpirationTime`, `passwordRetryCount`) —
/// so the card renders whatever is actually present, from either.
private struct PasswordPolicyStatus {
    var lockedAt: Date?
    var locksUntil: Date?
    var changedAt: Date?
    var expiresAt: Date?
    var failureCount: Int?
    var lastFailureAt: Date?
    var mustReset: Bool

    var isLocked: Bool { lockedAt != nil || locksUntil != nil }
}

private struct PasswordPolicyCard: View {
    let status: PasswordPolicyStatus

    /// Magnitude only ("1 mo", "3 days") — the phrasing ("since", "until",
    /// "ago") is composed by hand below, since `RelativeDateTimeFormatter`
    /// already bakes a direction word into its output and doubling up on it
    /// produces nonsense like "until in 1 mo".
    private static let magnitude: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter
    }()

    private static func magnitude(since date: Date) -> String {
        magnitude.string(from: abs(date.timeIntervalSinceNow)) ?? ""
    }

    var body: some View {
        HStack(spacing: 16) {
            labeled(
                status.isLocked ? "Locked" : "Not Locked",
                systemImage: status.isLocked ? "lock.fill" : "lock.open",
                tint: status.isLocked ? .red : .secondary,
                detail: status.lockedAt.map { "\(Self.magnitude(since: $0)) ago" }
                    ?? status.locksUntil.map { "unlocks in \(Self.magnitude(since: $0))" }
            )

            if let changedAt = status.changedAt {
                Divider().frame(height: 18)
                labeled(
                    "Changed",
                    systemImage: "clock.arrow.circlepath",
                    tint: .secondary,
                    detail: "\(Self.magnitude(since: changedAt)) ago"
                )
            }

            if let expiresAt = status.expiresAt {
                Divider().frame(height: 18)
                let expired = expiresAt < .now
                labeled(
                    expired ? "Expired" : "Expires",
                    systemImage: "hourglass",
                    tint: expired ? .red : .secondary,
                    detail: expired ? "\(Self.magnitude(since: expiresAt)) ago" : "in \(Self.magnitude(since: expiresAt))"
                )
            }

            if let failureCount = status.failureCount {
                Divider().frame(height: 18)
                labeled(
                    failureCount == 1 ? "1 Failed Attempt" : "\(failureCount) Failed Attempts",
                    systemImage: "exclamationmark.triangle",
                    tint: failureCount > 0 ? .orange : .secondary,
                    detail: status.lastFailureAt.map { "last \(Self.magnitude(since: $0)) ago" }
                )
            }

            if status.mustReset {
                Divider().frame(height: 18)
                labeled("Must Change Password", systemImage: "arrow.triangle.2.circlepath", tint: .orange, detail: nil)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func labeled(_ title: String, systemImage: String, tint: Color, detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.callout).foregroundStyle(tint)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

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

    @State private var passwordPolicyRows: [Attribute] = []

    /// Bumped by `refresh()` to force the operational/password-policy
    /// fetches below to re-run even when the entry's own DN and user
    /// attributes haven't changed — server-side-only values like
    /// `passwordExpirationTime` aren't reflected in `entry.attributes` at
    /// all, so nothing else would tell those `.task(id:)`s to restart.
    @State private var refreshToken = 0

    @Environment(\.openWindow) private var openWindow

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
        "\(entry.dn)|\(showOperational)|\(entry.attributes.hashValue)|\(refreshToken)"
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

    private var hasUserPassword: Bool {
        entry.attributes.contains { $0.name.caseInsensitiveCompare("userPassword") == .orderedSame }
    }

    /// Re-fetch the password-policy operational attributes whenever the
    /// entry (or its password) changes; only entries with a `userPassword`
    /// can carry them, so this stays a no-op for everything else.
    private var passwordPolicyFetchKey: String { "\(entry.dn)|\(hasUserPassword)|\(refreshToken)" }

    /// OpenLDAP's ppolicy overlay (`pwd*`) and 389 Directory Server's own
    /// password-policy plugin use entirely different attribute names for the
    /// same concepts — recognize both so the card works on either server.
    private static let passwordPolicyAttributeNames: Set<String> = [
        "pwdaccountlockedtime", "pwdchangedtime", "pwdfailuretime", "pwdreset",
        "accountunlocktime", "passwordexpirationtime", "passwordretrycount", "retrycountresettime",
    ]

    private func loadPasswordPolicy() async {
        guard hasUserPassword, !entry.dn.isEmpty else {
            passwordPolicyRows = []
            return
        }
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
            passwordPolicyRows = (results.first?.attributes ?? [])
                .filter { Self.passwordPolicyAttributeNames.contains($0.name.lowercased()) }
                .map { Attribute(name: $0.name, value: $0.value, isBinary: $0.isBinary, isOperational: true) }
        } catch {
            passwordPolicyRows = []
        }
    }

    private var passwordPolicyStatus: PasswordPolicyStatus? {
        guard !passwordPolicyRows.isEmpty else { return nil }
        func value(_ name: String) -> String? {
            passwordPolicyRows.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let lockedAt = value("pwdAccountLockedTime").flatMap { Self.parseGeneralizedTime($0) }
        let changedAt = value("pwdChangedTime").flatMap { Self.parseGeneralizedTime($0) }
        let failureTimes = passwordPolicyRows
            .filter { $0.name.caseInsensitiveCompare("pwdFailureTime") == .orderedSame }
            .compactMap { Self.parseGeneralizedTime($0.value) }
            .sorted(by: >)
        let mustReset = value("pwdReset")?.caseInsensitiveCompare("TRUE") == .orderedSame

        // 389 DS: an unlock time in the future means still locked; one in
        // the past (or the epoch sentinel it uses when never locked) reads
        // as not locked.
        let locksUntil = value("accountUnlockTime")
            .flatMap { Self.parseGeneralizedTime($0) }
            .flatMap { $0 > .now ? $0 : nil }
        let expiresAt = value("passwordExpirationTime").flatMap { Self.parseGeneralizedTime($0) }
        let retryCount = value("passwordRetryCount").flatMap(Int.init)
        let failureCount = failureTimes.isEmpty ? retryCount : failureTimes.count

        guard lockedAt != nil || locksUntil != nil || changedAt != nil || expiresAt != nil
            || failureCount != nil || mustReset else { return nil }

        return PasswordPolicyStatus(
            lockedAt: lockedAt,
            locksUntil: locksUntil,
            changedAt: changedAt,
            expiresAt: expiresAt,
            failureCount: failureCount,
            lastFailureAt: failureTimes.first,
            mustReset: mustReset
        )
    }

    /// LDAP GeneralizedTime, e.g. "20250911123456Z" — ppolicy attributes are
    /// always written in UTC with no fractional seconds.
    private static func parseGeneralizedTime(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return formatter.date(from: raw)
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

    private var isReadOnly: Bool { connection.isReadOnly }

    private func valueSuggestions(for attributeName: String) -> [String] {
        guard attributeName.caseInsensitiveCompare("objectClass") == .orderedSame else { return [] }
        return schema?.allObjectClassNames ?? []
    }

    private var entryPhoto: NSImage? {
        entry.attributes.first { $0.name.caseInsensitiveCompare("jpegPhoto") == .orderedSame }?.decodedImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let entryPhoto {
                    Image(nsImage: entryPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    Image(systemName: entry.icon)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                }
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

            if let status = passwordPolicyStatus {
                PasswordPolicyCard(status: status)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }

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
        .task(id: passwordPolicyFetchKey) { await loadPasswordPolicy() }
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
            editAttribute: (!isReadOnly && selectedAttribute?.isBinary == false && selectedAttribute?.isOperational == false)
                ? { beginEdit(selectedAttribute) } : nil,
            deleteAttribute: selectedAttribute.flatMap { attribute in
                (isReadOnly || attribute.isOperational) ? nil : { attributePendingDeletion = attribute }
            },
            moveDN: { isShowingMovePicker = true },
            copyDN: { isShowingCopyPicker = true },
            exportLDIF: { actions.exportLDIF(entry) },
            refresh: { refresh() },
            viewValue: selectedAttribute.map { attribute in { attributeBeingViewed = attribute } },
            jumpToSchema: selectedAttribute.map { attribute in { jumpToSchema(attribute) } },
            jumpToObjectClass: selectedAttribute.flatMap { attribute in
                attribute.name.caseInsensitiveCompare("objectClass") == .orderedSame
                    ? { jumpToObjectClass(attribute) } : nil
            },
            copyFull: selectedAttribute.map { attribute in { copyToPasteboard("\(attribute.name): \(attribute.value)") } },
            copyAttributeName: selectedAttribute.map { attribute in { copyToPasteboard(attribute.name) } },
            copyValue: selectedAttribute.map { attribute in { copyToPasteboard(attribute.value) } },
            setPassword: (!isReadOnly && selectedAttribute?.name.caseInsensitiveCompare("userPassword") == .orderedSame) ? {
                attributeBeingPasswordSet = selectedAttribute
            } : nil,
            setPhoto: (!isReadOnly && selectedAttribute?.name.caseInsensitiveCompare("jpegPhoto") == .orderedSame) ? {
                if let selectedAttribute { setPhoto(for: selectedAttribute) }
            } : nil,
            toggleOperational: { showOperational.toggle() },
            showsOperational: showOperational,
            isReadOnly: isReadOnly
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
            .disabled(isReadOnly)

            Button {
                beginEdit(selectedAttribute)
            } label: {
                Image(systemName: "pencil")
            }
            .help("Edit Attribute")
            .disabled(isReadOnly || selectedAttribute == nil || selectedAttribute?.isBinary == true
                || selectedAttribute?.isOperational == true)

            Button {
                attributePendingDeletion = selectedAttribute
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete Attribute")
            .disabled(isReadOnly || selectedAttribute == nil || selectedAttribute?.isOperational == true)

            Divider().frame(height: 16)

            Button {
                isShowingMovePicker = true
            } label: {
                Image(systemName: "arrow.turn.up.right")
            }
            .help("Move to… (⇧⌘M)")
            .disabled(isReadOnly)

            Button {
                isShowingCopyPicker = true
            } label: {
                Image(systemName: "square.on.square")
            }
            .help("Copy to… (⇧⌘D)")
            .disabled(isReadOnly)

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
                .disabled(isReadOnly)
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
        .keyboardShortcut("j", modifiers: .command)

        Button {
            jumpToSchema(attribute)
        } label: {
            Label("Jump to Schema", systemImage: "list.bullet.rectangle")
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button {
            jumpToObjectClass(attribute)
        } label: {
            Label("Jump to Object Class", systemImage: "square.stack.3d.up")
        }
        .keyboardShortcut("s", modifiers: [.command, .option])
        .disabled(attribute.name.caseInsensitiveCompare("objectClass") != .orderedSame)

        if !attribute.isOperational {
            Button {
                beginEdit(attribute)
            } label: {
                Label("Edit Value", systemImage: "pencil")
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(attribute.isBinary)

            if attribute.name.caseInsensitiveCompare("jpegPhoto") == .orderedSame {
                Button {
                    setPhoto(for: attribute)
                } label: {
                    Label("Set Photo", systemImage: "photo")
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }

            if attribute.name.caseInsensitiveCompare("userPassword") == .orderedSame {
                Button {
                    attributeBeingPasswordSet = attribute
                } label: {
                    Label("Set Password", systemImage: "key")
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }

            Button(role: .destructive) {
                attributePendingDeletion = attribute
            } label: {
                Label("Delete Value", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
        }

        Divider()

        Button {
            copyToPasteboard("\(attribute.name): \(attribute.value)")
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .keyboardShortcut("c", modifiers: .command)

        Button {
            copyToPasteboard(attribute.name)
        } label: {
            Label("Copy Attribute", systemImage: "tag")
        }
        .keyboardShortcut("c", modifiers: [.command, .option])

        Button {
            copyToPasteboard(attribute.value)
        } label: {
            Label("Copy Value", systemImage: "doc.plaintext")
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])
    }

    private func beginEdit(_ attribute: Attribute?) {
        guard let attribute, !attribute.isBinary, !attribute.isOperational else { return }
        editedValue = attribute.value
        attributeBeingEdited = attribute
    }

    /// Opens (or brings forward) the Schema window for this connection and
    /// selects `attribute`'s type on the Attributes tab.
    private func jumpToSchema(_ attribute: Attribute?) {
        guard let attribute else { return }
        let endpoint = "\(connection.host):\(UInt16(clamping: connection.port))"
        SchemaJumpCoordinator.shared.jump(toAttribute: attribute.name, endpoint: endpoint)
        openWindow(id: "schema", value: connection)
    }

    /// Same as `jumpToSchema`, but for an `objectClass` value row — jumps
    /// to that specific class (e.g. `inetOrgPerson`) on the Object Classes
    /// tab rather than to the `objectClass` attribute type itself.
    private func jumpToObjectClass(_ attribute: Attribute?) {
        guard let attribute, attribute.name.caseInsensitiveCompare("objectClass") == .orderedSame else { return }
        let endpoint = "\(connection.host):\(UInt16(clamping: connection.port))"
        SchemaJumpCoordinator.shared.jump(toObjectClass: attribute.value, endpoint: endpoint)
        openWindow(id: "schema", value: connection)
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
        refreshToken += 1
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
                readOnly: connection.isReadOnly,
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
                readOnly: connection.isReadOnly,
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
                readOnly: connection.isReadOnly,
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
