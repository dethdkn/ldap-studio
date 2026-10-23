# Security Policy

## Supported Versions

Only the [latest release](https://github.com/dethdkn/ldap-studio/releases/latest) of LDAP Studio receives security fixes. Please update before reporting an issue.

## Reporting a Vulnerability

Please **do not** open a public issue for security problems.

Instead, report them privately by email to **ldap-studio@rosa.sh**, or through [GitHub's private vulnerability reporting](https://github.com/dethdkn/ldap-studio/security/advisories/new).

Include as much of the following as you can:

- The LDAP Studio version and macOS version
- A description of the issue and its impact
- Steps to reproduce, or a proof of concept
- Any suggested fix

You'll get an acknowledgement within a few days. Once the issue is confirmed, a fix will be released as soon as possible, and you'll be credited in the changelog unless you'd rather stay anonymous.

## Scope

In scope:

- The LDAP Studio macOS app, including its handling of credentials (Keychain), LDAP/LDAPS/StartTLS connections, SSH tunnels, password hashing, and imported files (JSON, `.lcf`, LDIF)
- The website at [ldap-studio.app](https://ldap-studio.app)

Out of scope:

- Vulnerabilities in the LDAP servers you connect to
- Issues in bundled third-party libraries (OpenLDAP, OpenSSL, etc.) that are already fixed upstream; just let me know so I can update them
- The macOS Gatekeeper warning caused by the app not being notarized
