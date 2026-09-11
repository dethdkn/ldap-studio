//
//  ServerInfoView.swift
//  ldap-studio
//
//  "What server is this and what can it do" — a single base-scope read of
//  the Root DSE (RFC 4512 §5.1), requesting operational attributes so
//  supportedControl / supportedExtension / supportedSASLMechanisms etc.
//  actually come back. OID lists are annotated with the common/registered
//  meanings we're confident about; anything unrecognized just shows the
//  raw OID rather than guessing.
//

import AppKit
import SwiftUI

struct ServerInfoView: View {
    let connection: SavedConnection

    @State private var attributes: [LdapAttribute] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private var password: String { KeychainService.readPassword(for: connection.id) ?? "" }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Read Server Info", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if isLoading {
                ProgressView("Reading Root DSE…")
            } else {
                content
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .navigationTitle("Server Info — \(connection.name)")
        .task { await load() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help("Refresh (⌘R)")
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    copyAsText()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(attributes.isEmpty)
                .help("Copy everything as plain text")
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                if !namingContexts.isEmpty {
                    section("Naming Contexts", icon: "folder", count: namingContexts.count) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(namingContexts, id: \.self) { dn in
                                Text(dn).font(.callout.monospaced())
                            }
                        }
                    }
                }

                if !saslMechs.isEmpty {
                    section("SASL Mechanisms", icon: "lock.shield", count: saslMechs.count) {
                        pillGrid(saslMechs)
                    }
                }

                if !extensions.isEmpty {
                    section("Supported Extensions", icon: "puzzlepiece.extension", count: extensions.count) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(extensions, id: \.self) { oid in
                                oidRow(oid, known: Self.knownExtensions)
                            }
                        }
                    }
                }

                if !controls.isEmpty {
                    section("Supported Controls", icon: "slider.horizontal.3", count: controls.count) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(controls, id: \.self) { oid in
                                oidRow(oid, known: Self.knownControls)
                            }
                        }
                    }
                }

                if !features.isEmpty {
                    section("Supported Features", icon: "star", count: features.count) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(features, id: \.self) { oid in
                                oidRow(oid, known: Self.knownFeatures)
                            }
                        }
                    }
                }

                if !altServers.isEmpty {
                    section("Alternate Servers", icon: "arrow.triangle.branch") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(altServers, id: \.self) { Text($0).font(.callout.monospaced()) }
                        }
                    }
                }

                if !otherGroups.isEmpty {
                    section("Other", icon: "ellipsis.circle", count: otherGroups.count) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(otherGroups) { group in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(group.name)
                                        .font(.callout.weight(.medium))
                                        .frame(width: 170, alignment: .leading)
                                    Text(group.values.joined(separator: ", "))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .textSelection(.enabled)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name).font(.title2.bold())
                    Text("\(connection.host):\(connection.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 24) {
                if let vendorName {
                    labeled("Vendor", [vendorName, vendorVersion].compactMap { $0 }.joined(separator: " "))
                }
                if !ldapVersions.isEmpty {
                    labeled("LDAP Version", ldapVersions.joined(separator: ", "))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, icon: String, count: Int? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title).font(.headline)
                if let count {
                    Text("\(count)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            content()
        }
    }

    private func oidRow(_ oid: String, known: [String: String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let name = known[oid] {
                Text(name).font(.callout)
                Text(oid).font(.caption2.monospaced()).foregroundStyle(.secondary)
            } else {
                Text(oid).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    /// A `LazyVGrid` forces every pill in a row into the same column width,
    /// so "GSS-SPNEGO" / "ANONYMOUS" wrapped inside their cell instead of
    /// just taking more room. `FlowLayout` sizes each pill to its own text
    /// and only wraps whole pills to the next line.
    private func pillGrid(_ items: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .fixedSize()
            }
        }
    }

    // MARK: - Parsed fields

    private func values(_ name: String) -> [String] {
        attributes.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }

    private var namingContexts: [String] { values("namingContexts") }
    private var saslMechs: [String] { values("supportedSASLMechanisms") }
    private var extensions: [String] { values("supportedExtension") }
    private var controls: [String] { values("supportedControl") }
    private var features: [String] { values("supportedFeatures") }
    private var altServers: [String] { values("altServer") }
    private var ldapVersions: [String] { values("supportedLDAPVersion") }
    private var vendorName: String? { values("vendorName").first }
    private var vendorVersion: String? { values("vendorVersion").first }

    private struct NamedValues: Identifiable {
        let name: String
        let values: [String]
        var id: String { name }
    }

    /// Everything the Root DSE returned that isn't one of the fields above
    /// — server-specific extras (OpenLDAP's `configContext`, 389-ds's
    /// `nsBackendSuffix`, AD's `rootDomainNamingContext`, …).
    private var otherGroups: [NamedValues] {
        let handled: Set<String> = [
            "namingcontexts", "supportedcontrol", "supportedextension",
            "supportedsaslmechanisms", "availablesaslmechanisms", "vendorname",
            "vendorversion", "supportedldapversion", "subschemasubentry",
            "supportedfeatures", "altserver", "objectclass",
        ]
        var order: [String] = []
        var byKey: [String: [String]] = [:]
        for attr in attributes {
            let key = attr.name.lowercased()
            guard !handled.contains(key) else { continue }
            if byKey[key] == nil { order.append(attr.name) }
            byKey[key, default: []].append(attr.value)
        }
        return order.map { NamedValues(name: $0, values: byKey[$0.lowercased()] ?? []) }
    }

    // MARK: - Load

    private func load() async {
        loadError = nil
        isLoading = true
        do {
            let results = try await searchDirectory(
                host: connection.host, port: UInt16(clamping: connection.port),
                useSsl: connection.useSSL, startTLS: connection.useStartTLS,
                pinnedCertSHA256: connection.trustedCertSHA256,
                bindDn: connection.bindDN, password: password,
                baseDn: "", scope: .base, filter: "(objectClass=*)",
                includeOperational: true
            )
            guard let entry = results.first else {
                loadError = "The server didn't return a Root DSE entry."
                isLoading = false
                return
            }
            attributes = entry.attributes
        } catch {
            loadError = "\(error)"
        }
        isLoading = false
    }

    private func copyAsText() {
        var lines = ["\(connection.name) (\(connection.host):\(connection.port))"]
        if let vendorName {
            lines.append("Vendor: \([vendorName, vendorVersion].compactMap { $0 }.joined(separator: " "))")
        }
        if !ldapVersions.isEmpty { lines.append("LDAP version: \(ldapVersions.joined(separator: ", "))") }
        lines.append("")
        if !namingContexts.isEmpty {
            lines.append("Naming contexts:")
            lines.append(contentsOf: namingContexts.map { "  \($0)" })
            lines.append("")
        }
        if !saslMechs.isEmpty {
            lines.append("SASL mechanisms: \(saslMechs.joined(separator: ", "))")
            lines.append("")
        }
        if !extensions.isEmpty {
            lines.append("Supported extensions:")
            lines.append(contentsOf: extensions.map { describeOID($0, known: Self.knownExtensions) })
            lines.append("")
        }
        if !controls.isEmpty {
            lines.append("Supported controls:")
            lines.append(contentsOf: controls.map { describeOID($0, known: Self.knownControls) })
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func describeOID(_ oid: String, known: [String: String]) -> String {
        known[oid].map { "  \(oid)  (\($0))" } ?? "  \(oid)"
    }

    // MARK: - Well-known OIDs (only entries we're confident about)

    private static let knownExtensions: [String: String] = [
        "1.3.6.1.4.1.1466.20037": "StartTLS",
        "1.3.6.1.4.1.4203.1.11.1": "Password Modify",
        "1.3.6.1.4.1.4203.1.11.3": "Who Am I?",
        "1.3.6.1.1.8": "Cancel Operation",
        "1.3.6.1.4.1.1466.101.119.1": "Dynamic Refresh",
    ]

    private static let knownControls: [String: String] = [
        "1.2.840.113556.1.4.319": "Paged Results (RFC 2696)",
        "1.2.840.113556.1.4.473": "Server-Side Sort Request",
        "1.2.840.113556.1.4.474": "Server-Side Sort Response",
        "1.2.840.113556.1.4.529": "Extended DN",
        "1.2.840.113556.1.4.805": "Tree Delete",
        "1.2.840.113556.1.4.417": "Show Deleted Objects",
        "1.3.6.1.1.12": "Assertion",
        "1.3.6.1.1.13.1": "Pre-Read",
        "1.3.6.1.1.13.2": "Post-Read",
        "1.3.6.1.1.22": "Don't Use Copy",
        "1.3.6.1.4.1.42.2.27.8.5.1": "Password Policy",
        "1.3.6.1.4.1.42.2.27.9.5.2": "Get Effective Rights",
        "1.3.6.1.4.1.4203.1.9.1.1": "LDAP Content Sync (RFC 4533)",
        "1.3.6.1.4.1.4203.1.10.1": "Subentries",
        "2.16.840.1.113730.3.4.2": "ManageDsaIT",
        "2.16.840.1.113730.3.4.3": "Persistent Search",
        "2.16.840.1.113730.3.4.4": "Password Expired",
        "2.16.840.1.113730.3.4.5": "Password Expiring",
        "2.16.840.1.113730.3.4.9": "Virtual List View (VLV)",
        "2.16.840.1.113730.3.4.12": "Proxied Authorization (v1)",
        "2.16.840.1.113730.3.4.15": "Authorization Identity Response",
        "2.16.840.1.113730.3.4.16": "Authorization Identity Request",
        "2.16.840.1.113730.3.4.17": "Real Attributes Only",
        "2.16.840.1.113730.3.4.18": "Proxied Authorization (v2, RFC 4370)",
    ]

    private static let knownFeatures: [String: String] = [
        "1.3.6.1.4.1.4203.1.5.1": "All Operational Attributes",
        "1.3.6.1.4.1.4203.1.5.2": "OC AD-Lists",
        "1.3.6.1.4.1.4203.1.5.3": "True/False Filters",
        "1.3.6.1.4.1.4203.1.5.4": "Language Tag Options",
        "1.3.6.1.4.1.4203.1.5.5": "Language Range Options",
    ]
}

/// Left-to-right wrapping layout — each subview keeps its own natural
/// size (unlike `LazyVGrid`, whose adaptive columns share one width per
/// row) and wraps to a new line only when it no longer fits.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widestLine = max(widestLine, x - spacing)
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        widestLine = max(widestLine, x - spacing)
        let width = maxWidth.isFinite ? maxWidth : widestLine
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
