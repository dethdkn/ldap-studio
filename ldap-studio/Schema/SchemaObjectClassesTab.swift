//
//  SchemaObjectClassesTab.swift
//  ldap-studio
//

import SwiftUI

struct SchemaObjectClassesTab: View {
    let objectClasses: [SchemaObjectClass]
    /// Set from outside ("Jump to Object Class" on an `objectClass`
    /// attribute row) to select and scroll to a class by name; cleared
    /// once applied.
    @Binding var jumpToObjectClassName: String?

    @State private var searchText = ""
    @State private var selection: String?

    private var sorted: [SchemaObjectClass] {
        objectClasses.sorted {
            ($0.names.first ?? $0.oid).localizedCaseInsensitiveCompare($1.names.first ?? $1.oid) == .orderedAscending
        }
    }

    private var filtered: [SchemaObjectClass] {
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            ($0.names.first ?? "").localizedCaseInsensitiveContains(searchText) || $0.oid.contains(searchText)
        }
    }

    private var selected: SchemaObjectClass? {
        objectClasses.first { $0.oid == selection }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)

                ScrollViewReader { proxy in
                    List(filtered, id: \.oid, selection: $selection) { objectClass in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(objectClass.names.first ?? objectClass.oid)
                            Text(objectClass.oid)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(objectClass.oid)
                    }
                    .onAppear { applyJump(proxy) }
                    .onChange(of: jumpToObjectClassName) { _, _ in applyJump(proxy) }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            if let selected {
                SchemaObjectClassDetail(objectClass: selected)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "square.stack.3d.up",
                    description: Text("Select an object class to view its details.")
                )
            }
        }
    }

    private func applyJump(_ proxy: ScrollViewProxy) {
        guard let name = jumpToObjectClassName else { return }
        searchText = ""
        guard let match = objectClasses.first(where: { objectClass in
            objectClass.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }) else {
            jumpToObjectClassName = nil
            return
        }
        selection = match.oid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation { proxy.scrollTo(match.oid, anchor: .center) }
        }
        jumpToObjectClassName = nil
    }
}

private struct SchemaObjectClassDetail: View {
    let objectClass: SchemaObjectClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(objectClass.names.first ?? objectClass.oid)
                        .font(.title2.bold())
                    Text(objectClass.oid)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if objectClass.names.count > 1 {
                    SchemaField(label: "Aliases", value: objectClass.names.dropFirst().joined(separator: ", "))
                }

                SchemaField(label: "Description", value: objectClass.description ?? "No description")
                SchemaField(label: "X-Origin", value: objectClass.xOrigin ?? "")
                SchemaField(label: "Superior Objectclass", value: objectClass.superiorClasses.joined(separator: ", "))
                SchemaField(label: "Kind", value: objectClass.kind)

                if objectClass.obsolete {
                    SchemaField(label: "Status", value: "Obsolete")
                }

                SchemaField(label: "Requires Attributes", value: objectClass.must.joined(separator: ", "))
                SchemaField(label: "Allowed Attributes", value: objectClass.may.joined(separator: ", "))

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw Definition")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(objectClass.raw)
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
    SchemaObjectClassesTab(objectClasses: [
        SchemaObjectClass(
            oid: "0.9.2342.19200300.100.4.5",
            names: ["account"],
            description: nil,
            obsolete: false,
            superiorClasses: ["top"],
            kind: "STRUCTURAL",
            must: ["uid"],
            may: ["description", "seeAlso", "l", "o", "ou", "host"],
            xOrigin: "RFC 4524",
            raw: "( 0.9.2342.19200300.100.4.5 NAME 'account' SUP top STRUCTURAL MUST uid MAY ( description $ seeAlso $ l $ o $ ou $ host ) X-ORIGIN 'RFC 4524' )"
        )
    ], jumpToObjectClassName: .constant(nil))
    .frame(width: 760, height: 520)
}
