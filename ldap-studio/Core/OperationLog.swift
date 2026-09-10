//
//  OperationLog.swift
//  ldap-studio
//
//  A bounded, in-memory record of every LDAP operation the bridge sends —
//  what, where, how long, and the result. Fed by `LdapStudioCore`'s
//  `logged(_:)` wrapper; shown in the browser's Operation Log panel.
//

import Foundation

@MainActor
@Observable
final class OperationLog {
    static let shared = OperationLog()
    private init() {}

    enum Kind: String {
        case connect = "CONNECT"
        case search = "SEARCH"
        case schema = "SCHEMA"
        case add = "ADD"
        case modify = "MODIFY"
        case delete = "DELETE"
        case rename = "MODDN"
    }

    enum Outcome: Equatable {
        case ok
        case failure(String)
        var isOK: Bool { self == .ok }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let at: Date
        /// "host:port" — lets a browser window filter to its own connection.
        let endpoint: String
        let kind: Kind
        /// One-line description for the table row.
        let summary: String
        /// Full base/scope/filter or the individual mods, for the detail view.
        let detail: String
        let millis: Double
        let outcome: Outcome
    }

    private(set) var entries: [Entry] = []
    private let limit = 500

    func record(endpoint: String, kind: Kind, summary: String, detail: String,
                millis: Double, outcome: Outcome) {
        entries.append(Entry(at: Date(), endpoint: endpoint, kind: kind,
                             summary: summary, detail: detail, millis: millis,
                             outcome: outcome))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func clear() { entries.removeAll() }
}
