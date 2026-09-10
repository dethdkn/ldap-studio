//
//  OperationLogPanel.swift
//  ldap-studio
//

import SwiftUI

/// The expanded body of the browser's Operation Log — a table of the LDAP
/// operations sent for this connection, newest first, with a detail pane.
struct OperationLogPanel: View {
    /// "host:port" of the owning browser window; filters the shared log.
    let endpoint: String

    @State private var log = OperationLog.shared
    @State private var selection: OperationLog.Entry.ID?

    private var rows: [OperationLog.Entry] {
        log.entries.filter { $0.endpoint == endpoint }.reversed()
    }

    private var selected: OperationLog.Entry? {
        rows.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Operation Log").font(.caption.weight(.semibold))
                Text("\(rows.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { log.clear() }
                    .controlSize(.small)
                    .disabled(rows.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Divider()

            if rows.isEmpty {
                ContentUnavailableView("No Operations Yet", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    Table(rows, selection: $selection) {
                        TableColumn("Time") { entry in
                            Text(entry.at, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .width(70)
                        TableColumn("Op") { entry in
                            Text(entry.kind.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundStyle(entry.kind == .delete ? .red : .primary)
                        }
                        .width(66)
                        TableColumn("Summary") { entry in
                            Text(entry.summary).lineLimit(1)
                        }
                        TableColumn("ms") { entry in
                            Text(String(format: "%.0f", entry.millis))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .width(48)
                        TableColumn("Result") { entry in
                            switch entry.outcome {
                            case .ok:
                                Text("OK").foregroundStyle(.green)
                            case .failure(let message):
                                Text(message).foregroundStyle(.red).lineLimit(1)
                            }
                        }
                    }
                    .frame(minWidth: 360)

                    ScrollView {
                        if let selected {
                            Text(detailText(for: selected))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        } else {
                            Text("Select a row to see its base / scope / filter or mods.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                    }
                    .frame(minWidth: 220)
                }
            }
        }
    }

    private func detailText(for entry: OperationLog.Entry) -> String {
        var lines = [
            "\(entry.kind.rawValue)  \(entry.summary)",
            "endpoint: \(entry.endpoint)",
            String(format: "elapsed: %.1f ms", entry.millis),
        ]
        if case .failure(let message) = entry.outcome {
            lines.append("result: \(message)")
        } else {
            lines.append("result: OK")
        }
        lines.append("")
        lines.append(entry.detail)
        return lines.joined(separator: "\n")
    }
}
