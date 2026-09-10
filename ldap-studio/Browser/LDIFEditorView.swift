//
//  LDIFEditorView.swift
//  ldap-studio
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A scratch pad for LDIF change records that runs them against the
/// connection. Add / delete / modify / modrdn are supported; every record
/// runs even if an earlier one failed (LDAP has no transactions), and the
/// per-record outcome is listed below.
struct LDIFEditorView: View {
    let connection: SavedConnection

    @State private var text = ""
    @State private var results: [RunResult] = []
    @State private var isRunning = false
    @State private var summary: String?

    private struct RunResult: Identifiable {
        let id = UUID()
        let dn: String
        let action: String
        let ok: Bool
        let detail: String
    }

    private var password: String {
        KeychainService.readPassword(for: connection.id) ?? ""
    }

    var body: some View {
        VSplitView {
            editor
            resultsPane
        }
        .frame(minWidth: 560, minHeight: 460)
        .navigationTitle("LDIF Editor — \(connection.name)")
        .focusedSceneValue(\.ldifEditorCommands, LDIFEditorCommands(
            openFile: { openFile() },
            saveFile: { saveFile() },
            run: { run() }
        ))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openFile()
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                Button {
                    saveFile()
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                Button {
                    run()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(isRunning || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .disableAutocorrection(true)
            .frame(minHeight: 180)
            .overlay(alignment: .topTrailing) {
                if isRunning {
                    ProgressView().controlSize(.small).padding(8)
                }
            }
    }

    private var resultsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Results").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Divider()

            if results.isEmpty {
                ContentUnavailableView("No run yet", systemImage: "text.badge.checkmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(results) { result in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(result.ok ? Color.green : Color.red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(result.action)  \(result.dn)").font(.callout)
                                if !result.detail.isEmpty {
                                    Text(result.detail)
                                        .font(.caption)
                                        .foregroundStyle(result.ok ? Color.secondary : Color.red)
                                }
                            }
                            Spacer()
                        }
                        .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(minHeight: 120)
    }

    // MARK: - Run

    private func run() {
        let records: [LDIFRecord]
        do {
            records = try LDIFChangeParser.parse(text)
        } catch {
            results = [RunResult(dn: "", action: "parse", ok: false,
                                 detail: (error as? LocalizedError)?.errorDescription ?? "\(error)")]
            summary = "Parse failed"
            return
        }
        guard !records.isEmpty else {
            results = [RunResult(dn: "", action: "parse", ok: false, detail: "No records found.")]
            summary = nil
            return
        }

        isRunning = true
        results = []
        summary = nil

        Task {
            var out: [RunResult] = []
            for record in records {
                let (action, work) = plan(for: record)
                do {
                    try await work()
                    out.append(RunResult(dn: record.dn, action: action, ok: true, detail: ""))
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    out.append(RunResult(dn: record.dn, action: action, ok: false, detail: message))
                }
                results = out
            }
            let failed = out.filter { !$0.ok }.count
            summary = failed == 0
                ? "\(out.count) record\(out.count == 1 ? "" : "s") applied"
                : "\(out.count - failed) applied, \(failed) failed"
            isRunning = false
        }
    }

    private func plan(for record: LDIFRecord) -> (action: String, work: () async throws -> Void) {
        let host = connection.host
        let port = UInt16(clamping: connection.port)
        let ssl = connection.useSSL
        let bind = connection.bindDN
        let pw = password
        let dn = record.dn

        switch record.change {
        case .add(let attributes):
            return ("add", {
                try await addEntry(host: host, port: port, useSsl: ssl, bindDn: bind, password: pw,
                                   dn: dn,
                                   attributes: attributes.map {
                                       LdapAttribute(name: $0.name, value: $0.value, isBinary: $0.isBinary)
                                   })
            })
        case .delete:
            return ("delete", {
                try await deleteEntry(host: host, port: port, useSsl: ssl, bindDn: bind, password: pw, dn: dn)
            })
        case .modify(let ops):
            return ("modify", {
                try await modifyEntry(host: host, port: port, useSsl: ssl, bindDn: bind, password: pw,
                                      dn: dn,
                                      ops: ops.map { op in
                                          LdapModOp(kind: op.kind.bridged,
                                                    attribute: op.attribute,
                                                    values: op.values)
                                      })
            })
        case .modrdn(let newRDN, let deleteOldRDN, let newSuperior):
            return ("modrdn", {
                try await renameEntry(host: host, port: port, useSsl: ssl, bindDn: bind, password: pw,
                                      dn: dn, newRDN: newRDN, deleteOldRDN: deleteOldRDN,
                                      newSuperior: newSuperior)
            })
        }
    }

    // MARK: - Files

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ldif") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        DispatchQueue.main.async {
            panel.begin { response in
                guard response == .OK, let url = panel.url,
                      let loaded = try? String(contentsOf: url, encoding: .utf8) else { return }
                text = loaded
                results = []
                summary = nil
            }
        }
    }

    private func saveFile() {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "changes"
            panel.allowedContentTypes = [UTType(filenameExtension: "ldif") ?? .plainText]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

}

private extension LDIFModification.Kind {
    var bridged: LdapModKind {
        switch self {
        case .add: return .add
        case .delete: return .delete
        case .replace: return .replace
        }
    }
}
