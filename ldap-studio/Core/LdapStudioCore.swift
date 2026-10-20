//
//  LdapStudioCore.swift
//
//  Hand-written Swift bridge to the C core in `core/` (see
//  core/include/ldapstudio.h). This file replaces what uniffi used to
//  generate: it re-declares the same public types and free functions the
//  rest of the app already uses, so nothing else had to change.
//
//  The C library is exposed through the bridging header
//  (ldap-studio-Bridging-Header.h), so its symbols are visible here with
//  no `import`. libldap's calls are synchronous; the `async` functions
//  below run them on background queues and resume a continuation.
//  Directory operations run on pooled connections (LdapConnectionPool.swift)
//  rather than connecting and binding for every call.
//

import Foundation

// MARK: - Public data types (shapes match the former generated code)

nonisolated public struct LdapAttribute: Equatable, Hashable, Sendable {
    public var name: String
    /// For binary attributes (e.g. jpegPhoto) this is base64-encoded raw
    /// bytes rather than literal text — see `isBinary`.
    public var value: String
    public var isBinary: Bool

    public init(name: String, value: String, isBinary: Bool) {
        self.name = name
        self.value = value
        self.isBinary = isBinary
    }
}

nonisolated public struct LdapEntry: Equatable, Hashable, Sendable {
    public var dn: String
    public var name: String
    public var attributes: [LdapAttribute]

    public init(dn: String, name: String, attributes: [LdapAttribute]) {
        self.dn = dn
        self.name = name
        self.attributes = attributes
    }

    /// Every value of `attribute`, matched case-insensitively.
    public func values(_ attribute: String) -> [String] {
        attributes
            .filter { $0.name.caseInsensitiveCompare(attribute) == .orderedSame }
            .map(\.value)
    }
}

nonisolated public enum LdapSearchScope: Equatable, Hashable, Sendable {
    case base
    case oneLevel
    case subtree
}

nonisolated public enum LdapAuthenticationMethod: Int32, Hashable, Sendable {
    case simple = 0, external, gssapi, digestMD5
}

nonisolated public struct LDAPConnectionOptions: Hashable, Sendable {
    public var chaseReferrals: Bool
    public var timeoutSeconds: Int
    public var authentication: LdapAuthenticationMethod
    public var authID: String
    public var realm: String
    public var clientCertificateBookmark: Data?
    public var clientKeyBookmark: Data?
    public var useSSHTunnel: Bool
    public var sshHost: String
    public var sshPort: Int
    public var sshUsername: String
    public var sshUsesPrivateKey: Bool
    public var sshPassword: String
    public var sshPrivateKeyBookmark: Data?
    public var sshHostKeySHA256: String?

    public init(chaseReferrals: Bool = false, timeoutSeconds: Int = 15,
                authentication: LdapAuthenticationMethod = .simple,
                authID: String = "", realm: String = "",
                clientCertificateBookmark: Data? = nil,
                clientKeyBookmark: Data? = nil, useSSHTunnel: Bool = false,
                sshHost: String = "", sshPort: Int = 22, sshUsername: String = "",
                sshUsesPrivateKey: Bool = false, sshPassword: String = "",
                sshPrivateKeyBookmark: Data? = nil, sshHostKeySHA256: String? = nil) {
        self.chaseReferrals = chaseReferrals
        self.timeoutSeconds = timeoutSeconds
        self.authentication = authentication
        self.authID = authID
        self.realm = realm
        self.clientCertificateBookmark = clientCertificateBookmark
        self.clientKeyBookmark = clientKeyBookmark
        self.useSSHTunnel = useSSHTunnel
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshUsesPrivateKey = sshUsesPrivateKey
        self.sshPassword = sshPassword
        self.sshPrivateKeyBookmark = sshPrivateKeyBookmark
        self.sshHostKeySHA256 = sshHostKeySHA256
    }
}

nonisolated public struct SchemaObjectClass: Equatable, Hashable {
    public var oid: String
    /// All NAME values — the first is the conventional display name, the
    /// rest are aliases.
    public var names: [String]
    public var description: String?
    public var obsolete: Bool
    public var superiorClasses: [String]
    /// STRUCTURAL / ABSTRACT / AUXILIARY — defaults to STRUCTURAL per RFC 4512.
    public var kind: String
    public var must: [String]
    public var may: [String]
    public var xOrigin: String?
    /// The untouched schema definition string.
    public var raw: String

    public init(oid: String, names: [String], description: String?, obsolete: Bool,
                superiorClasses: [String], kind: String, must: [String], may: [String],
                xOrigin: String?, raw: String) {
        self.oid = oid
        self.names = names
        self.description = description
        self.obsolete = obsolete
        self.superiorClasses = superiorClasses
        self.kind = kind
        self.must = must
        self.may = may
        self.xOrigin = xOrigin
        self.raw = raw
    }
}

nonisolated public struct SchemaAttributeType: Equatable, Hashable {
    public var oid: String
    public var names: [String]
    public var description: String?
    public var obsolete: Bool
    public var superiorType: String?
    public var equalityMatchingRule: String?
    public var orderingMatchingRule: String?
    public var substringMatchingRule: String?
    /// The SYNTAX token as the server sent it — usually a numeric OID,
    /// sometimes with a `{length}` suffix.
    public var syntaxOid: String?
    public var singleValued: Bool
    public var collective: Bool
    public var noUserModification: Bool
    public var usage: String?
    public var xOrigin: String?
    public var raw: String

    public init(oid: String, names: [String], description: String?, obsolete: Bool,
                superiorType: String?, equalityMatchingRule: String?,
                orderingMatchingRule: String?, substringMatchingRule: String?,
                syntaxOid: String?, singleValued: Bool, collective: Bool,
                noUserModification: Bool, usage: String?, xOrigin: String?, raw: String) {
        self.oid = oid
        self.names = names
        self.description = description
        self.obsolete = obsolete
        self.superiorType = superiorType
        self.equalityMatchingRule = equalityMatchingRule
        self.orderingMatchingRule = orderingMatchingRule
        self.substringMatchingRule = substringMatchingRule
        self.syntaxOid = syntaxOid
        self.singleValued = singleValued
        self.collective = collective
        self.noUserModification = noUserModification
        self.usage = usage
        self.xOrigin = xOrigin
        self.raw = raw
    }
}

