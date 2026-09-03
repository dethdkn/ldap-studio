//
//  NewEntrySheet.swift
//  ldap-studio
//

import SwiftUI

struct NewEntrySheet: View {
    let parentDN: String
    /// Optional — feeds the attribute-name and objectClass-value
    /// autocomplete. `nil` just means no suggestions; every field stays
    /// fully free-typed either way.
    let schema: LdapSchema?
    let onCreate: (_ dn: String, _ attributes: [(name: String, value: String)]) -> Void

    @Environment(\.dismiss) private var dismiss

    private struct AttributeRow: Identifiable {
        let id = UUID()
        var name: String
        var value: String
    }

    @State private var rdn = ""
    @State private var rows: [AttributeRow] = [AttributeRow(name: "objectClass", value: "")]

    private var dn: String {
        "\(rdn),\(parentDN)"
    }

    private var attributes: [(name: String, value: String)] {
        rows
            .map { (name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.name.isEmpty && !$0.value.isEmpty }
    }

    private var isValid: Bool {
        !rdn.isEmpty && rdn.contains("=") && !attributes.isEmpty
    }

    /// The object class names already entered in the table so far — as the
    /// user builds up objectClass rows, attribute-name suggestions expand
    /// to match what those classes actually allow.
    private var currentObjectClassNames: [String] {
        rows
            .filter { $0.name.caseInsensitiveCompare("objectClass") == .orderedSame }
            .map { $0.value.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var attributeNameSuggestions: [String] {
        guard let schema else { return [] }
        var names = schema.allowedAttributeNames(forObjectClasses: currentObjectClassNames)
        if !names.contains(where: { $0.caseInsensitiveCompare("objectClass") == .orderedSame }) {
            names.insert("objectClass", at: 0)
        }
        return names
    }

    private func valueSuggestions(for attributeName: String) -> [String] {
        guard attributeName.caseInsensitiveCompare("objectClass") == .orderedSame else { return [] }
        return schema?.allObjectClassNames ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Entry")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Distinguished Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        TextField("cn=New Entry", text: $rdn)
                            .textFieldStyle(.plain)
                        Text(",\(parentDN)")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Attributes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            rows.append(AttributeRow(name: "", value: ""))
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Add Attribute")
                    }

                    List {
                        ForEach($rows) { $row in
                            HStack(spacing: 8) {
                                AutocompleteTextField(placeholder: "Attribute", text: $row.name, suggestions: attributeNameSuggestions)
                                    .textFieldStyle(.roundedBorder)
                                AutocompleteTextField(placeholder: "Value", text: $row.value, suggestions: valueSuggestions(for: row.name))
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    rows.removeAll { $0.id == row.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(rows.count <= 1)
                            }
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    onCreate(dn, attributes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 500, height: 400)
    }
}

#Preview {
    NewEntrySheet(parentDN: "ou=People,dc=corp,dc=example,dc=com", schema: nil) { _, _ in }
}
