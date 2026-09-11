//
//  SchemaAttributesTab.swift
//  ldap-studio
//

import SwiftUI

struct SchemaAttributesTab: View {
    let objectClasses: [SchemaObjectClass]
    let attributeTypes: [SchemaAttributeType]
    /// Set from outside ("Jump to Schema" on an attribute row) to select
    /// and scroll to an attribute by name; cleared once applied.
    @Binding var jumpToAttributeName: String?

    @State private var searchText = ""
    @State private var objectClassFilter = "All"
    @State private var selection: String?

    private static let allFilter = "All"

    private var objectClassNames: [String] {
        [Self.allFilter] + objectClasses
            .compactMap { $0.names.first }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The attribute names (lowercased) allowed by the currently selected
    /// object class — its own MUST and MAY combined. `nil` means "no
    /// filter", i.e. the "All" choice.
    private var allowedAttributeNames: Set<String>? {
        guard objectClassFilter != Self.allFilter,
              let objectClass = objectClasses.first(where: { $0.names.first == objectClassFilter }) else { return nil }
        return Set((objectClass.must + objectClass.may).map { $0.lowercased() })
    }

    private var sorted: [SchemaAttributeType] {
        attributeTypes.sorted {
            ($0.names.first ?? $0.oid).localizedCaseInsensitiveCompare($1.names.first ?? $1.oid) == .orderedAscending
        }
    }

    private var filtered: [SchemaAttributeType] {
        var result = sorted
        if let allowedAttributeNames {
            result = result.filter { attribute in
                attribute.names.contains { allowedAttributeNames.contains($0.lowercased()) }
            }
        }
        guard !searchText.isEmpty else { return result }
        return result.filter {
            ($0.names.first ?? "").localizedCaseInsensitiveContains(searchText) || $0.oid.contains(searchText)
        }
    }

    private var selected: SchemaAttributeType? {
        attributeTypes.first { $0.oid == selection }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Object Class", selection: $objectClassFilter) {
                    ForEach(objectClassNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
            }
            .padding(8)

            ScrollViewReader { proxy in
                List(filtered, id: \.oid, selection: $selection) { attribute in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attribute.names.first ?? attribute.oid)
                        Text(attribute.oid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(attribute.oid)
                }
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView.search
                    }
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
                .onAppear { applyJump(proxy) }
                .onChange(of: jumpToAttributeName) { _, _ in applyJump(proxy) }
            }
        } detail: {
            if let selected {
                SchemaAttributeDetail(attribute: selected)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "list.bullet",
                    description: Text("Select an attribute to view its details.")
                )
            }
        }
    }

    private func applyJump(_ proxy: ScrollViewProxy) {
        guard let name = jumpToAttributeName else { return }
        // Clear any filter that could hide the match, then select + scroll.
        objectClassFilter = Self.allFilter
        searchText = ""
        guard let match = attributeTypes.first(where: { attribute in
            attribute.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }) else {
            jumpToAttributeName = nil
            return
        }
        selection = match.oid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation { proxy.scrollTo(match.oid, anchor: .center) }
        }
        jumpToAttributeName = nil
    }
}

private struct SchemaAttributeDetail: View {
    let attribute: SchemaAttributeType

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(attribute.names.first ?? attribute.oid)
                        .font(.title2.bold())
                    Text(attribute.oid)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let syntax = attribute.syntaxOid {
                        Text(syntax)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                SchemaField(label: "Description", value: attribute.description ?? "No description")
                SchemaField(label: "X-Origin", value: attribute.xOrigin ?? "")
                SchemaField(label: "Aliases", value: attribute.names.dropFirst().joined(separator: ", "))
                SchemaField(label: "Parent Attribute", value: attribute.superiorType ?? "")
                SchemaField(label: "Read Only", value: attribute.noUserModification ? "Yes" : "No")
                SchemaField(label: "Multivalued", value: attribute.singleValued ? "No" : "Yes")
                // RFC 4512: USAGE defaults to userApplications when the server omits it.
                SchemaField(label: "Usage", value: attribute.usage ?? "userApplications")

                if attribute.obsolete {
                    SchemaField(label: "Status", value: "Obsolete")
                }
                if attribute.collective {
                    SchemaField(label: "Collective", value: "Yes")
                }

                SchemaField(label: "Equality Matching Rules", value: attribute.equalityMatchingRule ?? "")
                SchemaField(label: "Substring Matching Rules", value: attribute.substringMatchingRule ?? "")
                SchemaField(label: "Ordering Matching Rules", value: attribute.orderingMatchingRule ?? "")

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw Definition")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(attribute.raw)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    SchemaAttributesTab(
        objectClasses: [],
        attributeTypes: [
            SchemaAttributeType(
                oid: "2.16.840.1.113730.3.1.55",
                names: ["aci"],
                description: "Netscape defined access control information attribute type",
                obsolete: false,
                superiorType: nil,
                equalityMatchingRule: nil,
                orderingMatchingRule: nil,
                substringMatchingRule: nil,
                syntaxOid: "1.3.6.1.4.1.1466.115.121.1.15",
                singleValued: false,
                collective: false,
                noUserModification: false,
                usage: "directoryOperation",
                xOrigin: "Netscape Directory Server",
                raw: "( 2.16.840.1.113730.3.1.55 NAME 'aci' DESC 'Netscape defined access control information attribute type' SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 USAGE directoryOperation X-ORIGIN 'Netscape Directory Server' )"
            )
        ],
        jumpToAttributeName: .constant(nil)
    )
    .frame(width: 760, height: 520)
}