nonisolated public struct LdapSchema: Equatable, Hashable {
    public var objectClasses: [SchemaObjectClass]
    public var attributeTypes: [SchemaAttributeType]

    public init(objectClasses: [SchemaObjectClass], attributeTypes: [SchemaAttributeType]) {
        self.objectClasses = objectClasses
        self.attributeTypes = attributeTypes
    }
}

public enum PasswordScheme: Equatable, Hashable {
    case pbkdf2Sha512
    case unixCrypt
    case md5Crypt
    case md5
    case sha1
    case smd5
    case ssha
    case sha256Crypt
    case sha512Crypt
}

// MARK: - Errors

public enum ConnectionError: Error, CustomStringConvertible {
    case ConnectFailed(host: String, port: UInt16, reason: String)
    case ConnectTimedOut(host: String, port: UInt16)
    case BindFailed(reason: String)
    case SearchFailed(reason: String)
    case ModifyFailed(reason: String)
    /// TLS/StartTLS rejected the server's certificate, or it didn't match
    /// the fingerprint trusted for this connection. The UI answers this by
    /// probing the certificate and offering "Trust for this connection".
    case TLSUntrusted(host: String, port: UInt16, reason: String)
    case SSHHostKeyUntrusted(host: String, port: UInt16, fingerprint: String)
    /// A write was attempted on a connection marked read-only. Blocked
    /// before it ever reaches the server.
    case ReadOnly
    /// A pooled connection found the server gone, and reconnecting didn't
    /// help either.
    case ConnectionLost(reason: String)

    public var description: String {
        switch self {
        case let .ConnectFailed(host, port, reason):
            return "Could not connect to \(host):\(port): \(reason)"
        case let .ConnectTimedOut(host, port):
            return "Connecting to \(host):\(port) timed out"
        case let .BindFailed(reason):   return "Bind failed: \(reason)"
        case let .SearchFailed(reason): return "Search failed: \(reason)"
        case let .ModifyFailed(reason): return "Modify failed: \(reason)"
        case let .TLSUntrusted(host, port, reason):
            return "The certificate for \(host):\(port) isn't trusted: \(reason)"
        case let .SSHHostKeyUntrusted(host, port, fingerprint):
            return "The SSH host key for \(host):\(port) is not trusted (\(SSHHostKeyFingerprint.openSSH(fromHex: fingerprint)))."
        case .ReadOnly:
            return "This connection is read-only. Turn off read-only mode in its settings to make changes."
        case let .ConnectionLost(reason):
            return "Lost the connection to the server: \(reason)"
        }
    }
    public var errorDescription: String? { description }
}

public enum PasswordError: Error, CustomStringConvertible {
    case HashFailed(reason: String)
    public var description: String {
        switch self { case let .HashFailed(reason): return "Couldn't hash the password: \(reason)" }
    }
    public var errorDescription: String? { description }
}

public enum PhotoError: Error, CustomStringConvertible {
    case DecodeFailed(reason: String)
    case EncodeFailed(reason: String)
    public var description: String {
        switch self {
        case let .DecodeFailed(reason): return "Couldn't read or decode the image: \(reason)"
        case let .EncodeFailed(reason): return "Couldn't encode the resized image: \(reason)"
        }
    }
    public var errorDescription: String? { description }
}

// MARK: - C ↔ Swift marshalling helpers

nonisolated private func str(_ p: UnsafePointer<CChar>?) -> String {
    p.map { String(cString: $0) } ?? ""
}

nonisolated private func optStr(_ p: UnsafePointer<CChar>?) -> String? {
    p.map { String(cString: $0) }
}

nonisolated private func strArray(_ p: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, _ n: Int) -> [String] {
    guard let p, n > 0 else { return [] }
    return (0..<n).map { String(cString: p[$0]!) }
}

/// Turns a populated `LSError` into the matching Swift error and disposes
/// the strings it owns.
nonisolated private func swiftError(_ err: inout LSError) -> Error {
    defer { ls_error_dispose(&err) }
    let host = str(err.host)
    let reason = str(err.reason)
    switch err.kind {
    case LS_CONNECT_FAILED:    return ConnectionError.ConnectFailed(host: host, port: err.port, reason: reason)
    case LS_CONNECT_TIMED_OUT: return ConnectionError.ConnectTimedOut(host: host, port: err.port)
    case LS_TLS_UNTRUSTED:     return ConnectionError.TLSUntrusted(host: host, port: err.port, reason: reason)
    case LS_SSH_HOST_KEY_UNTRUSTED: return ConnectionError.SSHHostKeyUntrusted(host: host, port: err.port, fingerprint: reason)
    case LS_BIND_FAILED:       return ConnectionError.BindFailed(reason: reason)
    case LS_SEARCH_FAILED:     return ConnectionError.SearchFailed(reason: reason)
    case LS_MODIFY_FAILED:     return ConnectionError.ModifyFailed(reason: reason)
    case LS_HASH_FAILED:       return PasswordError.HashFailed(reason: reason)
    case LS_DECODE_FAILED:     return PhotoError.DecodeFailed(reason: reason)
    case LS_ENCODE_FAILED:     return PhotoError.EncodeFailed(reason: reason)
    case LS_CONNECTION_LOST:   return ConnectionError.ConnectionLost(reason: reason)
    case LS_CANCELLED:         return CancellationError()
    default:                   return ConnectionError.SearchFailed(reason: reason.isEmpty ? "unknown error" : reason)
    }
}

