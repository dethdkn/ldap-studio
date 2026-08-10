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

        WindowGroup(for: SavedConnection.self) { $connection in
            if let connection {
                BrowserView(connection: connection)
            }
        }
    }
}
