//
//  LDAPFilterBuilder.swift
//  ldap-studio
//

import SwiftUI

enum LDAPFilterEditorMode: Hashable {
    case raw
    case builder
}

enum LDAPFilterJoin: String, CaseIterable, Identifiable {
    case and = "All (AND)"
    case or = "Any (OR)"

    var id: Self { self }
    var marker: Character { self == .and ? "&" : "|" }
}

enum LDAPFilterOperator: String, CaseIterable, Identifiable {
    case equals = "is"
    case contains = "contains"
    case beginsWith = "begins with"
    case endsWith = "ends with"
    case greaterOrEqual = "is ≥"
    case lessOrEqual = "is ≤"
    case approximately = "is approximately"
    case present = "is present"

    var id: Self { self }
    var needsValue: Bool { self != .present }
}

struct LDAPFilterClause: Identifiable, Hashable {
    var id = UUID()
    var attribute = "objectClass"
    var operation: LDAPFilterOperator = .present
    var value = ""
    var isNegated = false

    var filter: String? {
        let attribute = attribute.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attribute.isEmpty else { return nil }

        let escaped = Self.escape(value)
        let assertion: String
        switch operation {
        case .equals: assertion = "\(attribute)=\(escaped)"
        case .contains: assertion = "\(attribute)=*\(escaped)*"
        case .beginsWith: assertion = "\(attribute)=\(escaped)*"
        case .endsWith: assertion = "\(attribute)=*\(escaped)"
        case .greaterOrEqual: assertion = "\(attribute)>=\(escaped)"
        case .lessOrEqual: assertion = "\(attribute)<=\(escaped)"
        case .approximately: assertion = "\(attribute)~=\(escaped)"
        case .present: assertion = "\(attribute)=*"
        }

        let filter = "(\(assertion))"
        return isNegated ? "(!\(filter))" : filter
    }

    /// RFC 4515 requires these assertion-value bytes to be escaped. Keeping
    /// ordinary Unicode intact produces readable, valid UTF-8 filters.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\5c")
            .replacingOccurrences(of: "*", with: "\\2a")
            .replacingOccurrences(of: "(", with: "\\28")
            .replacingOccurrences(of: ")", with: "\\29")
            .replacingOccurrences(of: "\0", with: "\\00")
    }
}

struct LDAPFilterBuilder: View {
    @Binding var join: LDAPFilterJoin
    @Binding var clauses: [LDAPFilterClause]
    let attributeSuggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Match")
                    .foregroundStyle(.secondary)
                Picker("Match", selection: $join) {
                    ForEach(LDAPFilterJoin.allCases) { join in
                        Text(join.rawValue).tag(join)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Button("Add Rule", systemImage: "plus") {
                    clauses.append(LDAPFilterClause(attribute: "", operation: .equals))
                }
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($clauses) { $clause in
                        HStack(spacing: 8) {
                            Toggle("NOT", isOn: $clause.isNegated)
                                .toggleStyle(.checkbox)
                                .fixedSize()

                            AutocompleteTextField(
                                placeholder: "Attribute",
                                text: $clause.attribute,
                                suggestions: attributeSuggestions
                            )
                            .frame(minWidth: 150)

                            Picker("Operator", selection: $clause.operation) {
                                ForEach(LDAPFilterOperator.allCases) { operation in
                                    Text(operation.rawValue).tag(operation)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 145)

                            if clause.operation.needsValue {
                                TextField("Value", text: $clause.value)
                                    .frame(minWidth: 160)
                            } else {
                                Spacer(minLength: 160)
                            }

                            Button(role: .destructive) {
                                clauses.removeAll { $0.id == clause.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove Rule")
                            .disabled(clauses.count == 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}