nonisolated func convert(_ e: UnsafePointer<LSEntry>) -> LdapEntry {
    let v = e.pointee
    var attributes: [LdapAttribute] = []
    if let ap = v.attributes, v.attribute_count > 0 {
        attributes.reserveCapacity(v.attribute_count)
        for i in 0..<v.attribute_count {
            let a = ap[i]
            attributes.append(LdapAttribute(name: str(a.name),
                                            value: str(a.value),
                                            isBinary: a.is_binary))
        }
    }
    return LdapEntry(dn: str(v.dn), name: str(v.name), attributes: attributes)
}

nonisolated private func convert(objectClass o: LSObjectClass) -> SchemaObjectClass {
    SchemaObjectClass(oid: str(o.oid),
                      names: strArray(o.names, o.name_count),
                      description: optStr(o.description),
                      obsolete: o.obsolete,
                      superiorClasses: strArray(o.superior_classes, o.superior_class_count),
                      kind: str(o.kind),
                      must: strArray(o.must, o.must_count),
                      may: strArray(o.may, o.may_count),
                      xOrigin: optStr(o.x_origin),
                      raw: str(o.raw))
}

nonisolated private func convert(attributeType a: LSAttributeType) -> SchemaAttributeType {
    SchemaAttributeType(oid: str(a.oid),
                        names: strArray(a.names, a.name_count),
                        description: optStr(a.description),
                        obsolete: a.obsolete,
                        superiorType: optStr(a.superior_type),
                        equalityMatchingRule: optStr(a.equality_matching_rule),
                        orderingMatchingRule: optStr(a.ordering_matching_rule),
                        substringMatchingRule: optStr(a.substring_matching_rule),
                        syntaxOid: optStr(a.syntax_oid),
                        singleValued: a.single_valued,
                        collective: a.collective,
                        noUserModification: a.no_user_modification,
                        usage: optStr(a.usage),
                        xOrigin: optStr(a.x_origin),
                        raw: str(a.raw))
}

nonisolated private func cScope(_ s: LdapSearchScope) -> LSScope {
    switch s {
    case .base:     return LS_SCOPE_BASE
    case .oneLevel: return LS_SCOPE_ONELEVEL
    case .subtree:  return LS_SCOPE_SUBTREE
    }
}

private func cScheme(_ s: PasswordScheme) -> LSPasswordScheme {
    switch s {
    case .pbkdf2Sha512: return LS_PBKDF2_SHA512
    case .unixCrypt:    return LS_UNIX_CRYPT
    case .md5Crypt:     return LS_MD5_CRYPT
    case .md5:          return LS_MD5
    case .sha1:         return LS_SHA1
    case .smd5:         return LS_SMD5
    case .ssha:         return LS_SSHA
    case .sha256Crypt:  return LS_SHA256_CRYPT
    case .sha512Crypt:  return LS_SHA512_CRYPT
    }
}

/// Ships the app's own CA bundle to the C layer, once. The bundled
/// OpenSSL can't read Homebrew's default cert store from inside the App
/// Sandbox, so without this every ldaps:// handshake fails with a
/// "Connect error". Swift runs this exactly once, thread-safely.
private let installBundledCACert: Void = {
    if let path = Bundle.main.path(forResource: "openssl-cacert", ofType: "pem") {
        ls_set_tls_cacert(path)
    }
}()

/// Every call into the C core runs here, one at a time. That's a
/// requirement, not just tidiness: each operation first pushes its own
/// connection policy (TLS, auth, timeout, SSH) into sticky global state in
/// the core, so two calls in flight at once would trample each other's
/// settings.
private let ldapCoreQueue = DispatchQueue(label: "app.ldap-studio.native-core", qos: .userInitiated)

/// Runs a blocking C call off the main thread and bridges it to `async`.
private func background<T>(_ work: @escaping () -> Result<T, Error>) async throws -> T {
    _ = installBundledCACert
    return try await withCheckedThrowingContinuation { continuation in
        ldapCoreQueue.async {
            continuation.resume(with: work())
        }
    }
}

/// Same, but pushes this connection's TLS policy (StartTLS, pinned cert)
/// and connection options into the C layer first — it's sticky global
/// state that the next connect reads, so every operation sets it
/// explicitly, which also resets it for the plain-`ldap://` and
/// plain-`ldaps://` callers that pass the defaults.
private func background<T>(startTLS: Bool, pinnedCertSHA256: String?,
                           options: LDAPConnectionOptions? = nil,
                           _ work: @escaping () -> Result<T, Error>) async throws -> T {
    try await background {
        setTLSPolicy(startTLS: startTLS,
                     allowUntrusted: pinnedCertSHA256 != nil,
                     pinnedCertSHA256: pinnedCertSHA256)
        return withConnectionPolicy(options ?? LDAPConnectionOptions(), work)
    }
}

