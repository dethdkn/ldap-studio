//
//  LdapConnectionPool.swift
//  ldap-studio
//
//  Keeps bound LDAP connections open between operations. Browsing a large
//  directory lazily means many small searches — one per expanded node, one
//  per selected entry — and paying for TCP + TLS + bind on each would make
//  every click slow, especially over LDAPS or an SSH tunnel.
//
//  Connections are kept per `LdapTarget` (server + credentials + options),
//  so two windows on the same connection share them and editing a saved
//  connection naturally starts fresh ones. Each caller gets a connection to
//  itself for the length of its operation; a few sit idle for reuse and
//  are closed after a short while so the server isn't left holding them.
//

import Foundation

/// Everything needed to reach and bind to one directory as one identity —
/// what pooled connections are shared by.
nonisolated public struct LdapTarget: Hashable, Sendable {
    public var host: String
    public var port: UInt16
    public var useSsl: Bool
    public var startTLS: Bool
    public var pinnedCertSHA256: String?
    public var options: LDAPConnectionOptions
    public var bindDn: String
    public var password: String

    public init(host: String, port: UInt16, useSsl: Bool, startTLS: Bool = false,
                pinnedCertSHA256: String? = nil, options: LDAPConnectionOptions? = nil,
                bindDn: String, password: String) {
        self.host = host
        self.port = port
        self.useSsl = useSsl
        self.startTLS = startTLS
        self.pinnedCertSHA256 = pinnedCertSHA256
        self.options = options ?? LDAPConnectionOptions()
        self.bindDn = bindDn
        self.password = password
    }

    /// "host:port" — how the Operation Log groups rows by server.
    public var endpoint: String { "\(host):\(port)" }
}

/// Blocking calls on pooled connections run here, several at once — unlike
/// opening a connection, which has to go through the serial core queue.
nonisolated let ldapWorkQueue = DispatchQueue(label: "app.ldap-studio.native-core.work",
                                              qos: .userInitiated, attributes: .concurrent)

/// An `LSCancel` freed only once nothing can trigger it anymore — the
/// cancellation handler and the blocking call each hold a reference.
nonisolated private final class CancelFlag: @unchecked Sendable {
    let pointer: OpaquePointer = ls_cancel_new()
    func trigger() { ls_cancel_trigger(pointer) }
    deinit { ls_cancel_free(pointer) }
}

/// One checked-out connection, for the length of one operation.
nonisolated final class LdapSession: @unchecked Sendable {
    fileprivate let handle: OpaquePointer
    /// Set once results have been handed back to the caller; after that a
    /// lost connection can't be quietly retried without repeating them.
    private(set) var isCommitted = false

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    func markCommitted() { isCommitted = true }

    /// Runs a blocking C call on this connection, off the main thread.
    func call<T>(_ work: @escaping (OpaquePointer) -> Result<T, Error>) async throws -> T {
        nonisolated(unsafe) let handle = handle
        return try await withCheckedThrowingContinuation { continuation in
            ldapWorkQueue.async {
                continuation.resume(with: work(handle))
            }
        }
    }

    /// Same, passing an `LSCancel` that fires when the calling task is
    /// cancelled — for searches, which check it while they wait.
    func call<T>(cancellable: Bool,
                 _ work: @escaping (OpaquePointer, OpaquePointer) -> Result<T, Error>) async throws -> T {
        let flag = CancelFlag()
        return try await withTaskCancellationHandler {
            try await call { handle in work(handle, flag.pointer) }
        } onCancel: {
            flag.trigger()
        }
    }

    /// Whether the server still answers on this connection: a base search
    /// of the root DSE asking for no attributes. A failure marks the
    /// connection broken, so releasing it closes it.
    func isAlive() async -> Bool {
        (try? await call { conn in
            var err = LSError()
            var search: OpaquePointer?
            _ = "1.1".withCString { noAttributes in
                [Optional(noAttributes)].withUnsafeBufferPointer { buf in
                    ls_search_begin(conn, "", LS_SCOPE_BASE, "(objectClass=*)", buf.baseAddress, 1,
                                    false, 0, 10, &search, &err)
                }
            }
            guard let search else { return .success(false) }
            defer { ls_search_free(search) }
            var out: UnsafeMutablePointer<LSEntry>?
            var count = 0
            var done = false
            var truncated = false
            let rc = ls_search_next_page(search, nil, &out, &count, &done, &truncated, &err)
            if rc == 0 { ls_entries_free(out, count) } else { ls_error_dispose(&err) }
            return .success(rc == 0)
        }) ?? false
    }

    /// Ends a search begun on this connection. Awaited, so the connection
    /// isn't handed to anyone else while the search is still tidying up.
    func finish(search: OpaquePointer) async {
        _ = try? await call { _ in
            ls_search_free(search)
            return .success(())
        }
    }
}

