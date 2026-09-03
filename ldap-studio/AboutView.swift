//
//  AboutView.swift
//  ldap-studio
//

import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image("ldap-studio")
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Ldap Studio")
                    .font(.title2.bold())
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Link("GitHub", destination: URL(string: "https://github.com/dethdkn/ldap-studio")!)
                Text("|")
                    .foregroundStyle(.secondary)
                Link("Report Bug", destination: URL(string: "https://github.com/dethdkn/ldap-studio/issues")!)
                Text("|")
                    .foregroundStyle(.secondary)
                Link("Sponsor", destination: URL(string: "https://github.com/sponsors/dethdkn")!)
            }
            .font(.callout)
        }
        .padding(32)
        .frame(width: 320)
    }
}

#Preview {
    AboutView()
}
