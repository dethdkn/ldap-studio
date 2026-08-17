//
//  NewEntrySheet.swift
//  ldap-studio
//

import SwiftUI

struct NewEntrySheet: View {
    let parentDN: String
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Entry")
                .font(.headline)
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Attributes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            rows.append(AttributeRow(name: "", value: ""))
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Add Attribute")
                    }

                    List {
                        ForEach($rows) { $row in
                            HStack {
                                TextField("Attribute", text: $row.name)
                                TextField("Value", text: $row.value)
                                Button {
                                    rows.removeAll { $0.id == row.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .disabled(rows.count <= 1)
                            }
                        }
                    }
                    .frame(minHeight: 160)
                }
            }
            .padding()

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
            .padding()
        }
        .frame(width: 480, height: 420)
    }
}

#Preview {
    NewEntrySheet(parentDN: "ou=People,dc=corp,dc=example,dc=com") { _, _ in }
}
