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
    init() {
        // This is a multi-window utility app, not a document app — macOS
        // window tabbing (and the empty "New Tab") makes no sense here, so
        // turn it off entirely. Also drops "Show Tab Bar" from the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            Home()
        }
        .commands {
            AppMenuCommands()
        }

        WindowGroup(for: SavedConnection.self) { $connection in
            if let connection {
                BrowserView(connection: connection)
            }
        }

        WindowGroup(id: "schema", for: SavedConnection.self) { $connection in
            if let connection {
                SchemaView(connection: connection)
            }
        }

        WindowGroup(id: "ldif", for: SavedConnection.self) { $connection in
            if let connection {
                LDIFEditorView(connection: connection)
            }
        }

        Window("About Ldap Studio", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
