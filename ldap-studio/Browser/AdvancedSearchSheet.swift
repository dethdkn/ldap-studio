//
//  AdvancedSearchSheet.swift
//  ldap-studio
//

import SwiftUI

/// A real LDAP search — base DN, scope, and a raw RFC 4515 filter string,
/// evaluated by the server itself. The basic search field over the tree
/// only matches against dn text; this is for everything a filter can do
/// (attribute values, AND/OR/NOT, substrings, presence, …).
struct AdvancedSearchSheet: View {
    let connection: SavedConnection
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var baseDN: String
    @State private var scope: LdapSearchScope = .subtree
    @State private var filter = "(objectClass=*)"
    @State private var results: [LdapEntry] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false

    init(connection: SavedConnection, defaultBaseDN: String, onSelect: @escaping (String) -> Void) {
        self.connection = connection
        self.onSelect = onSelect
        _baseDN = State(initialValue: defaultBaseDN)
    }

    private var isValid: Bool {
        !baseDN.isEmpty && !filter.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Advanced Search")
                .font(.headline)
                .padding()

            Divider()

            Form {
                TextField("Base DN", text: $baseDN)
                Picker("Scope", selection: $scope) {
                    Text("Base").tag(LdapSearchScope.base)
                    Text("One Level").tag(LdapSearchScope.oneLevel)
                    Text("Subtree").tag(LdapSearchScope.subtree)
                }
                TextField("Filter", text: $filter)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(search)
            }
            .formStyle(.grouped)
            .frame(height: 150)

            Divider()

            HStack {
                Text("Attribute").font(.caption).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
                Text("dn").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            List(results, id: \.dn) { entry in
                Button {
                    onSelect(entry.dn)
                    dismiss()
                } label: {
                    HStack {
                        Text(entry.name)
                            .frame(width: 200, alignment: .leading)
                        Text(entry.dn)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if hasSearched && results.isEmpty && errorMessage == nil {
                    ContentUnavailableView.search
                }
            }

            Divider()

            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(2)
                } else {
                    Text(hasSearched ? "\(results.count) result\(results.count == 1 ? "" : "s")" : "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Search") {
                    search()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isSearching)
            }
            .padding()
        }
        .frame(width: 600, height: 520)
    }

    private func search() {
        guard isValid, !isSearching else { return }
        isSearching = true
        errorMessage = nil
        Task {
            defer {
                isSearching = false
                hasSearched = true
            }
            do {
                results = try await searchDirectory(
                    host: connection.host,
                    port: UInt16(clamping: connection.port),
                    useSsl: connection.useSSL,
                    bindDn: connection.bindDN,
                    password: KeychainService.readPassword(for: connection.id) ?? "",
                    baseDn: baseDN,
                    scope: scope,
                    filter: filter
                )
            } catch {
                errorMessage = "\(error)"
                results = []
            }
        }
    }
}

#Preview {
    AdvancedSearchSheet(
        connection: SavedConnection(name: "Preview", host: "localhost", port: 389, useSSL: false, baseDN: "dc=example,dc=com", bindDN: ""),
        defaultBaseDN: "dc=example,dc=com"
    ) { _ in }
}
