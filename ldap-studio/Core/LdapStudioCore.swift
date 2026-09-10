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
//  below run them on a background queue and resume a continuation, which
//  keeps the call sites (`try await fetchRootEntry(...)`) unchanged.
//

import Foundation

// MARK: - Public data types (shapes match the former generated code)

public struct LdapAttribute: Equatable, Hashable {
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

public struct LdapEntry: Equatable, Hashable {
    public var dn: String
    public var name: String
    public var hasChildren: Bool
    public var attributes: [LdapAttribute]
    public var children: [LdapEntry]

    public init(dn: String, name: String, hasChildren: Bool,
                attributes: [LdapAttribute], children: [LdapEntry]) {
        self.dn = dn
        self.name = name
        self.hasChildren = hasChildren
        self.attributes = attributes
        self.children = children
    }
}

public enum LdapSearchScope: Equatable, Hashable {
    case base
    case oneLevel
    case subtree
}

public struct SchemaObjectClass: Equatable, Hashable {
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

public struct SchemaAttributeType: Equatable, Hashable {
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

public struct LdapSchema: Equatable, Hashable {
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

    public var description: String {
        switch self {
        case let .ConnectFailed(host, port, reason):
            return "Could not connect to \(host):\(port): \(reason)"
        case let .ConnectTimedOut(host, port):
            return "Connecting to \(host):\(port) timed out after 15 seconds"
        case let .BindFailed(reason):   return "Bind failed: \(reason)"
        case let .SearchFailed(reason): return "Search failed: \(reason)"
        case let .ModifyFailed(reason): return "Modify failed: \(reason)"
        case let .TLSUntrusted(host, port, reason):
            return "The certificate for \(host):\(port) isn't trusted: \(reason)"
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

private func str(_ p: UnsafePointer<CChar>?) -> String {
    p.map { String(cString: $0) } ?? ""
}

private func optStr(_ p: UnsafePointer<CChar>?) -> String? {
    p.map { String(cString: $0) }
}

private func strArray(_ p: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, _ n: Int) -> [String] {
    guard let p, n > 0 else { return [] }
    return (0..<n).map { String(cString: p[$0]!) }
}

/// Turns a populated `LSError` into the matching Swift error and disposes
/// the strings it owns.
private func swiftError(_ err: inout LSError) -> Error {
    defer { ls_error_dispose(&err) }
    let host = str(err.host)
    let reason = str(err.reason)
    switch err.kind {
    case LS_CONNECT_FAILED:    return ConnectionError.ConnectFailed(host: host, port: err.port, reason: reason)
    case LS_CONNECT_TIMED_OUT: return ConnectionError.ConnectTimedOut(host: host, port: err.port)
    case LS_TLS_UNTRUSTED:     return ConnectionError.TLSUntrusted(host: host, port: err.port, reason: reason)
    case LS_BIND_FAILED:       return ConnectionError.BindFailed(reason: reason)
    case LS_SEARCH_FAILED:     return ConnectionError.SearchFailed(reason: reason)
    case LS_MODIFY_FAILED:     return ConnectionError.ModifyFailed(reason: reason)
    case LS_HASH_FAILED:       return PasswordError.HashFailed(reason: reason)
    case LS_DECODE_FAILED:     return PhotoError.DecodeFailed(reason: reason)
    case LS_ENCODE_FAILED:     return PhotoError.EncodeFailed(reason: reason)
    default:                   return ConnectionError.SearchFailed(reason: reason.isEmpty ? "unknown error" : reason)
    }
}

private func convert(_ e: UnsafePointer<LSEntry>) -> LdapEntry {
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
    var children: [LdapEntry] = []
    if let cp = v.children, v.child_count > 0 {
        children.reserveCapacity(v.child_count)
        for i in 0..<v.child_count { children.append(convert(cp + i)) }
    }
    return LdapEntry(dn: str(v.dn), name: str(v.name),
                     hasChildren: v.has_children,
                     attributes: attributes, children: children)
}

private func convert(objectClass o: LSObjectClass) -> SchemaObjectClass {
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

private func convert(attributeType a: LSAttributeType) -> SchemaAttributeType {
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

private func cScope(_ s: LdapSearchScope) -> LSScope {
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

/// Runs a blocking C call off the main thread and bridges it to `async`.
private func background<T>(_ work: @escaping () -> Result<T, Error>) async throws -> T {
    _ = installBundledCACert
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: work())
        }
    }
}

/// Same, but pushes this connection's TLS policy (StartTLS, pinned cert)
/// into the C layer first — it's sticky global state that the next
/// connect reads, so every operation sets it explicitly, which also
/// resets it for the plain-`ldap://` and plain-`ldaps://` callers that
/// pass the defaults.
private func background<T>(startTLS: Bool, pinnedCertSHA256: String?,
                          _ work: @escaping () -> Result<T, Error>) async throws -> T {
    try await background {
        setTLSPolicy(startTLS: startTLS,
                     allowUntrusted: pinnedCertSHA256 != nil,
                     pinnedCertSHA256: pinnedCertSHA256)
        return work()
    }
}

/// Sets the per-connection TLS policy in the C core. `allowUntrusted`
/// only makes sense together with a pin (verification off, the pin is
/// what's trusted); with no pin it's plain chain verification.
public func setTLSPolicy(startTLS: Bool, allowUntrusted: Bool, pinnedCertSHA256: String?) {
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

// MARK: - Public API (same signatures the app already calls)

public func testConnection(host: String, port: UInt16, useSsl: Bool,
                           startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                           bindDn: String, password: String) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_test_connection(host, port, useSsl, bindDn, password, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func fetchRootEntry(host: String, port: UInt16, useSsl: Bool,
                           startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                           bindDn: String, password: String,
                           baseDn: String) async throws -> LdapEntry {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        var out: UnsafeMutablePointer<LSEntry>?
        let rc = ls_fetch_root_entry(host, port, useSsl, bindDn, password, baseDn, &out, &err)
        guard rc == 0, let out else { return .failure(swiftError(&err)) }
        let entry = convert(out)
        ls_entry_free(out)
        return .success(entry)
    }
}

public func searchDirectory(host: String, port: UInt16, useSsl: Bool,
                            startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                            bindDn: String, password: String, baseDn: String,
                            scope: LdapSearchScope, filter: String) async throws -> [LdapEntry] {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        var out: UnsafeMutablePointer<LSEntry>?
        var count = 0
        let rc = ls_search_directory(host, port, useSsl, bindDn, password, baseDn,
                                     cScope(scope), filter, &out, &count, &err)
        guard rc == 0 else { return .failure(swiftError(&err)) }
        var results: [LdapEntry] = []
        if let out {
            results.reserveCapacity(count)
            for i in 0..<count { results.append(convert(out + i)) }
            ls_entries_free(out, count)
        }
        return .success(results)
    }
}

public func fetchSchema(host: String, port: UInt16, useSsl: Bool,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        bindDn: String, password: String) async throws -> LdapSchema {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        var out: UnsafeMutablePointer<LSSchema>?
        let rc = ls_fetch_schema(host, port, useSsl, bindDn, password, &out, &err)
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

public func deleteEntry(host: String, port: UInt16, useSsl: Bool,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        bindDn: String, password: String, dn: String) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_delete_entry(host, port, useSsl, bindDn, password, dn, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func addAttributeValue(host: String, port: UInt16, useSsl: Bool,
                              startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                              bindDn: String, password: String, dn: String,
                              attribute: String, value: String) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_add_attribute_value(host, port, useSsl, bindDn, password,
                                        dn, attribute, value, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func modifyAttributeValue(host: String, port: UInt16, useSsl: Bool,
                                 startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                                 bindDn: String, password: String, dn: String,
                                 attribute: String, oldValue: String, newValue: String,
                                 isBinary: Bool) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_modify_attribute_value(host, port, useSsl, bindDn, password,
                                           dn, attribute, oldValue, newValue, isBinary, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func setAttributeValue(host: String, port: UInt16, useSsl: Bool,
                              startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                              bindDn: String, password: String, dn: String,
                              attribute: String, value: String, isBinary: Bool) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_set_attribute_value(host, port, useSsl, bindDn, password,
                                        dn, attribute, value, isBinary, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func deleteAttributeValue(host: String, port: UInt16, useSsl: Bool,
                                 startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                                 bindDn: String, password: String, dn: String,
                                 attribute: String, value: String, isBinary: Bool) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_delete_attribute_value(host, port, useSsl, bindDn, password,
                                           dn, attribute, value, isBinary, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func moveEntry(host: String, port: UInt16, useSsl: Bool,
                      startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                      bindDn: String, password: String,
                      dn: String, newSuperior: String) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_move_entry(host, port, useSsl, bindDn, password, dn, newSuperior, &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func renameEntry(host: String, port: UInt16, useSsl: Bool,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        bindDn: String, password: String, dn: String,
                        newRDN: String, deleteOldRDN: Bool,
                        newSuperior: String?) async throws {
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc = ls_rename_entry(host, port, useSsl, bindDn, password, dn,
                                 newRDN, deleteOldRDN, newSuperior ?? "", &err)
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public enum LdapModKind {
    case add, delete, replace
    fileprivate var c: LSModKind {
        switch self {
        case .add: return LS_MOD_ADD
        case .delete: return LS_MOD_DELETE
        case .replace: return LS_MOD_REPLACE
        }
    }
}

public struct LdapModOp {
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
public func modifyEntry(host: String, port: UInt16, useSsl: Bool,
                        startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                        bindDn: String, password: String, dn: String,
                        ops: [LdapModOp]) async throws {
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

    let count = ops.count
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc: Int32 = cValues.withUnsafeBufferPointer { valBuf in
            var cOps: [LSModOp] = []
            cOps.reserveCapacity(count)
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
                ls_modify_entry(host, port, useSsl, bindDn, password, dn,
                                opBuf.baseAddress, opBuf.count, &err)
            }
        }
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
}

public func addEntry(host: String, port: UInt16, useSsl: Bool,
                     startTLS: Bool = false, pinnedCertSHA256: String? = nil,
                     bindDn: String, password: String, dn: String,
                     attributes: [LdapAttribute]) async throws {
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

    let count = cAttrs.count
    try await background(startTLS: startTLS, pinnedCertSHA256: pinnedCertSHA256) {
        var err = LSError()
        let rc: Int32 = cAttrs.withUnsafeBufferPointer { buf in
            ls_add_entry(host, port, useSsl, bindDn, password, dn,
                         buf.baseAddress, count, &err)
        }
        return rc == 0 ? .success(()) : .failure(swiftError(&err))
    }
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
}

public func dependencyVersions() -> DependencyVersions {
    let v = ls_dependency_versions()
    return DependencyVersions(
        openldap: String(cString: v.openldap),
        openssl: String(cString: v.openssl),
        libxcrypt: String(cString: v.libxcrypt)
    )
}