/// A file the user picked in the connection editor (client certificate,
/// private key), resolved from its security-scoped bookmark. Sandboxed
/// access to it lasts only while `stop()` hasn't been called.
nonisolated private struct ScopedFile {
    let path: String
    private let url: URL?
    private let isAccessing: Bool

    init(bookmark: Data?) {
        var isStale = false
        url = bookmark.flatMap {
            try? URL(resolvingBookmarkData: $0, options: .withSecurityScope,
                     relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
        isAccessing = url?.startAccessingSecurityScopedResource() ?? false
        path = url?.path ?? ""
    }

    func stop() {
        if isAccessing { url?.stopAccessingSecurityScopedResource() }
    }
}

/// Pushes `options` into the C core's per-operation policy, then runs
/// `work` with any security-scoped files that policy points at held open
/// until it returns.
nonisolated private func withConnectionPolicy<T>(_ options: LDAPConnectionOptions, _ work: () -> T) -> T {
    let certFile = ScopedFile(bookmark: options.clientCertificateBookmark)
    let keyFile = ScopedFile(bookmark: options.clientKeyBookmark)
    let sshKeyFile = ScopedFile(bookmark: options.sshPrivateKeyBookmark)
    defer {
        certFile.stop()
        keyFile.stop()
        sshKeyFile.stop()
    }

    ls_set_connection_policy(
        options.chaseReferrals,
        UInt32(clamping: options.timeoutSeconds),
        LSAuthMethod(rawValue: UInt32(options.authentication.rawValue)),
        options.authID,
        options.realm,
        certFile.path,
        keyFile.path
    )
    ls_set_ssh_policy(
        options.useSSHTunnel,
        options.sshHost,
        UInt16(clamping: options.sshPort),
        options.sshUsername,
        options.sshUsesPrivateKey ? LS_SSH_PRIVATE_KEY : LS_SSH_PASSWORD,
        options.sshPassword,
        sshKeyFile.path,
        options.sshHostKeySHA256 ?? ""
    )
    return work()
}

/// Wraps an operation so it lands in the Operation Log with timing and
/// outcome. Any thrown error is recorded and rethrown unchanged. `result`,
/// when given, is appended to the summary and detail once the work is done
/// (or has failed) — e.g. how many pages and entries a search read.
nonisolated private func logged<T>(_ kind: OperationLog.Kind, endpoint: String,
                                   summary: String, detail: String,
                                   result: (() -> String)? = nil,
                                   _ work: () async throws -> T) async throws -> T {
    let start = DispatchTime.now()
    func ms() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
    do {
        let value = try await work()
        let elapsed = ms()
        let note = result?()
        let summary = note.map { "\(summary) · \($0)" } ?? summary
        let detail = note.map { "\(detail)\nresult: \($0)" } ?? detail
        await MainActor.run {
            OperationLog.shared.record(endpoint: endpoint, kind: kind, summary: summary,
                                       detail: detail, millis: elapsed, outcome: .ok)
        }
        return value
    } catch {
        let elapsed = ms()
        let message = error is CancellationError ? "Cancelled" : "\(error)"
        let note = result?()
        let detail = note.map { "\(detail)\nresult: \($0)" } ?? detail
        await MainActor.run {
            OperationLog.shared.record(endpoint: endpoint, kind: kind, summary: summary,
                                       detail: detail, millis: elapsed,
                                       outcome: .failure(message))
        }
        throw error
    }
}

private func endpoint(_ host: String, _ port: UInt16) -> String { "\(host):\(port)" }

private func abbrev(_ s: String, _ n: Int = 120) -> String {
    s.count > n ? String(s.prefix(n)) + "…" : s
}

/// Sets the per-connection TLS policy in the C core. `allowUntrusted`
/// only makes sense together with a pin (verification off, the pin is
/// what's trusted); with no pin it's plain chain verification.
nonisolated public func setTLSPolicy(startTLS: Bool, allowUntrusted: Bool, pinnedCertSHA256: String?) {
    if let pin = pinnedCertSHA256 {
        pin.withCString { ls_set_tls_policy(startTLS, allowUntrusted, $0) }
    } else {
        ls_set_tls_policy(startTLS, allowUntrusted, nil)
    }
}

/// The server's leaf certificate as read back with verification disabled —
/// for the "Trust for this connection" dialog.
public struct LdapCertificate: Sendable, Equatable {
    public let subject: String
    public let issuer: String
    /// Lowercase hex SHA-256 of the DER cert — what gets pinned.
    public let sha256: String
    public let notBefore: String
    public let notAfter: String
    public let selfSigned: Bool
    public let expired: Bool
    public let hostMismatch: Bool
}

public func probeCertificate(host: String, port: UInt16, useSsl: Bool,
                             startTLS: Bool) async throws -> LdapCertificate {
    try await background {
        var err = LSError()
        var info = LSCertInfo()
        let rc = ls_probe_certificate(host, port, useSsl, startTLS, &info, &err)
        guard rc == 0 else { return .failure(swiftError(&err)) }
        defer { ls_cert_info_dispose(&info) }
        return .success(LdapCertificate(
            subject: str(info.subject),
            issuer: str(info.issuer),
            sha256: str(info.sha256),
            notBefore: str(info.not_before),
            notAfter: str(info.not_after),
            selfSigned: info.self_signed,
            expired: info.expired,
            hostMismatch: info.host_mismatch
        ))
    }
}

// MARK: - Public API

public func testConnection(host: String, port: UInt16, useSsl: Bool,
                           startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                           options: LDAPConnectionOptions? = nil,
                           bindDn: String, password: String) async throws {
    try await logged(.connect, endpoint: endpoint(host, port),
                     summary: "bind \(bindDn.isEmpty ? "anonymous" : bindDn)",
                     detail: "host: \(host):\(port)\nbind: \(bindDn.isEmpty ? "anonymous" : bindDn)") {
        try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256, options: options) {
        var err = LSError()
        let rc = ls_test_connection(host, port, useSsl, bindDn, password, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
    }
}

/// Opens one pooled connection for `target` on the core queue — the
/// connection policy is sticky global state in the C layer, so it's set
/// and consumed in the same serialized step. Logged like a bind.
nonisolated func openPooledConnection(_ target: LdapTarget) async throws -> OpaquePointer {
    try await logged(.connect, endpoint: target.endpoint,
                     summary: "bind \(target.bindDn.isEmpty ? "anonymous" : target.bindDn)",
                     detail: "host: \(target.endpoint)\nbind: \(target.bindDn.isEmpty ? "anonymous" : target.bindDn)\nkept open for reuse") {
        try await background(startTLS: target.startTLS, pinnedCertSHA256: target.pinnedCertSHA256,
                             options: target.options) {
            var err = LSError()
            var conn: OpaquePointer?
            let rc = ls_connection_open(target.host, target.port, target.useSsl,
                                        target.bindDn, target.password, &conn, &err)
            guard rc == 0, let conn else { return .failure(swiftError(&err)) }
            return .success(conn)
        }
    }
}

// MARK: Searching

/// A search, read in pages (RFC 2696) so a server's size limit is never
/// the reason it fails.
nonisolated public struct LdapSearchRequest: Sendable {
    public var baseDn: String
    public var scope: LdapSearchScope
    public var filter: String
    /// nil = every user attribute; `["1.1"]` = none, just DNs.
    public var attributes: [String]?
    public var includeOperational: Bool
    /// Stop after this many entries — client-side, so reaching it is never
    /// an error. 0 = read everything.
    public var limit: Int
    public var pageSize: Int
    /// Fail a page the server sends nothing for in this many seconds.
    /// nil = a default of max(60, 4 × the connection timeout); 0 = wait as
    /// long as it takes — for searches the user started and can stop
    /// (an unindexed filter on a large Active Directory can take minutes).
    public var idleTimeout: Int?

    public init(baseDn: String, scope: LdapSearchScope, filter: String = "(objectClass=*)",
                attributes: [String]? = nil, includeOperational: Bool = false,
                limit: Int = 0, pageSize: Int = 500, idleTimeout: Int? = nil) {
        self.baseDn = baseDn
        self.scope = scope
        self.filter = filter
        self.attributes = attributes
        self.includeOperational = includeOperational
        self.limit = limit
        self.pageSize = pageSize
        self.idleTimeout = idleTimeout
    }
}

nonisolated public struct LdapSearchProgress: Sendable {
    public var pages: Int
    public var entries: Int
}

nonisolated public struct LdapSearchOutcome: Sendable {
    public var pages: Int
    public var entries: Int
    /// False when the search stopped early: at `limit`, because `onPage`
    /// asked it to, or because the server ignored paging and cut it off.
    public var isComplete: Bool
    /// The server stopped early on its own (it ignored the paging control
    /// and hit its size limit), so the results are a partial set.
    public var wasTruncated: Bool

    /// Throws unless every result was read — for callers that act on a
    /// whole branch (copy, export, counting before a delete) and must not
    /// quietly work on part of it.
    public func requireComplete() throws {
        guard wasTruncated else { return }
        throw ConnectionError.SearchFailed(reason: "the server returned only the first \(entries) entries (its size limit) and ignored the request to page through the rest")
    }
}

/// Runs `request` on a pooled connection and hands each page to `onPage`
/// as it arrives; return false from `onPage` to stop early. Cancelling the
/// calling task abandons the request on the server. Logged as one row,
/// with the page and entry counts.
@discardableResult
public func pagedSearch(_ target: LdapTarget, _ request: LdapSearchRequest,
                        onPage: ([LdapEntry], LdapSearchProgress) async throws -> Bool) async throws -> LdapSearchOutcome {
    var outcome = LdapSearchOutcome(pages: 0, entries: 0, isComplete: true, wasTruncated: false)
    let attrs = request.attributes.map { $0.joined(separator: " ") } ?? "*"
    let detail = """
        base: \(request.baseDn)
        scope: \(request.scope)
        filter: \(request.filter)
        attrs: \(attrs)\(request.includeOperational ? " +" : "")
        """
    try await logged(.search, endpoint: target.endpoint,
                     summary: "search \(request.baseDn) (\(request.scope))",
                     detail: detail,
                     result: { "\(outcome.entries) entr\(outcome.entries == 1 ? "y" : "ies") in \(outcome.pages) page\(outcome.pages == 1 ? "" : "s")\(outcome.wasTruncated ? ", cut short by the server's size limit" : outcome.isComplete ? "" : ", stopped early")" }) {
        try await LdapConnectionPool.shared.withConnection(target) { session in
            // Nothing waits forever on a server that's stopped answering.
            let idleTimeout = request.idleTimeout ?? max(60, target.options.timeoutSeconds * 4)
            outcome = LdapSearchOutcome(pages: 0, entries: 0, isComplete: true, wasTruncated: false)
            let cAttrs = request.attributes ?? []
            let search: OpaquePointer = try await session.call { conn in
                var err = LSError()
                var search: OpaquePointer?
                let cStrings: [UnsafeMutablePointer<CChar>?] = cAttrs.map { strdup($0) }
                defer { cStrings.forEach { free($0) } }
                let rc = cStrings.map { UnsafePointer($0) }.withUnsafeBufferPointer { buf in
                    ls_search_begin(conn, request.baseDn, cScope(request.scope), request.filter,
                                    buf.baseAddress, buf.count, request.includeOperational,
                                    UInt32(clamping: request.pageSize),
                                    UInt32(clamping: idleTimeout), &search, &err)
                }
                guard rc == 0, let search else { return .failure(swiftError(&err)) }
                return .success(search)
            }
            do {
                while true {
                    let page: (entries: [LdapEntry], done: Bool, truncated: Bool) =
                        try await session.call(cancellable: true) { _, cancel in
                            var err = LSError()
                            var out: UnsafeMutablePointer<LSEntry>?
                            var count = 0
                            var done = false
                            var truncated = false
                            let rc = ls_search_next_page(search, cancel, &out, &count, &done, &truncated, &err)
                            guard rc == 0 else { return .failure(swiftError(&err)) }
                            var entries: [LdapEntry] = []
                            if let out {
                                entries.reserveCapacity(count)
                                for i in 0..<count { entries.append(convert(out + i)) }
                                ls_entries_free(out, count)
                            }
                            return .success((entries, done, truncated))
                        }
                    session.markCommitted()
                    outcome.pages += 1
                    var entries = page.entries
                    var reachedLimit = false
                    if request.limit > 0, outcome.entries + entries.count >= request.limit {
                        entries = Array(entries.prefix(request.limit - outcome.entries))
                        reachedLimit = !(page.done && outcome.entries + page.entries.count == request.limit)
                    }
                    outcome.entries += entries.count
                    if page.truncated {
                        outcome.isComplete = false
                        outcome.wasTruncated = true
                    }
                    let keepGoing = try await onPage(entries, LdapSearchProgress(pages: outcome.pages,
                                                                                entries: outcome.entries))
                    if reachedLimit || (!keepGoing && !page.done) {
                        outcome.isComplete = false
                        break
                    }
                    if page.done { break }
                    try Task.checkCancellation()
                }
            } catch {
                await session.finish(search: search)
                throw error
            }
            await session.finish(search: search)
        }
    }
    return outcome
}

nonisolated public struct LdapSearchResult: Sendable {
    public var entries: [LdapEntry]
    /// False when `limit` cut the results short (or the server did).
    public var isComplete: Bool
    /// The server cut them short — see `LdapSearchOutcome.wasTruncated`.
    public var wasTruncated: Bool
}

/// Collects every page of `request` into one array.
public func searchAll(_ target: LdapTarget, _ request: LdapSearchRequest) async throws -> LdapSearchResult {
    var entries: [LdapEntry] = []
    let outcome = try await pagedSearch(target, request) { page, _ in
        entries.append(contentsOf: page)
        return true
    }
    return LdapSearchResult(entries: entries, isComplete: outcome.isComplete,
                            wasTruncated: outcome.wasTruncated)
}

/// One entry by DN with all its user attributes, or nil if it doesn't
/// exist (or isn't visible to this bind).
public func fetchEntry(_ target: LdapTarget, dn: String, attributes: [String]? = nil,
                       includeOperational: Bool = false) async throws -> LdapEntry? {
    do {
        return try await searchAll(target, LdapSearchRequest(
            baseDn: dn, scope: .base, attributes: attributes,
            includeOperational: includeOperational, pageSize: 0
        )).entries.first
    } catch ConnectionError.SearchFailed(let reason) where reason == noSuchObjectReason {
        return nil
    }
}

/// libldap's text for result code 32 — what a base search on a DN that
/// doesn't exist fails with.
nonisolated let noSuchObjectReason = String(cString: ls_ldap_error_text(32))

public func searchDirectory(host: String, port: UInt16, useSsl: Bool,
                            startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                            options: LDAPConnectionOptions? = nil,
                            bindDn: String, password: String, baseDn: String,
                            scope: LdapSearchScope, filter: String,
                            includeOperational: Bool = false,
                            limit: Int = 0) async throws -> [LdapEntry] {
    let target = LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                            pinnedCertSHA256: pinnedCertSHA256, options: options,
                            bindDn: bindDn, password: password)
    return try await searchAll(target, LdapSearchRequest(
        baseDn: baseDn, scope: scope, filter: filter,
        includeOperational: includeOperational, limit: limit,
        pageSize: scope == .base ? 0 : 500
    )).entries
}

public func fetchSchema(_ target: LdapTarget) async throws -> LdapSchema {
    try await logged(.schema, endpoint: target.endpoint,
                     summary: "load schema",
                     detail: "base: cn=Subschema\nscope: base\nattrs: objectClasses attributeTypes") {
        try await LdapConnectionPool.shared.withConnection(target) { session in
            try await session.call { conn in
                var err = LSError()
                var out: UnsafeMutablePointer<LSSchema>?
                let rc = ls_fetch_schema(conn, &out, &err)
                guard rc == 0, let out else { return .failure(swiftError(&err)) }
                let v = out.pointee
                var classes: [SchemaObjectClass] = []
                if let p = v.object_classes, v.object_class_count > 0 {
                    classes.reserveCapacity(v.object_class_count)
                    for i in 0..<v.object_class_count { classes.append(convert(objectClass: p[i])) }
                }
                var attrs: [SchemaAttributeType] = []
                if let p = v.attribute_types, v.attribute_type_count > 0 {
                    attrs.reserveCapacity(v.attribute_type_count)
                    for i in 0..<v.attribute_type_count { attrs.append(convert(attributeType: p[i])) }
                }
                ls_schema_free(out)
                return .success(LdapSchema(objectClasses: classes, attributeTypes: attrs))
            }
        }
    }
}

public func fetchSchema(host: String, port: UInt16, useSsl: Bool,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        options: LDAPConnectionOptions? = nil,
                        bindDn: String, password: String) async throws -> LdapSchema {
    try await fetchSchema(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password))
}

// MARK: Writes

/// Runs one write on a pooled connection, logged. Blocked up front on a
/// read-only connection.
private func write(_ target: LdapTarget, readOnly: Bool, kind: OperationLog.Kind,
                   summary: String, detail: String,
                   _ work: @escaping (OpaquePointer, inout LSError) -> Int32) async throws {
    guard !readOnly else { throw ConnectionError.ReadOnly }
    try await logged(kind, endpoint: target.endpoint, summary: summary, detail: detail) {
        try await LdapConnectionPool.shared.withConnection(target, isWrite: true) { session in
            try await session.call { conn in
                var err = LSError()
                let rc = work(conn, &err)
                return rc == 0 ? .success(()) : .failure(swiftError(&err))
            }
        }
    }
}

public func deleteEntry(_ target: LdapTarget, readOnly: Bool, dn: String) async throws {
    try await write(target, readOnly: readOnly, kind: .delete,
                    summary: "delete \(dn)", detail: "dn: \(dn)") { conn, err in
        ls_delete_entry(conn, dn, &err)
    }
}

public func renameEntry(_ target: LdapTarget, readOnly: Bool, dn: String,
                        newRDN: String, deleteOldRDN: Bool, newSuperior: String?) async throws {
    let isMove = newSuperior != nil && newRDN == DN.rdn(of: dn)
    try await write(target, readOnly: readOnly, kind: .rename,
                    summary: isMove ? "move \(dn)" : "rename \(dn)",
                    detail: isMove
                        ? "dn: \(dn)\nnew superior: \(newSuperior ?? "")"
                        : "dn: \(dn)\nnew RDN: \(newRDN)\ndelete old RDN: \(deleteOldRDN)\nnew superior: \(newSuperior ?? "(same)")") { conn, err in
        ls_rename_entry(conn, dn, newRDN, deleteOldRDN, newSuperior ?? "", &err)
    }
}

nonisolated public enum LdapModKind: Sendable {
    case add, delete, replace
    fileprivate var c: LSModKind {
        switch self {
        case .add: return LS_MOD_ADD
        case .delete: return LS_MOD_DELETE
        case .replace: return LS_MOD_REPLACE
        }
    }
}

nonisolated public struct LdapModOp: Sendable {
    public let kind: LdapModKind
    public let attribute: String
    /// Empty for a whole-attribute delete / replace-with-nothing.
    public let values: [(value: String, isBinary: Bool)]

    public init(kind: LdapModKind, attribute: String,
                values: [(value: String, isBinary: Bool)]) {
        self.kind = kind
        self.attribute = attribute
        self.values = values
    }
}

/// One LDAP Modify with every op applied together (LDIF `changetype: modify`).
public func modifyEntry(_ target: LdapTarget, readOnly: Bool, dn: String, ops: [LdapModOp],
                        summary: String? = nil, detail: String? = nil) async throws {
    try await write(target, readOnly: readOnly, kind: .modify,
                    summary: summary ?? "modify \(dn) (\(ops.count) op\(ops.count == 1 ? "" : "s"))",
                    detail: detail ?? ("dn: \(dn)\n" + ops.map { "\($0.kind) \($0.attribute)" }.joined(separator: "\n"))) { conn, err in
        let flatValues = ops.flatMap(\.values)
        let valueStrings = flatValues.map { strdup($0.value) }
        let attrStrings: [UnsafeMutablePointer<CChar>] = ops.map { strdup($0.attribute)! }
        let emptyName = strdup("")
        defer {
            valueStrings.forEach { free($0) }
            attrStrings.forEach { free($0) }
            free(emptyName)
        }

        var cValues: [LSAttribute] = []
        cValues.reserveCapacity(flatValues.count)
        for (i, v) in flatValues.enumerated() {
            cValues.append(LSAttribute(name: emptyName, value: valueStrings[i], is_binary: v.isBinary))
        }

        var offsets: [Int] = []
        var running = 0
        for op in ops {
            offsets.append(running)
            running += op.values.count
        }

        return cValues.withUnsafeBufferPointer { valBuf in
            var cOps: [LSModOp] = []
            cOps.reserveCapacity(ops.count)
            for (i, op) in ops.enumerated() {
                let n = op.values.count
                let base: UnsafePointer<LSAttribute>? =
                    n == 0 ? nil : valBuf.baseAddress.map { $0 + offsets[i] }
                cOps.append(LSModOp(kind: op.kind.c,
                                    attribute: UnsafePointer(attrStrings[i]),
                                    values: base,
                                    value_count: n))
            }
            return cOps.withUnsafeBufferPointer { opBuf in
                ls_modify_entry(conn, dn, opBuf.baseAddress, opBuf.count, &err)
            }
        }
    }
}

public func addEntry(_ target: LdapTarget, readOnly: Bool, dn: String,
                     attributes: [LdapAttribute]) async throws {
    try await write(target, readOnly: readOnly, kind: .add,
                    summary: "add \(dn)",
                    detail: "dn: \(dn)\nattributes: \(attributes.map(\.name).joined(separator: ", "))") { conn, err in
        // Build a C LSAttribute[] whose char* fields stay valid for the call.
        let names = attributes.map { strdup($0.name) }
        let values = attributes.map { strdup($0.value) }
        defer {
            names.forEach { free($0) }
            values.forEach { free($0) }
        }
        var cAttrs: [LSAttribute] = []
        cAttrs.reserveCapacity(attributes.count)
        for (i, a) in attributes.enumerated() {
            cAttrs.append(LSAttribute(name: names[i], value: values[i], is_binary: a.isBinary))
        }
        return cAttrs.withUnsafeBufferPointer { buf in
            ls_add_entry(conn, dn, buf.baseAddress, buf.count, &err)
        }
    }
}

// MARK: Writes — the call shapes the views already use

public func deleteEntry(host: String, port: UInt16, useSsl: Bool,
                        readOnly: Bool = false,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        options: LDAPConnectionOptions? = nil,
                        bindDn: String, password: String, dn: String) async throws {
    try await deleteEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn)
}

public func addAttributeValue(host: String, port: UInt16, useSsl: Bool,
                              readOnly: Bool = false,
                              startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                              options: LDAPConnectionOptions? = nil,
                              bindDn: String, password: String, dn: String,
                              attribute: String, value: String) async throws {
    try await modifyEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn,
                          ops: [LdapModOp(kind: .add, attribute: attribute, values: [(value, false)])],
                          summary: "add value: \(attribute) on \(dn)",
                          detail: "dn: \(dn)\nadd: \(attribute) = \(abbrev(value))")
}