nonisolated final class LdapConnectionPool: @unchecked Sendable {
    static let shared = LdapConnectionPool()

    /// At most this many connections per target are in use at once; more
    /// callers wait their turn. Enough for several expands, an entry load
    /// and a long export side by side, without flooding the server when
    /// something (resolving a big group's members) fires off hundreds of
    /// lookups.
    private static let maxInUsePerTarget = 6
    /// Idle connections kept per target for reuse.
    private static let maxIdlePerTarget = 4
    /// Comfortably below typical server idle timeouts (Active Directory's
    /// MaxConnIdleTime is 900s).
    private static let idleLifetime: TimeInterval = 90

    private struct Idle {
        let handle: OpaquePointer
        let since: Date
    }

    private let lock = NSLock()
    private var idle: [LdapTarget: [Idle]] = [:]
    private var inUse: [LdapTarget: Int] = [:]
    private var waiters: [LdapTarget: [CheckedContinuation<Void, Never>]] = [:]
    private var reaper: DispatchSourceTimer?

    /// A write on a connection that's sat idle this long first checks the
    /// connection is still there — see `withConnection`.
    private static let probeAfterIdle: TimeInterval = 5

    /// Runs `body` on a connection to `target` — a pooled one if available,
    /// otherwise a newly opened one.
    ///
    /// A reused connection may have been dropped by the server while idle.
    /// For a read, that's handled by retrying once on a fresh connection if
    /// `body` hadn't yet committed to any results. A write can't be retried
    /// that way — the server may have applied it before the connection
    /// went — so for `isWrite` an idle connection is probed with a tiny
    /// search first, and a dead one replaced before the write is sent.
    func withConnection<T>(_ target: LdapTarget, isWrite: Bool = false,
                           _ body: (LdapSession) async throws -> T) async throws -> T {
        // A task that already holds a connection to `target` (a copy adding
        // entries while its search is still open) gets another one without
        // waiting for a slot — waiting there could deadlock against itself.
        let nested = Self.heldTargets.contains(target)
        var canRetry = true
        while true {
            let (handle, idleSince) = try await acquire(target, countsTowardLimit: !nested)
            let reused = idleSince != nil
            let session = LdapSession(handle: handle)
            if isWrite, let idleSince, Date().timeIntervalSince(idleSince) > Self.probeAfterIdle,
               !(await session.isAlive()) {
                release(handle, to: target, countsTowardLimit: !nested)
                discardIdle(target)
                continue
            }
            do {
                let value = try await Self.$heldTargets.withValue(Self.heldTargets.union([target])) {
                    try await body(session)
                }
                release(handle, to: target, countsTowardLimit: !nested)
                return value
            } catch {
                release(handle, to: target, countsTowardLimit: !nested)
                if case ConnectionError.ConnectionLost = error, reused, canRetry, !isWrite,
                   !session.isCommitted {
                    // Whatever dropped this one (a server restart, a
                    // network change) most likely dropped its idle
                    // siblings too; retry on a fresh connection.
                    discardIdle(target)
                    canRetry = false
                    continue
                }
                throw error
            }
        }
    }

    /// Closes the idle connections to `target`.
    private func discardIdle(_ target: LdapTarget) {
        lock.lock()
        let handles = idle.removeValue(forKey: target)?.map(\.handle) ?? []
        lock.unlock()
        close(handles)
    }

    /// Closes every idle connection — for quitting.
    func closeAll() {
        lock.lock()
        let handles = idle.values.flatMap { $0.map(\.handle) }
        idle.removeAll()
        lock.unlock()
        handles.forEach { ls_connection_close($0) }
    }

    /// Takes one of the target's in-use slots, waiting for one to free up
    /// if they're all taken.
    private func reserveSlot(_ target: LdapTarget) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let granted = lock.withLock {
                if inUse[target, default: 0] < Self.maxInUsePerTarget {
                    inUse[target, default: 0] += 1
                    return true
                }
                waiters[target, default: []].append(continuation)
                return false
            }
            if granted { continuation.resume() }
        }
    }

    /// Gives a slot back — straight to the next waiter, if there is one.
    private func freeSlot(_ target: LdapTarget) {
        lock.lock()
        if var queue = waiters[target], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[target] = queue.isEmpty ? nil : queue
            lock.unlock()
            next.resume()
        } else {
            inUse[target, default: 1] -= 1
            if inUse[target] == 0 { inUse[target] = nil }
            lock.unlock()
        }
    }

    @TaskLocal private static var heldTargets: Set<LdapTarget> = []

    private func acquire(_ target: LdapTarget,
                         countsTowardLimit: Bool) async throws -> (OpaquePointer, Date?) {
        if countsTowardLimit { await reserveSlot(target) }
        let (reusable, expired) = takeIdle(target)
        close(expired)
        if let reusable { return (reusable.handle, reusable.since) }
        do {
            return (try await openPooledConnection(target), nil)
        } catch {
            if countsTowardLimit { freeSlot(target) }
            throw error
        }
    }

    /// The most recently used idle connection to `target`, if any, plus
    /// any that have sat idle too long (for the caller to close).
    private func takeIdle(_ target: LdapTarget) -> (Idle?, [OpaquePointer]) {
        lock.lock()
        defer { lock.unlock() }
        guard var list = idle[target] else { return (nil, []) }
        let cutoff = Date().addingTimeInterval(-Self.idleLifetime)
        let expired = list.filter { $0.since < cutoff }.map(\.handle)
        list.removeAll { $0.since < cutoff }
        let reusable = list.popLast()
        idle[target] = list.isEmpty ? nil : list
        return (reusable, expired)
    }

    private func release(_ handle: OpaquePointer, to target: LdapTarget,
                         countsTowardLimit: Bool) {
        defer { if countsTowardLimit { freeSlot(target) } }
        guard !ls_connection_is_broken(handle) else {
            close([handle])
            return
        }
        lock.lock()
        var list = idle[target] ?? []
        let keep = list.count < Self.maxIdlePerTarget
        if keep {
            list.append(Idle(handle: handle, since: Date()))
            idle[target] = list
        }
        startReaperIfNeeded()
        lock.unlock()
        if !keep { close([handle]) }
    }

    /// Unbinding sends a request, so it happens off the caller's thread.
    private func close(_ handles: [OpaquePointer]) {
        guard !handles.isEmpty else { return }
        nonisolated(unsafe) let handles = handles
        ldapWorkQueue.async {
            handles.forEach { ls_connection_close($0) }
        }
    }

    /// Called with the lock held.
    private func startReaperIfNeeded() {
        guard reaper == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.reap() }
        timer.resume()
        reaper = timer
    }

    private func reap() {
        lock.lock()
        let cutoff = Date().addingTimeInterval(-Self.idleLifetime)
        var expired: [OpaquePointer] = []
        for (target, list) in idle {
            expired += list.filter { $0.since < cutoff }.map(\.handle)
            let remaining = list.filter { $0.since >= cutoff }
            idle[target] = remaining.isEmpty ? nil : remaining
        }
        lock.unlock()
        close(expired)
    }
}
