//
//  AutocompleteTextField.swift
//  ldap-studio
//

import SwiftUI

/// A plain `TextField` with an optional dropdown of matching suggestions —
/// purely a convenience. Nothing here ever stops the user from typing
/// anything else; suggestions only narrow as you type and are one click
/// away, never required. Uses `.popover` rather than a hand-positioned
/// overlay specifically so it isn't clipped when this field sits inside a
/// `List` row (a plain overlay would be).
struct AutocompleteTextField: View {
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]

    @FocusState private var isFocused: Bool
    @State private var isShowingSuggestions = false

    private var filteredSuggestions: [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? suggestions : suggestions.filter { $0.localizedCaseInsensitiveContains(query) }
        let lowerQuery = query.lowercased()
        return Array(
            matches
                .sorted { lhs, rhs in
                    let lhsPrefix = lhs.lowercased().hasPrefix(lowerQuery)
                    let rhsPrefix = rhs.lowercased().hasPrefix(lowerQuery)
                    if lhsPrefix != rhsPrefix { return lhsPrefix }
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                .prefix(8)
        )
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($isFocused)
            .onChange(of: text) { _, _ in updateVisibility() }
            .onChange(of: isFocused) { _, _ in updateVisibility() }
            .popover(isPresented: $isShowingSuggestions, arrowEdge: .bottom) {
                suggestionsList
            }
    }

    private func updateVisibility() {
        let hasTypedSomething = !text.trimmingCharacters(in: .whitespaces).isEmpty
        isShowingSuggestions = isFocused && hasTypedSomething && !filteredSuggestions.isEmpty
    }

    private var suggestionsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredSuggestions, id: \.self) { suggestion in
                    Button {
                        text = suggestion
                        isShowingSuggestions = false
                    } label: {
                        Text(suggestion)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 240, height: CGFloat(filteredSuggestions.count) * 24 + 8)
    }
}

#Preview {
    @Previewable @State var text = ""
    return AutocompleteTextField(
        placeholder: "Attribute",
        text: $text,
        suggestions: ["cn", "sn", "uid", "mail", "userPassword", "objectClass", "description"]
    )
    .padding()
    .frame(width: 300)
}
