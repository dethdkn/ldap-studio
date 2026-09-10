//
//  GroupMembersSheet.swift
//  ldap-studio
//

import SwiftUI

/// Edits a group's membership — the `member` / `uniqueMember` multi-valued
/// DN attribute — without hand-typing DNs: current members are resolved to
/// display names, and new ones are found with a search field. Every add /
/// remove is a live LDAP modify; `onClose` refreshes the caller afterward.
struct GroupMembersSheet: View {
    let group: DirectoryEntry
    let connection: SavedConnection
    let onClose: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var attribute = "member"
    @State private var members: [Member] = []
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var error: String?

    @State private var searchText = ""
    @State private var searchResults: [Person] = []
    @State private var isSearching = false

    struct Member: Identifiable, Hashable {
        let dn: String
        var displayName: String?
        var id: String { dn }
        var resolved: Bool { displayName != nil }
        var label: String { displayName ?? GroupMembersSheet.rdnValue(of: dn) }
    }

    struct Person: Identifiable, Hashable {
        let dn: String
        let displayName: String
        var id: String { dn }
    }

    private var password: String {
        KeychainService.readPassword(for: connection.id) ?? ""
    }

    private var currentDNs: Set<String> { Set(members.map(\.dn)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Members of \(group.name)").font(.headline)
                    Text("\(attribute) — \(group.dn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding()

            Divider()

            addSection

            Divider()

            memberList

            Divider()

            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer()
                Button("Done") {
                    Task {
                        await onClose()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480, height: 540)
        .task { await loadMembers() }
        .task(id: searchText) { await runSearch() }
    }

    private var addSection: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search people to add…", text: $searchText)
                    .textFieldStyle(.plain)
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

            if !searchResults.isEmpty {
                List {
                    ForEach(searchResults) { person in
                        HStack {
                            personRow(person.displayName, person.dn)
                            Spacer()
                            Button("Add") { add(person) }
                                .disabled(isBusy || currentDNs.contains(person.dn))
                        }
                    }
                }
                .frame(height: 150)
                .listStyle(.bordered)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var memberList: some View {
        if isLoading {
            ProgressView("Resolving members…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if members.isEmpty {
            ContentUnavailableView("No Members", systemImage: "person.2.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section("\(members.count) member\(members.count == 1 ? "" : "s")") {
                    ForEach(members) { member in
                        HStack {
                            if !member.resolved {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("This DN didn't resolve — the entry may have been deleted.")
                            }
                            personRow(member.label, member.dn)
                            Spacer()
                            Button {
                                remove(member)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
    }

    private func personRow(_ name: String, _ dn: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
            Text(dn).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: - Data

    private func loadMembers() async {
        attribute = Self.membershipAttribute(for: group)
        let dns = group.attributes
            .filter { $0.name.caseInsensitiveCompare(attribute) == .orderedSame }
            .map(\.value)

        let resolved = await withTaskGroup(of: Member.self) { taskGroup -> [Member] in
            for dn in dns {
                taskGroup.addTask { await resolve(dn) }
            }
            var out: [Member] = []
            for await member in taskGroup { out.append(member) }
            return out
        }
        members = resolved.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        isLoading = false
    }

    private func resolve(_ dn: String) async -> Member {
        do {
            let hits = try await searchDirectory(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                baseDn: dn,
                scope: .base,
                filter: "(objectClass=*)"
            )
            let attrs = hits.first?.attributes ?? []
            func value(_ name: String) -> String? {
                attrs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
            }
            return Member(dn: dn, displayName: value("displayName") ?? value("cn") ?? value("uid"))
        } catch {
            return Member(dn: dn, displayName: nil)
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }

        isSearching = true
        defer { isSearching = false }

        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\5c")
            .replacingOccurrences(of: "*", with: "\\2a")
            .replacingOccurrences(of: "(", with: "\\28")
            .replacingOccurrences(of: ")", with: "\\29")
        let nameClauses = ["cn", "uid", "sn", "givenName", "displayName", "mail"]
            .map { "(\($0)=*\(escaped)*)" }.joined()
        let filter = "(&(|(objectClass=person)(objectClass=inetOrgPerson)(objectClass=posixAccount))(|\(nameClauses)))"

        do {
            let hits = try await searchDirectory(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                baseDn: connection.baseDN,
                scope: .subtree,
                filter: filter
            )
            if Task.isCancelled { return }
            searchResults = hits.prefix(50).map { hit in
                func value(_ name: String) -> String? {
                    hit.attributes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
                }
                return Person(dn: hit.dn,
                              displayName: value("displayName") ?? value("cn") ?? value("uid") ?? hit.name)
            }
        } catch {
            searchResults = []
        }
    }

    // MARK: - Writes

    private func add(_ person: Person) {
        write {
            try await addAttributeValue(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                dn: group.dn,
                attribute: attribute,
                value: person.dn
            )
            let member = Member(dn: person.dn, displayName: person.displayName)
            members.append(member)
            members.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            searchText = ""
            searchResults = []
        }
    }

    private func remove(_ member: Member) {
        write {
            try await deleteAttributeValue(
                host: connection.host,
                port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL,
                bindDn: connection.bindDN,
                password: password,
                dn: group.dn,
                attribute: attribute,
                value: member.dn,
                isBinary: false
            )
            members.removeAll { $0.dn == member.dn }
        }
    }

    private func write(_ operation: @escaping () async throws -> Void) {
        Task {
            isBusy = true
            error = nil
            defer { isBusy = false }
            do {
                try await operation()
            } catch {
                self.error = "\(error)"
            }
        }
    }

    // MARK: - Helpers

    /// A group whose membership this sheet can edit — recognised by
    /// objectClass or by already carrying a `member` / `uniqueMember`.
    static func isGroup(_ entry: DirectoryEntry) -> Bool {
        let groupClasses: Set = [
            "groupofnames", "groupofuniquenames", "groupofmembers",
            "groupofurls", "posixgroup", "group", "univentiongroup",
        ]
        let objectClasses = Set(
            entry.attributes
                .filter { $0.name.caseInsensitiveCompare("objectClass") == .orderedSame }
                .map { $0.value.lowercased() }
        )
        if !objectClasses.isDisjoint(with: groupClasses) { return true }
        return entry.attributes.contains {
            ["member", "uniquemember"].contains($0.name.lowercased())
        }
    }

    /// `member` unless the group only carries `uniqueMember` (or is a
    /// `groupOfUniqueNames`).
    static func membershipAttribute(for group: DirectoryEntry) -> String {
        let names = Set(group.attributes.map { $0.name.lowercased() })
        if names.contains("member") { return "member" }
        if names.contains("uniquemember") { return "uniqueMember" }
        let objectClasses = Set(
            group.attributes
                .filter { $0.name.caseInsensitiveCompare("objectClass") == .orderedSame }
                .map { $0.value.lowercased() }
        )
        return objectClasses.contains("groupofuniquenames") ? "uniqueMember" : "member"
    }

    static func rdnValue(of dn: String) -> String {
        guard let first = dn.split(separator: ",").first,
              let eq = first.firstIndex(of: "=") else { return dn }
        return String(first[first.index(after: eq)...])
    }
}

#Preview {
    GroupMembersSheet(
        group: DirectoryEntry(
            name: "cn=Admins",
            dn: "cn=Admins,ou=Groups,dc=corp,dc=example,dc=com",
            icon: "person.2.fill",
            attributes: [
                Attribute(name: "objectClass", value: "groupOfNames"),
                Attribute(name: "member", value: "cn=Alice Johnson,ou=People,dc=corp,dc=example,dc=com"),
            ],
            children: nil
        ),
        connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "dc=corp,dc=example,dc=com", bindDN: "")
    ) {}
}
