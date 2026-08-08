//
//  InfoPanel.swift
//  ldap-studio
//

import SwiftUI

struct InfoPanel: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("ldap-studio")
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("LDAP Studio")
                    .font(.title2.bold())
                Text("Version \(appVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button {
                    // Will open the "new connection" sheet later.
                } label: {
                    Label("Add Connection…", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    // Will open the "import connection" file selector later.
                } label: {
                    Label("Import Connection…", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

#Preview {
    InfoPanel()
        .frame(height: 500)
}
