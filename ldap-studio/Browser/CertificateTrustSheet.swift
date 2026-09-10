//
//  CertificateTrustSheet.swift
//  ldap-studio
//

import SwiftUI

/// Shown when a TLS / StartTLS connection is refused because the server's
/// certificate doesn't validate against the system trust store. It probes
/// the certificate (verification off, read-only) and lets the user pin its
/// SHA-256 for this one connection — the browser equivalent of "proceed
/// anyway", but scoped and remembered.
struct CertificateTrustSheet: View {
    let host: String
    let port: UInt16
    let useSSL: Bool
    let useStartTLS: Bool
    /// Called with the leaf certificate's SHA-256 when the user trusts it.
    let onTrust: (_ sha256: String) -> Void
    /// When set, the sheet renders this instead of probing the server —
    /// for previews and tests.
    var previewCertificate: LdapCertificate?

    @Environment(\.dismiss) private var dismiss

    @State private var certificate: LdapCertificate?
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Untrusted Certificate")
                        .font(.headline)
                    Text("\(host):\(String(port))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            Group {
                if let certificate {
                    details(certificate)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't Read Certificate", systemImage: "xmark.octagon")
                    } description: {
                        Text(loadError)
                    }
                } else {
                    ProgressView("Reading certificate…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 240)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Trust for This Connection") {
                    if let certificate { onTrust(certificate.sha256) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(certificate == nil)
            }
            .padding()
        }
        .frame(width: 520)
        .task {
            if let previewCertificate {
                certificate = previewCertificate
                return
            }
            do {
                certificate = try await probeCertificate(
                    host: host, port: port, useSsl: useSSL, startTLS: useStartTLS
                )
            } catch {
                loadError = "\(error)"
            }
        }
    }

    @ViewBuilder
    private func details(_ cert: LdapCertificate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let reasons = warnings(for: cert)
            if !reasons.isEmpty {
                HStack(spacing: 6) {
                    ForEach(reasons, id: \.self) { reason in
                        Text(reason)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.18), in: Capsule())
                    }
                }
            }

            row("Subject", cert.subject)
            row("Issuer", cert.issuer)
            row("Valid from", cert.notBefore)
            row("Valid until", cert.notAfter)
            row("SHA-256", NewConnectionSheet.shortFingerprint(cert.sha256))

            Text("Trusting this pins the certificate above. If the server ever presents a different one, the connection will fail until you review it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func warnings(for cert: LdapCertificate) -> [String] {
        var out: [String] = []
        if cert.selfSigned { out.append("Self-signed") }
        if cert.expired { out.append("Expired / not yet valid") }
        if cert.hostMismatch { out.append("Name mismatch") }
        return out
    }
}

#Preview {
    CertificateTrustSheet(
        host: "ldap.internal.example.com",
        port: 636,
        useSSL: true,
        useStartTLS: false,
        onTrust: { print("trusted \($0)") },
        previewCertificate: LdapCertificate(
            subject: "CN=ldap.internal.example.com,O=Example Corp,C=US",
            issuer: "CN=Example Corp Internal CA,O=Example Corp,C=US",
            sha256: "a1b2c3d4e5f60718293a4b5c6d7e8f90112233445566778899aabbccddeeff001",
            notBefore: "Jan  1 00:00:00 2025 GMT",
            notAfter: "Jan  1 00:00:00 2028 GMT",
            selfSigned: false,
            expired: false,
            hostMismatch: true
        )
    )
}