/// Targeted delete-then-add of just this value, so other values of a
/// multi-valued attribute survive (a plain Replace would wipe them).
public func modifyAttributeValue(host: String, port: UInt16, useSsl: Bool,
                                 readOnly: Bool = false,
                                 startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                                 options: LDAPConnectionOptions? = nil,
                                 bindDn: String, password: String, dn: String,
                                 attribute: String, oldValue: String, newValue: String,
                                 isBinary: Bool) async throws {
    try await modifyEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn,
                          ops: [LdapModOp(kind: .delete, attribute: attribute, values: [(oldValue, isBinary)]),
                                LdapModOp(kind: .add, attribute: attribute, values: [(newValue, isBinary)])],
                          summary: "replace: \(attribute) on \(dn)",
                          detail: "dn: \(dn)\n\(attribute): \(abbrev(oldValue)) -> \(abbrev(newValue))")
}

/// Replace every value of `attribute` with the single `value` (LDAP
/// Replace) — for effectively single-valued attributes like jpegPhoto.
public func setAttributeValue(host: String, port: UInt16, useSsl: Bool,
                              readOnly: Bool = false,
                              startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                              options: LDAPConnectionOptions? = nil,
                              bindDn: String, password: String, dn: String,
                              attribute: String, value: String, isBinary: Bool) async throws {
    try await modifyEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn,
                          ops: [LdapModOp(kind: .replace, attribute: attribute, values: [(value, isBinary)])],
                          summary: "set: \(attribute) on \(dn)",
                          detail: "dn: \(dn)\nreplace: \(attribute) = \(abbrev(value))")
}

