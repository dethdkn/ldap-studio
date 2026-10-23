# Contributing to LDAP Studio

Thanks for your interest in LDAP Studio! Bug reports, ideas, and pull requests are all welcome.

By taking part, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting Bugs and Requesting Features

[Open an issue](https://github.com/dethdkn/ldap-studio/issues) and, for bugs, include:

- Your LDAP Studio and macOS versions
- The LDAP server you're connecting to (OpenLDAP, Active Directory, 389 DS, …), if it matters
- Steps to reproduce, what you expected, and what happened instead

Please leave out passwords, hostnames, and any real directory data you don't want to make public.

Security issues should **not** go in a public issue. See [SECURITY.md](SECURITY.md).

## Project Layout

- `ldap-studio/`: the SwiftUI macOS app
- `core/`: the LDAP core, written in C, on top of OpenLDAP, OpenSSL, libxcrypt, and libssh2
- `docs/`: the website at [ldap-studio.app](https://ldap-studio.app) (Nuxt)
- `scripts/`: build and release scripts

## Development Setup

You'll need Xcode and [Homebrew](https://brew.sh).

```bash
git clone https://github.com/dethdkn/ldap-studio.git
cd ldap-studio
brew bundle
```

Open `ldap-studio.xcodeproj` in Xcode and run the `ldap-studio` scheme. The C core is compiled automatically as part of the build. To build a Release `.app` from the command line, run `scripts/build.sh`.

### C Core

From `core/`:

```bash
make test          # assert-based self-checks (tests/selftest.c)
make format        # format with clang-format
make format-check  # check formatting without changing files
make compdb        # regenerate compile_commands.json (for clangd and tidy)
make tidy          # static analysis with clang-tidy
```

### Website

From `docs/`, using [Bun](https://bun.sh):

```bash
bun install
bun run dev        # local dev server
bun run lint       # oxlint
bun run fmt        # oxfmt check
bun run typecheck
```

## Pull Requests

1. Fork the repo and create a branch from `main`.
2. Keep each pull request focused on one change.
3. Make sure the app builds, and run `make test` and `make format-check` in `core/` if you touched the C core, or the lint, format, and typecheck scripts in `docs/` if you touched the website.
4. Test your change against a real LDAP server when possible.
5. Describe what changed and why, and add screenshots for UI changes.

### Commit Messages

Commits use [gitmoji](https://gitmoji.dev): one line, starting with the emoji, in the imperative mood. For example:

```
✨ Reveal quick search results in the directory tree on click
🐛 Fix crash when a search returns no entries
```

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
