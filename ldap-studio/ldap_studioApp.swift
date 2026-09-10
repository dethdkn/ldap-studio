//
//  ldap_studioApp.swift
//  ldap-studio
//
//  Created by Gabriel Rosa on 07/08/26.
//

import AppKit
import SwiftUI

@main
struct ldap_studioApp: App {
    /// One store for the whole app — the Home window edits it, and the
    /// browser windows read it (and write back a trusted certificate when
    /// the user accepts one). Injected into every scene below.
    @State private var store = ConnectionStore()

    init() {
        // This is a multi-window utility app, not a document app — macOS
        // window tabbing (and the empty "New Tab") makes no sense here, so
        // turn it off entirely. Also drops "Show Tab Bar" from the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            Home()
                .environment(store)
                .task { store.load() }
        }
        .commands {
            AppMenuCommands()
        }

        WindowGroup(for: SavedConnection.self) { $connection in
            if let connection {
                BrowserView(connection: connection)
                    .environment(store)
            }
        }

        WindowGroup(id: "schema", for: SavedConnection.self) { $connection in
            if let connection {
                SchemaView(connection: connection)
                    .environment(store)
            }
        }

        WindowGroup(id: "ldif", for: SavedConnection.self) { $connection in
            if let connection {
                LDIFEditorView(connection: connection)
                    .environment(store)
            }
        }

        Window("About Ldap Studio", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
