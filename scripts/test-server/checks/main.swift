// Checks the lazy tree, paged searches, connection pool and branch
// operations against the test server (see ../run.sh). Run with ../check.sh.
// Writes go under ou=Empty / ou=Deep and are removed again.
import Foundation

func ms(_ d: Duration) -> String { String(format: "%.0f ms", Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000) }
func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures += 1 } }
var failures = 0
let clock = ContinuousClock()

func connection(_ bind: String, _ pw: String, base: String = "dc=example,dc=com", readOnly: Bool = false) -> SavedConnection {
    let c = SavedConnection(name: "t", host: "127.0.0.1", port: 3389, useSSL: false, baseDN: base, bindDN: bind, isReadOnly: readOnly)
    KeychainService.passwords[c.id] = pw
    return c
}

@MainActor func run() async {
    let reader = connection("cn=reader,ou=Service,dc=example,dc=com", "reader")
    let tree = DirectoryTree(connection: reader)

    var t0 = clock.now
    await tree.loadRoot()
    check(tree.root != nil && tree.rootError == nil, "open: root loaded in \(ms(clock.now - t0))")
    if let root = tree.root { await tree.retryWait(root) }
    print("   top-level children:", tree.root?.children.map(\.name) ?? [])
    check(tree.root?.children.count == 8, "open: 8 top-level children")
    let people = tree.node("ou=People,dc=example,dc=com")!
    let empty = tree.node("ou=Empty,dc=example,dc=com")!
    check(people.showsDisclosure && !empty.showsDisclosure, "arrows: People has one, Empty (hasSubordinates FALSE) does not")

    // expand People: first page time, full load time
    t0 = clock.now
    tree.setExpanded(people, true)
    while people.children.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
    print("   People first batch: \(people.children.count) after \(ms(clock.now - t0))")
    while people.childrenState != .loaded { try? await Task.sleep(for: .milliseconds(20)); if case .failed = people.childrenState { break } }
    check(people.children.count == 76_000, "People: all 76,000 children in \(ms(clock.now - t0))")
    check(people.visibleChildren.count == 1000 && people.hiddenChildCount == 75_000, "People: draws 1,000, 75,000 behind Show More")
    let firstUser = people.children[0]
    check(!firstUser.showsDisclosure, "leaf users have no arrow")
    check(people.children.map(\.sortKey) == people.children.map(\.sortKey).sorted(), "People children sorted")

    // cancel on collapse
    let groups = tree.node("ou=Groups,dc=example,dc=com")!
    tree.setExpanded(groups, true)
    tree.setExpanded(groups, false)
    check(groups.childrenState == .notLoaded, "collapse while loading cancels the load")

    // per-node error
    let restricted = tree.node("ou=Restricted,dc=example,dc=com")!
    tree.setExpanded(restricted, true)
    while restricted.childrenState == .loading { try? await Task.sleep(for: .milliseconds(5)) }
    if case let .failed(msg) = restricted.childrenState { check(true, "Restricted fails on its own: \(msg)") } else { check(false, "Restricted should fail") }
    check(tree.root?.childrenState == .loaded && people.childrenState == .loaded, "rest of tree unaffected")

    // rapid collapse / re-expand must end with the newest load's result
    let computers = tree.node("ou=Computers,dc=example,dc=com")!
    for _ in 0..<5 { tree.setExpanded(computers, true); try? await Task.sleep(for: .milliseconds(30)); tree.setExpanded(computers, false) }
    tree.setExpanded(computers, true)
    while computers.childrenState != .loaded { try? await Task.sleep(for: .milliseconds(20)) }
    try? await Task.sleep(for: .milliseconds(500))
    check(computers.children.count == 22_000 && computers.childrenState == .loaded, "rapid collapse/expand ends with all 22,000 computers")

    // reveal deep + beyond display limit
    t0 = clock.now
    let deep = "uid=deep30x1,ou=Level29,ou=Level28,ou=Level27,ou=Level26,ou=Level25,ou=Level24,ou=Level23,ou=Level22,ou=Level21,ou=Level20,ou=Level19,ou=Level18,ou=Level17,ou=Level16,ou=Level15,ou=Level14,ou=Level13,ou=Level12,ou=Level11,ou=Level10,ou=Level09,ou=Level08,ou=Level07,ou=Level06,ou=Level05,ou=Level04,ou=Level03,ou=Level02,ou=Level01,ou=Deep,dc=example,dc=com"
    do {
        let r = try await tree.reveal(deep.uppercased().replacingOccurrences(of: ",", with: ", "))
        check(r == deep, "reveal 31-level-deep DN typed in caps with spaces (\(ms(clock.now - t0)))")
    } catch { check(false, "reveal deep: \(error)") }
    do {
        let r = try await tree.reveal("uid=user075999,ou=People,dc=example,dc=com")
        check(people.visibleChildren.contains { $0.dn == r }, "reveal entry #76,000 pins it into the drawn rows")
    } catch { check(false, "reveal user075999: \(error)") }
    do { _ = try await tree.reveal("uid=nobody,ou=People,dc=example,dc=com"); check(false, "missing should throw") }
    catch { check(true, "reveal missing DN: \(error.localizedDescription)") }
    do { _ = try await tree.reveal("dc=other,dc=org"); check(false, "outside should throw") }
    catch { check(true, "reveal outside base: \(error.localizedDescription)") }

    // refresh all keeps expansion
    let expandedBefore = Set(tree.allExpanded())
    t0 = clock.now
    await tree.refreshAll()
    let expandedAfter = Set(tree.allExpanded())
    check(expandedBefore == expandedAfter && !expandedAfter.isEmpty, "refresh all keeps \(expandedAfter.count) expanded nodes (\(ms(clock.now - t0)))")
    check(tree.node(deep) != nil && people.children.count == 76_000, "refresh keeps deep node and People")

    // quick search
    t0 = clock.now
    let qs = try! await searchAll(tree.target, LdapSearchRequest(baseDn: "dc=example,dc=com", scope: .subtree,
        filter: "(|(cn=User 0001*)(uid=user0001*))", attributes: ["objectClass"], limit: 200))
    check(qs.entries.count == 200 && !qs.isComplete, "quick search stops at 200 (\(ms(clock.now - t0)))")
    let qs2 = try! await searchAll(tree.target, LdapSearchRequest(baseDn: "dc=example,dc=com", scope: .subtree,
        filter: "(uid=deep30*)", attributes: ["objectClass"], limit: 200))
    check(qs2.entries.count == 3 && qs2.isComplete, "quick search finds unloaded deep entries")

    // advanced search, everything
    t0 = clock.now
    var pages = 0
    let out = try! await pagedSearch(tree.target, LdapSearchRequest(baseDn: "dc=example,dc=com", scope: .subtree, filter: "(objectClass=inetOrgPerson)", attributes: ["1.1"])) { _, p in pages = p.pages; return true }
    check(out.entries == 126_090 && out.isComplete, "advanced search: \(out.entries) persons in \(pages) pages (\(ms(clock.now - t0)))")

    let readBinds = OperationLog.shared.entries.filter { $0.kind == .connect }.count
    check(readBinds <= 6, "connections reused: \(readBinds) binds for all the reads above (\(OperationLog.shared.entries.count) log rows)")

    // TLS through the pool: LDAPS with a pinned certificate, and StartTLS
    let pin = ProcessInfo.processInfo.environment["PIN"]!
    var ldaps = connection("cn=reader,ou=Service,dc=example,dc=com", "reader")
    ldaps.port = 3636; ldaps.useSSL = true; ldaps.trustedCertSHA256 = pin
    KeychainService.passwords[ldaps.id] = "reader"
    let e1 = try? await fetchEntry(ldaps.ldapTarget, dn: "dc=example,dc=com")
    check(e1 != nil, "LDAPS with pinned certificate")
    ldaps.trustedCertSHA256 = String(repeating: "0", count: 64)
    do { _ = try await fetchEntry(ldaps.ldapTarget, dn: "dc=example,dc=com"); check(false, "wrong pin should fail") }
    catch { check("\(error)".contains("isn't trusted"), "LDAPS with wrong pin refused: \(error)") }
    var stls = connection("cn=reader,ou=Service,dc=example,dc=com", "reader")
    stls.useStartTLS = true; stls.trustedCertSHA256 = pin
    KeychainService.passwords[stls.id] = "reader"
    let e2 = try? await fetchEntry(stls.ldapTarget, dn: "dc=example,dc=com")
    check(e2 != nil, "StartTLS with pinned certificate")

    // cancel a search
    let task = Task { try await searchAll(tree.target, LdapSearchRequest(baseDn: "dc=example,dc=com", scope: .subtree)) }
    try? await Task.sleep(for: .milliseconds(150))
    task.cancel()
    do { _ = try await task.value; check(false, "cancel should throw") } catch { check(error is CancellationError, "cancelled search throws CancellationError") }
    let after = try? await searchAll(tree.target, LdapSearchRequest(baseDn: "ou=Groups,dc=example,dc=com", scope: .oneLevel, attributes: ["1.1"]))
    check(after?.entries.count == 2000, "pooled connection still good after a cancelled paged search")

    // DN parsing
    check(DN.components("cn=Smith\\, John,ou=People,dc=x") == ["cn=Smith\\, John", "ou=People", "dc=x"], "DN: escaped comma stays in its RDN")
    check(DN.components("cn=foo\\ ,ou=x") == ["cn=foo\\ ", "ou=x"], "DN: escaped trailing space kept")
    check(DN.same("cn=a\\2Cb,DC=X", "CN=A\\,B, dc=x"), "DN: \\2C and \\, compare equal")
    check(!DN.same("cn=a,b=c", "cn=a\\,b=c"), "DN: escaped and real commas differ")
    check(DN.isWithin("uid=a,ou=People,dc=x", "OU=people, DC=X") && !DN.isWithin("ou=Peoplex,dc=x", "ou=People,dc=x"), "DN: isWithin")
    let k = DN.normalize
    check(DN.keyIsWithin(k("uid=a,ou=P,dc=x"), k("ou=P,dc=x")) && DN.keyIsWithin(k("ou=P,dc=x"), k("ou=P,dc=x"))
          && !DN.keyIsWithin(k("ou=XP,dc=x"), k("ou=P,dc=x")) && !DN.keyIsWithin(k("cn=a\\,ou=P,dc=x"), k("ou=P,dc=x")),
          "DN: keyIsWithin respects RDN boundaries and escaped commas")

    // writes as manager
    let manager = connection("cn=manager,ou=Service,dc=example,dc=com", "manager")
    let actions = EntryActions(connection: manager)
    let dept = "ou=Dept00,ou=Departments,dc=example,dc=com"
    t0 = clock.now
    let n = try! await actions.branchDNs(dept).count
    check(n == 1011, "count Dept00 branch = \(n) (\(ms(clock.now - t0)))")
    t0 = clock.now
    let copied = try! await actions.copy(dept, to: "ou=Empty,dc=example,dc=com")
    let nCopied = try! await actions.branchDNs(copied).count
    check(nCopied == 1011, "copy Dept00 → Empty: \(nCopied) entries (\(ms(clock.now - t0)))")
    t0 = clock.now
    let moved = try! await actions.move(copied, to: "ou=Deep,dc=example,dc=com")
    check(try! await actions.branchDNs(moved).count == 1011, "move copied branch keeps all 1011 (\(ms(clock.now - t0)))")
    // export LDIF parent-first
    var ldif = ""
    try! await actions.writeLDIF([moved], subtree: true) { ldif += $0 }
    let dns = ldif.split(separator: "\n").filter { $0.hasPrefix("dn: ") }.map { String($0.dropFirst(4)) }
    var seen = Set<String>(); var ordered = true
    for dn in dns { if dn != moved, !seen.contains(DN.normalize(DN.parent(of: dn)!)) { ordered = false }; seen.insert(DN.normalize(dn)) }
    check(dns.count == 1011 && ordered, "LDIF export: 1011 records, parent-first")
    t0 = clock.now
    let branch = try! await actions.branchDNs(moved)
    var lastProgress = 0
    try! await actions.deleteBranch(branch) { lastProgress = $0 }
    try! await actions.deleteBranch([branch.last!])   // already deleted: tolerated
    let gone = try! await fetchEntry(tree.target, dn: moved)
    check(gone == nil && lastProgress == 1011, "delete branch of 1011 (\(ms(clock.now - t0)))")
    // tree in-place updates
    let deepNode = tree.node("ou=Deep,dc=example,dc=com")!
    try! await actions.createEntry(dn: "ou=NewOU,ou=Deep,dc=example,dc=com", attributes: [("objectClass", "organizationalUnit")])
    await tree.entryAdded("ou=NewOU,ou=Deep,dc=example,dc=com")
    check(deepNode.children.contains { $0.name == "ou=NewOU" }, "create: node added in place")
    let renamed = try! await actions.rename("ou=NewOU,ou=Deep,dc=example,dc=com", toRDN: "ou=Renamed")
    await tree.entryMoved(from: "ou=NewOU,ou=Deep,dc=example,dc=com", to: renamed)
    check(deepNode.children.contains { $0.name == "ou=Renamed" } && !deepNode.children.contains { $0.name == "ou=NewOU" }, "rename: node replaced in place")
    try! await deleteEntry(manager.ldapTarget, readOnly: false, dn: renamed)
    tree.entryRemoved(renamed)
    check(!deepNode.children.contains { $0.name == "ou=Renamed" }, "delete: node removed in place")

    // read-only
    let ro = connection("cn=manager,ou=Service,dc=example,dc=com", "manager", readOnly: true)
    do { try await EntryActions(connection: ro).deleteBranch(["ou=Empty,dc=example,dc=com"]); check(false, "ro") }
    catch { check("\(error)".contains("read-only"), "read-only blocks branch delete") }
    do { _ = try await EntryActions(connection: ro).copy(dept, to: "ou=Empty,dc=example,dc=com"); check(false, "ro") }
    catch { check("\(error)".contains("read-only"), "read-only blocks copy") }

    // reveal finds an entry added since its parent was loaded
    let stale = "ou=AddedLater,ou=Deep,dc=example,dc=com"
    try! await actions.createEntry(dn: stale, attributes: [("objectClass", "organizationalUnit")])
    let revealed = try? await tree.reveal(stale)
    check(revealed == stale, "reveal finds an entry added after its parent was loaded")
    try! await deleteEntry(manager.ldapTarget, readOnly: false, dn: stale)

    // a server that ignores paging: results flagged, branch actions refuse
    let unpaged = LdapSearchRequest(baseDn: "ou=People,dc=example,dc=com", scope: .oneLevel,
                                    attributes: ["1.1"], pageSize: 0)
    let cut = try! await searchAll(tree.target, unpaged)
    check(cut.wasTruncated && cut.entries.count == 500, "truncated results are flagged (\(cut.entries.count))")
    do {
        try await pagedSearch(tree.target, unpaged) { _, _ in true }.requireComplete()
        check(false, "requireComplete should throw")
    } catch { check(true, "branch actions refuse truncated results: \(error)") }

    // a network that stops answering: a cancelled request retires its
    // connection, so the next one fails in time instead of hanging
    if let proxyPort = ProcessInfo.processInfo.environment["PROXY_PORT"].flatMap(Int.init),
       let proxyPID = ProcessInfo.processInfo.environment["PROXY_PID"].flatMap(Int32.init) {
        var proxied = connection("cn=reader,ou=Service,dc=example,dc=com", "reader")
        proxied.port = proxyPort
        proxied.timeoutSeconds = 3
        KeychainService.passwords[proxied.id] = "reader"
        _ = try? await fetchEntry(proxied.ldapTarget, dn: "dc=example,dc=com")
        kill(proxyPID, SIGSTOP)
        let stuck = Task { try await fetchEntry(proxied.ldapTarget, dn: "dc=example,dc=com") }
        try? await Task.sleep(for: .seconds(2))
        stuck.cancel()
        _ = try? await stuck.value
        t0 = clock.now
        let next = try? await fetchEntry(proxied.ldapTarget, dn: "dc=example,dc=com")
        let waited = clock.now - t0
        check(next == nil && waited < .seconds(10), "frozen network: next request gives up in \(ms(waited)) instead of hanging")
        kill(proxyPID, SIGCONT)
        let recovered = try? await fetchEntry(proxied.ldapTarget, dn: "dc=example,dc=com")
        check(recovered != nil, "network back: requests work again")
    } else {
        print("SKIP frozen-network check (no PROXY_PORT)")
    }

    // the server restarts under idle pooled connections: a read retries,
    // a write first checks the connection and replaces it
    if let runScript = ProcessInfo.processInfo.environment["RUN_SCRIPT"] {
        _ = try? await fetchEntry(manager.ldapTarget, dn: "dc=example,dc=com")
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: runScript)
        restart.arguments = ["start"]
        restart.standardOutput = FileHandle.nullDevice
        try! restart.run()
        restart.waitUntilExit()
        do {
            let afterRestart = try await fetchEntry(tree.target, dn: "dc=example,dc=com")
            check(afterRestart != nil, "server restarted: a read reconnects and retries")
        } catch { check(false, "server restarted: a read reconnects and retries — \(error)") }
        try? await Task.sleep(for: .seconds(6))
        let probe = "ou=AfterRestart,ou=Empty,dc=example,dc=com"
        do {
            try await actions.createEntry(dn: probe, attributes: [("objectClass", "organizationalUnit")])
            try await deleteEntry(manager.ldapTarget, readOnly: false, dn: probe)
            check(true, "server restarted: a write on an idle connection checks it first and succeeds")
        } catch { check(false, "write after restart: \(error)") }
    } else {
        print("SKIP server-restart check (no RUN_SCRIPT)")
    }

    // empty base DN: the tree starts at the naming contexts
    let rootDSE = DirectoryTree(connection: connection("cn=reader,ou=Service,dc=example,dc=com", "reader", base: ""))
    await rootDSE.loadRoot()
    if let r = rootDSE.root { await rootDSE.retryWait(r) }
    let contexts = rootDSE.root?.children.map(\.dn) ?? []
    check(contexts.contains("dc=example,dc=com"), "empty base DN lists naming contexts: \(contexts)")
    let fromRoot = try? await rootDSE.reveal("uid=deep02x1,ou=Level01,ou=Deep,dc=example,dc=com")
    check(fromRoot == "uid=deep02x1,ou=Level01,ou=Deep,dc=example,dc=com", "empty base DN: reveal walks down from the naming context")

    // small directory
    let small = DirectoryTree(connection: connection("cn=manager,dc=small,dc=test", "manager", base: "dc=small,dc=test"))
    t0 = clock.now
    await small.loadRoot()
    if let r = small.root { await small.retryWait(r) }
    check(small.root?.children.count == 4, "small directory opens (\(ms(clock.now - t0))): \(small.root?.children.map(\.name) ?? [])")
    print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
}

extension DirectoryTree {
    func retryWait(_ node: TreeNode) async {
        while node.childrenState == .loading || node.childrenState == .notLoaded { try? await Task.sleep(for: .milliseconds(5)) }
    }
    func allExpanded() -> [String] {
        var out: [String] = []
        func walk(_ n: TreeNode) { if n.isExpanded { out.append(n.dn) }; n.children.forEach(walk) }
        if let root { walk(root) }
        return out
    }
}

await run()
exit(failures == 0 ? 0 : 1)
