//
//  SSHHostKeyFingerprint.swift
//  ldap-studio
//

import Foundation

/// SSH host key fingerprints, in the form people can actually compare.
enum SSHHostKeyFingerprint {
    /// The core reports a host key as the lowercase hex SHA-256 of its public
    /// key blob. OpenSSH — `ssh-keygen -lf`, the fingerprint line printed on a
    /// first `ssh` connection, most administrators' notes — shows the very
    /// same hash as `SHA256:` plus unpadded base64, so that's the form to show
    /// someone who has to verify it. Returns the input unchanged if it isn't
    /// valid hex.
    static func openSSH(fromHex hex: String) -> String {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return hex }
            bytes.append(byte)
            index = next
        }
        let base64 = Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:" + base64
    }
}
