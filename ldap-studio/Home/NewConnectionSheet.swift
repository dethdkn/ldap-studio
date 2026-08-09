//
//  NewConnectionSheet.swift
//  ldap-studio
//

import SwiftUI

struct NewConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: Int = 389
    @State private var useSSL: Bool = false
    @State private var bindDN: String = ""
    @State private var password: String = ""

    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Connection")
                .font(.headline)
                .padding()

            Form {
                TextField("Name", text: $name)
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number)
                Toggle("Use SSL", isOn: $useSSL)
                TextField("Bind DN", text: $bindDN)
                SecureField("Password", text: $password)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Test") {
                    // Will test the connection later.
                }
                .disabled(!isValid)

                Button("Add") {
                    // Will create the actual connection later.
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 420, height: 380)
    }
}

#Preview {
    NewConnectionSheet()
}