public func deleteAttributeValue(host: String, port: UInt16, useSsl: Bool,
                                 readOnly: Bool = false,
                                 startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                                 options: LDAPConnectionOptions? = nil,
                                 bindDn: String, password: String, dn: String,
                                 attribute: String, value: String, isBinary: Bool) async throws {
    try await modifyEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn,
                          ops: [LdapModOp(kind: .delete, attribute: attribute, values: [(value, isBinary)])],
                          summary: "delete value: \(attribute) on \(dn)",
                          detail: "dn: \(dn)\ndelete: \(attribute) = \(abbrev(value))")
}

/// Moves `dn` (and, on the server, everything under it) beneath
/// `newSuperior`, keeping its RDN.
public func moveEntry(host: String, port: UInt16, useSsl: Bool,
                      readOnly: Bool = false,
                      startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                      options: LDAPConnectionOptions? = nil,
                      bindDn: String, password: String,
                      dn: String, newSuperior: String) async throws {
    try await renameEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn, newRDN: DN.rdn(of: dn),
                          deleteOldRDN: true, newSuperior: newSuperior)
}

/// Rename / relocate an entry (LDAP ModifyDN). `newSuperior` nil keeps the
/// current parent. Used by the LDIF editor's `changetype: modrdn`.
public func renameEntry(host: String, port: UInt16, useSsl: Bool,
                        readOnly: Bool = false,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        options: LDAPConnectionOptions? = nil,
                        bindDn: String, password: String, dn: String,
                        newRDN: String, deleteOldRDN: Bool,
                        newSuperior: String?) async throws {
    try await renameEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn, newRDN: newRDN,
                          deleteOldRDN: deleteOldRDN, newSuperior: newSuperior)
}

