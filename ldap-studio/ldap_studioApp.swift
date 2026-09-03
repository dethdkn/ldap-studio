//
//  ldap_studioApp.swift
//  ldap-studio
//
//  Created by Gabriel Rosa on 07/08/26.
//

import SwiftUI

@main
struct ldap_studioApp: App {
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

        Window("About Ldap Studio", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
