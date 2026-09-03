//
//  AddAttributeSheet.swift
//  ldap-studio
//

import SwiftUI

/// A small form for adding one attribute — its own sheet rather than an
/// `.alert()` specifically so the attribute-name/value fields can carry
/// autocomplete: `.alert()` on macOS can only host `TextField`/`SecureField`/
/// `Button`, nothing with a popover attached.
struct AddAttributeSheet: View {
    let nameSuggestions: [String]
    let valueSuggestions: (String) -> [String]
    let onAdd: (_ name: String, _ value: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Attribute")
                .font(.headline)
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attribute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AutocompleteTextField(placeholder: "e.g. mail", text: $name, suggestions: nameSuggestions)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AutocompleteTextField(placeholder: "Value", text: $value, suggestions: valueSuggestions(name))
                        .textFieldStyle(.roundedBorder)
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

                Button("Add") {
                    onAdd(name.trimmingCharacters(in: .whitespaces), value.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 380)
    }
}

#Preview {
    AddAttributeSheet(
        nameSuggestions: ["cn", "sn", "mail", "objectClass"],
        valueSuggestions: { _ in [] }
    ) { _, _ in }
}