public func modifyEntry(host: String, port: UInt16, useSsl: Bool,
                        readOnly: Bool = false,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        options: LDAPConnectionOptions? = nil,
                        bindDn: String, password: String, dn: String,
                        ops: [LdapModOp]) async throws {
    try await modifyEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                     pinnedCertSHA256: pinnedCertSHA256, options: options,
                                     bindDn: bindDn, password: password),
                          readOnly: readOnly, dn: dn, ops: ops)
}

public func addEntry(host: String, port: UInt16, useSsl: Bool,
                     readOnly: Bool = false,
                     startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                     options: LDAPConnectionOptions? = nil,
                     bindDn: String, password: String, dn: String,
                     attributes: [LdapAttribute]) async throws {
    try await addEntry(LdapTarget(host: host, port: port, useSsl: useSsl, startTLS: startTLS,
                                  pinnedCertSHA256: pinnedCertSHA256, options: options,
                                  bindDn: bindDn, password: password),
                       readOnly: readOnly, dn: dn, attributes: attributes)
}

public func hashPassword(plaintext: String, scheme: PasswordScheme) throws -> String {
    var err = LSError()
    var out: UnsafeMutablePointer<CChar>?
    let rc = ls_hash_password(plaintext, cScheme(scheme), &out, &err)
    guard rc == 0, let out else { throw swiftError(&err) }
    defer { ls_string_free(out) }
    return String(cString: out)
}

public func resizePhotoToBase64(path: String) throws -> String {
    var err = LSError()
    var out: UnsafeMutablePointer<CChar>?
    let rc = ls_resize_photo_to_base64(path, &out, &err)
    guard rc == 0, let out else { throw swiftError(&err) }
    defer { ls_string_free(out) }
    return String(cString: out)
}

// MARK: - Build info

/// Versions of the bundled native libraries this build links against.
public struct DependencyVersions {
    public let openldap: String
    public let openssl: String
    public let libxcrypt: String
    public let libssh2: String
}

public func dependencyVersions() -> DependencyVersions {
    let v = ls_dependency_versions()
    return DependencyVersions(
        openldap: String(cString: v.openldap),
        openssl: String(cString: v.openssl),
        libxcrypt: String(cString: v.libxcrypt),
        libssh2: String(cString: v.libssh2)
    )
}

/// Call once as the app quits. Closes the pooled connections, then waits briefly for any connection attempt
/// that already timed out but is still unwinding in the background (exiting
/// underneath it can crash during OpenSSL's exit-time cleanup), then closes
/// every SSH tunnel kept warm for reuse so none linger after the app closes.
public func shutdownCore() {
    LdapConnectionPool.shared.closeAll()
    ls_shutdown(2000)
}
