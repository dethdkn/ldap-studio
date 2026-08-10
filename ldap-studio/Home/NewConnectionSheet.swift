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

    @State private var testSucceeded = false
    @State private var testResultMessage = ""
    @State private var isShowingTestResult = false
    @State private var isTesting = false

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
                    .onChange(of: useSSL) { _, newValue in
                        port = newValue ? 636 : 389
                    }
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
                    Task {
                        isTesting = true
                        defer { isTesting = false }
                        do {
                            try await testConnection(
                                host: host,
                                port: UInt16(clamping: port),
                                useSsl: useSSL,
                                bindDn: bindDN,
                                password: password
                            )
                            testSucceeded = true
                            testResultMessage = "Successfully connected and bound to \(host)."
                        } catch {
                            testSucceeded = false
                            testResultMessage = "\(error)"
                        }
                        isShowingTestResult = true
                    }
                }
                .disabled(!isValid || isTesting)

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
        .alert(
            testSucceeded ? "Connection Successful" : "Connection Failed",
            isPresented: $isShowingTestResult
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage)
        }
    }
}

#Preview {
    NewConnectionSheet()
}
