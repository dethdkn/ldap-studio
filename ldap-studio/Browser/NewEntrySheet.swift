//
//  NewEntrySheet.swift
//  ldap-studio
//

import SwiftUI

struct NewEntrySheet: View {
    let parentDN: String
    /// Optional — powers the Guided mode and the Manual mode's
    /// autocomplete. `nil` forces Manual (every field free-typed).
    let schema: LdapSchema?
    let onCreate: (_ dn: String, _ attributes: [(name: String, value: String)]) -> Void

    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case guided = "Guided"
        case manual = "Manual"
        var id: String { rawValue }
    }

    @State private var mode: Mode

    // Manual mode
    private struct AttributeRow: Identifiable {
        let id = UUID()
        var name: String
        var value: String
    }
    @State private var rdn = ""
    @State private var rows: [AttributeRow] = [AttributeRow(name: "objectClass", value: "")]

    // Guided mode
    @State private var classes: [String] = []
    @State private var classToAdd = ""
    @State private var rdnAttribute = "cn"
    @State private var rdnValue = ""
    @State private var mustValues: [String: String] = [:]
    @State private var optionalRows: [AttributeRow] = []

    init(parentDN: String, schema: LdapSchema?,
         onCreate: @escaping (_ dn: String, _ attributes: [(name: String, value: String)]) -> Void) {
        self.parentDN = parentDN
        self.schema = schema
        self.onCreate = onCreate
        _mode = State(initialValue: schema == nil ? .manual : .guided)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Entry").font(.headline)
                Spacer()
                if schema != nil {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch mode {
                case .guided: guidedForm
                case .manual: manualForm
                }
            }

            Divider()

            HStack {
                if mode == .guided, !unfilledRequired.isEmpty {
                    Text("Missing: \(unfilledRequired.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let (dn, attrs) = mode == .guided ? guidedResult : (manualDN, manualAttributes)
                    onCreate(dn, attrs)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(mode == .guided ? !isGuidedValid : !isManualValid)
            }
            .padding(20)
        }
        .frame(width: 520, height: 460)
    }

    // MARK: - Guided

    private var required: LdapSchema.RequiredOptionalAttributes {
        schema?.requiredAndOptionalAttributes(forObjectClasses: classes)
            ?? .init(must: [], may: [])
    }

    /// MUST attributes the user still has to fill (objectClass and the RDN
    /// attribute are handled separately).
    private var requiredFields: [String] {
        required.must.filter {
            $0.caseInsensitiveCompare("objectClass") != .orderedSame
                && $0.caseInsensitiveCompare(rdnAttribute) != .orderedSame
        }
    }

    /// Suggestions for the RDN attribute field — the classes' MUST/MAY
    /// attributes plus the RFC 4519 naming attributes, so `l`, `dc`, `c`,
    /// `st`, … are all one keystroke away. The field itself accepts
    /// anything typed.
    private var rdnAttributeSuggestions: [String] {
        let naming = ["cn", "uid", "ou", "o", "dc", "l", "c", "st",
                      "sn", "givenName", "uidNumber", "serialNumber"]
        var seen = Set<String>()
        var out: [String] = []
        for name in required.must + naming + required.may
        where name.caseInsensitiveCompare("objectClass") != .orderedSame {
            if seen.insert(name.lowercased()).inserted { out.append(name) }
        }
        return out
    }

    private var guidedDN: String { "\(rdnAttribute)=\(rdnValue),\(parentDN)" }

    private var unfilledRequired: [String] {
        requiredFields.filter { (mustValues[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var isGuidedValid: Bool {
        !classes.isEmpty
            && !rdnAttribute.trimmingCharacters(in: .whitespaces).isEmpty
            && !rdnValue.trimmingCharacters(in: .whitespaces).isEmpty
            && unfilledRequired.isEmpty
    }

    private var guidedResult: (String, [(name: String, value: String)]) {
        var attrs: [(name: String, value: String)] = classes.map { (name: "objectClass", value: $0) }
        attrs.append((name: rdnAttribute.trimmingCharacters(in: .whitespaces),
                      value: rdnValue.trimmingCharacters(in: .whitespaces)))
        for name in requiredFields {
            let value = (mustValues[name] ?? "").trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { attrs.append((name: name, value: value)) }
        }
        for row in optionalRows {
            let name = row.name.trimmingCharacters(in: .whitespaces)
            let value = row.value.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !value.isEmpty { attrs.append((name: name, value: value)) }
        }
        return (guidedDN, attrs)
    }

    private var availableOptionalAttributes: [String] {
        let used = Set(optionalRows.map { $0.name.lowercased() } + [rdnAttribute.lowercased()])
        return required.may.filter { !used.contains($0.lowercased()) }
    }

    @ViewBuilder
    private var guidedForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Object classes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Object Classes").font(.caption).foregroundStyle(.secondary)
                    if !classes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(classes, id: \.self) { name in
                                    HStack(spacing: 4) {
                                        Text(name)
                                        Button {
                                            classes.removeAll { $0 == name }
                                        } label: { Image(systemName: "xmark.circle.fill") }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                }
                            }
                        }
                    }
                    HStack {
                        AutocompleteTextField(
                            placeholder: "Add a class (e.g. inetOrgPerson)…",
                            text: $classToAdd,
                            suggestions: (schema?.allObjectClassNames ?? []).filter { name in
                                !classes.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
                            }
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addClass)
                        Button("Add", action: addClass)
                            .disabled(classToAdd.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Pick the entry's structural class plus any auxiliary classes.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                if classes.isEmpty {
                    ContentUnavailableView(
                        "Choose object classes",
                        systemImage: "square.stack.3d.up",
                        description: Text("The form fills in once you add a class.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    // RDN
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Distinguished Name").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            AutocompleteTextField(
                                placeholder: "attr",
                                text: $rdnAttribute,
                                suggestions: rdnAttributeSuggestions
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            Text("=")
                            TextField("value", text: $rdnValue)
                                .textFieldStyle(.roundedBorder)
                            Text(",\(parentDN)").foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    // Required
                    if !requiredFields.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Required").font(.caption).foregroundStyle(.secondary)
                            ForEach(requiredFields, id: \.self) { name in
                                HStack {
                                    Text(name).frame(width: 150, alignment: .leading)
                                    TextField("value", text: Binding(
                                        get: { mustValues[name] ?? "" },
                                        set: { mustValues[name] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    // Optional
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Optional").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                ForEach(availableOptionalAttributes, id: \.self) { name in
                                    Button(name) { optionalRows.append(AttributeRow(name: name, value: "")) }
                                }
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .disabled(availableOptionalAttributes.isEmpty)
                        }
                        ForEach($optionalRows) { $row in
                            HStack {
                                Text(row.name).frame(width: 150, alignment: .leading)
                                TextField("value", text: $row.value)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    optionalRows.removeAll { $0.id == row.id }
                                } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func addClass() {
        let name = classToAdd.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              !classes.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            classToAdd = ""
            return
        }
        classes.append(name)
        classToAdd = ""
        // If the user hasn't touched the default `cn`, and this class set
        // doesn't actually allow `cn` as a MUST, switch to its first
        // required attribute (e.g. `ou` for an organizationalUnit).
        if rdnAttribute.caseInsensitiveCompare("cn") == .orderedSame {
            let musts = required.must.filter {
                $0.caseInsensitiveCompare("objectClass") != .orderedSame
            }
            if !musts.contains(where: { $0.caseInsensitiveCompare("cn") == .orderedSame }),
               let first = musts.first {
                rdnAttribute = first
            }
        }
    }

    // MARK: - Manual (unchanged behaviour)

    private var manualDN: String { "\(rdn),\(parentDN)" }

    private var manualAttributes: [(name: String, value: String)] {
        rows
            .map { (name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.name.isEmpty && !$0.value.isEmpty }
    }

    private var isManualValid: Bool {
        !rdn.isEmpty && rdn.contains("=") && !manualAttributes.isEmpty
    }

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

    private var manualForm: some View {
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
    }
}

#Preview("Manual") {
    NewEntrySheet(parentDN: "ou=People,dc=corp,dc=example,dc=com", schema: nil) { _, _ in }
}
