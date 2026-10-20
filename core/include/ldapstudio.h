/*
 * ldapstudio.h — the entire C ABI the SwiftUI app links against.
 *
 * This replaces what the old Rust crate exposed through UniFFI. Every
 * function returns 0 on success and a non-zero LSErrorKind on failure,
 * filling the caller-provided `err` out-param. Any `**out` result is
 * heap-allocated by the library and must be released with the matching
 * `ls_*_free` function; `ls_error_dispose` frees the strings inside an
 * LSError (not the LSError itself, which the caller owns).
 *
 * All strings crossing this boundary are NUL-terminated UTF-8. Binary
 * attribute values (jpegPhoto, certificates, …) are base64-encoded text
 * with `is_binary` set, exactly as the old Rust layer did — that's how
 * they survive the trip as a plain string.
 */
#ifndef LDAPSTUDIO_H
#define LDAPSTUDIO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Errors ─────────────────────────────────────────────────────────── */

typedef enum {
  LS_OK = 0,
  LS_CONNECT_FAILED,
  LS_CONNECT_TIMED_OUT,
  LS_BIND_FAILED,
  LS_SEARCH_FAILED,
  LS_MODIFY_FAILED,
  LS_HASH_FAILED,
  LS_DECODE_FAILED,
  LS_ENCODE_FAILED,
  /* TLS/StartTLS handshake rejected the server's certificate (untrusted
   * issuer, self-signed, expired, name mismatch) or it didn't match the
   * per-connection pinned fingerprint. The app answers this by probing the
   * certificate and offering to trust it. */
  LS_TLS_UNTRUSTED,
  LS_SSH_HOST_KEY_UNTRUSTED,
  /* An already-open LSConnection found its server gone (closed after
   * sitting idle, network dropped). Nothing reached the server, so the
   * app reconnects and retries. */
  LS_CONNECTION_LOST,
  /* The LSCancel passed to the call was triggered; the request was
   * abandoned on the server. */
  LS_CANCELLED
} LSErrorKind;

/*
 * `host`/`port` are only populated for the connect-stage errors (they
 * map to the Rust ConnectFailed/ConnectTimedOut variants that carried
 * them); everything else just carries `reason`. `host` and `reason` are
 * owned by the struct — call ls_error_dispose to free them.
 */
typedef struct {
  LSErrorKind kind;
  char *host;
  uint16_t port;
  char *reason;
} LSError;

void ls_error_dispose(LSError *err);

/* ── Directory data ─────────────────────────────────────────────────── */

typedef struct {
  char *name;
  char *value; /* base64 text when is_binary */
  bool is_binary;
} LSAttribute;

typedef struct {
  char *dn;
  char *name; /* the RDN, for display */
  LSAttribute *attributes;
  size_t attribute_count;
} LSEntry;

typedef enum { LS_SCOPE_BASE = 0, LS_SCOPE_ONELEVEL, LS_SCOPE_SUBTREE } LSScope;

/* ── Schema data (mirrors SchemaObjectClass / SchemaAttributeType) ──── */

typedef struct {
  char *oid;
  char **names;
  size_t name_count;
  char *description; /* nullable */
  bool obsolete;
  char **superior_classes;
  size_t superior_class_count;
  char *kind; /* STRUCTURAL / ABSTRACT / AUXILIARY */
  char **must;
  size_t must_count;
  char **may;
  size_t may_count;
  char *x_origin; /* nullable */
  char *raw;
} LSObjectClass;

typedef struct {
  char *oid;
  char **names;
  size_t name_count;
  char *description; /* nullable */
  bool obsolete;
  char *superior_type;           /* nullable */
  char *equality_matching_rule;  /* nullable */
  char *ordering_matching_rule;  /* nullable */
  char *substring_matching_rule; /* nullable */
  char *syntax_oid;              /* nullable */
  bool single_valued;
  bool collective;
  bool no_user_modification;
  char *usage;    /* nullable */
  char *x_origin; /* nullable */
  char *raw;
} LSAttributeType;

typedef struct {
  LSObjectClass *object_classes;
  size_t object_class_count;
  LSAttributeType *attribute_types;
  size_t attribute_type_count;
} LSSchema;

/* ── Password hashing ──────────────────────────────────────────────── */

typedef enum {
  LS_PBKDF2_SHA512 = 0,
  LS_UNIX_CRYPT,
  LS_MD5_CRYPT,
  LS_MD5,
  LS_SHA1,
  LS_SMD5,
  LS_SSHA,
  LS_SHA256_CRYPT,
  LS_SHA512_CRYPT
} LSPasswordScheme;

/* ── Connection policy ─────────────────────────────────────────────────
 *
 * Opening a connection (ls_connection_open, ls_test_connection,
 * ls_probe_certificate) takes the same five parameters up front:
 *   host, port, use_ssl, bind_dn, password
 * An empty bind_dn means an anonymous bind. The whole connect+bind is
 * capped at the timeout set via ls_set_connection_policy (15 seconds by
 * default): if it hasn't finished by then the call returns
 * LS_CONNECT_TIMED_OUT, however far along — or stuck — it was.
 */

/* Point the LDAPS/TLS layer at a PEM CA-bundle file. The bundled OpenSSL
 * can't read Homebrew's default cert store from inside the App Sandbox,
 * so the app calls this once at startup with a path to a bundle shipped
 * in its own Resources. Pass NULL to fall back to OpenSSL's default. The
 * path is copied. Call before opening any ldaps:// connection. */
void ls_set_tls_cacert(const char *path);

/* Per-connection TLS policy, applied by the next connect the same sticky
 * way ls_set_tls_cacert is (the Swift layer sets it immediately before
 * every connect). `start_tls` upgrades a plain ldap:// connection with
 * StartTLS after connecting (ignored for ldaps://). When `pinned_sha256`
 * is non-NULL (lowercase hex SHA-256 of the server's leaf certificate,
 * DER), library chain verification is turned off and the connection is
 * accepted only if the presented leaf matches — trust-on-first-use for
 * self-signed / private-CA servers. `allow_untrusted` turns verification
 * off without pinning; the app only uses it transiently. Pass
 * start_tls=false, allow_untrusted=false, pinned_sha256=NULL to reset. */
void ls_set_tls_policy(bool start_tls, bool allow_untrusted,
                       const char *pinned_sha256);

typedef enum {
  LS_AUTH_SIMPLE = 0,
  LS_AUTH_EXTERNAL,
  LS_AUTH_GSSAPI,
  LS_AUTH_DIGEST_MD5
} LSAuthMethod;

/* Connection behavior and bind method for the next connect. Strings are
 * copied. A timeout below one second is clamped to one second. */
void ls_set_connection_policy(bool chase_referrals, unsigned timeout_seconds,
                              LSAuthMethod auth_method, const char *auth_id,
                              const char *realm, const char *client_cert_path,
                              const char *client_key_path);

typedef enum { LS_SSH_PASSWORD = 0, LS_SSH_PRIVATE_KEY } LSSSHAuthMethod;
void ls_set_ssh_policy(bool enabled, const char *host, uint16_t port,
                       const char *username, LSSSHAuthMethod auth_method,
                       const char *password, const char *private_key_path,
                       const char *pinned_host_key_sha256);

/* An SSH tunnel is expensive to open (handshake + auth), so once one is
 * opened for a given target it's kept warm and reused by later
 * connections to the same server instead of being torn down after each
 * one (see connect.c). Call this to close every cached tunnel right
 * away — e.g. when the app is quitting. Tunnels also self-expire after a
 * few minutes of disuse, so this is a courtesy, not a requirement. */
void ls_close_ssh_tunnels(void);

/* Call once before the process exits, after closing every LSConnection.
 * A connection attempt that hit its timeout is abandoned rather than
 * killed, and keeps unwinding on its own thread for a moment; exiting
 * underneath it can race OpenSSL's exit-time cleanup. This waits up to
 * `wait_ms` for any such attempts to finish, then closes every cached SSH
 * tunnel (ls_close_ssh_tunnels). */
void ls_shutdown(unsigned wait_ms);

/* Connects with certificate verification disabled purely to read back the
 * server's leaf certificate, so the app can show it and ask the user
 * whether to trust it. Returns LS_OK even when the cert wouldn't normally
 * validate; the booleans say why it wouldn't. All strings are owned by
 * the struct — release with ls_cert_info_dispose. */
typedef struct {
  char *subject;
  char *issuer;
  char *sha256; /* lowercase hex, no separators */
  char *not_before;
  char *not_after;
  bool self_signed;
  bool expired;
  bool host_mismatch;
} LSCertInfo;

int ls_probe_certificate(const char *host, uint16_t port, bool use_ssl,
                         bool start_tls, LSCertInfo *out, LSError *err);
void ls_cert_info_dispose(LSCertInfo *info);

/* Connects, binds, and disconnects again. */
int ls_test_connection(const char *host, uint16_t port, bool use_ssl,
                       const char *bind_dn, const char *password, LSError *err);

/* ── Connections ───────────────────────────────────────────────────────
 *
 * A bound connection that stays open across operations, so browsing a
 * large directory doesn't pay for a TCP + TLS handshake and a bind on
 * every click. Opened with whatever policy the ls_set_* calls last set.
 *
 * One connection serves one call at a time — the app keeps a small pool
 * and hands each caller its own — but different connections may be used
 * from different threads at once.
 *
 * Every call below that fails because the server went away marks the
 * connection broken (see ls_connection_is_broken); close it and open a
 * new one. A connection that sits idle long enough to be closed by the
 * server fails with LS_CONNECTION_LOST, which is safe to retry on a fresh
 * connection.
 */
typedef struct LSConnection LSConnection;

int ls_connection_open(const char *host, uint16_t port, bool use_ssl,
                       const char *bind_dn, const char *password,
                       LSConnection **out, LSError *err);
void ls_connection_close(LSConnection *conn); /* NULL is a no-op */
bool ls_connection_is_broken(const LSConnection *conn);

/* A thread-safe flag that stops a search in progress: trigger it from any
 * thread and the search abandons its request and returns LS_CANCELLED
 * within about 100ms. */
typedef struct LSCancel LSCancel;
LSCancel *ls_cancel_new(void);
void ls_cancel_trigger(LSCancel *cancel);
void ls_cancel_free(LSCancel *cancel);

/* ── Searching ─────────────────────────────────────────────────────────
 *
 * A search is read one page at a time, so callers can show the first
 * results while the rest arrive and stop whenever they like. With
 * `page_size` > 0 the search sends the paged results control (RFC 2696,
 * non-critical), which is what lets it read past a server's size limit
 * (Active Directory's MaxPageSize, OpenLDAP's sizelimit). A server that
 * rejects the page size as too large is retried with smaller pages.
 *
 * `attributes` lists the attributes to return; NULL / 0 means every user
 * attribute ("*"). Pass {"1.1"} for no attributes at all (just DNs).
 * `include_operational` adds "+" (createTimestamp, entryUUID, …).
 *
 * `idle_timeout_seconds` > 0 fails a page that receives nothing from the
 * server for that long; 0 waits as long as it takes (callers cancel).
 */
typedef struct LSSearch LSSearch;

int ls_search_begin(LSConnection *conn, const char *base_dn, LSScope scope,
                    const char *filter, const char *const *attributes,
                    size_t attribute_count, bool include_operational,
                    unsigned page_size, unsigned idle_timeout_seconds,
                    LSSearch **out, LSError *err);

/* Fetches the next page into *out (release with ls_entries_free; may be
 * empty). Sets *done once there are no more pages. Sets *truncated when
 * the server stopped early with "size limit exceeded" anyway — it
 * ignored the paging control — so the results are incomplete. `cancel`
 * may be NULL. On failure the search is finished; don't call it again. */
int ls_search_next_page(LSSearch *search, LSCancel *cancel, LSEntry **out,
                        size_t *out_count, bool *done, bool *truncated,
                        LSError *err);

/* Ends a search, telling the server to drop an unfinished paged search's
 * state. NULL is a no-op. Doesn't close the connection. */
void ls_search_free(LSSearch *search);

int ls_fetch_schema(LSConnection *conn, LSSchema **out, LSError *err);

/* ── Writes ────────────────────────────────────────────────────────── */

int ls_delete_entry(LSConnection *conn, const char *dn, LSError *err);

/* Rename / relocate an entry (LDAP ModifyDN). `new_rdn` is the entry's new
 * RDN (e.g. "cn=Bob"); `new_superior` NULL or empty keeps the current
 * parent. A move keeps the RDN and passes a new superior. */
int ls_rename_entry(LSConnection *conn, const char *dn, const char *new_rdn,
                    bool delete_old_rdn, const char *new_superior,
                    LSError *err);

int ls_add_entry(LSConnection *conn, const char *dn,
                 const LSAttribute *attributes, size_t attribute_count,
                 LSError *err);

typedef enum { LS_MOD_ADD = 0, LS_MOD_DELETE, LS_MOD_REPLACE } LSModKind;

typedef struct {
  LSModKind kind;
  const char *attribute;
  /* `values[i].value` (+ is_binary); `name` is ignored. `value_count` may
   * be 0 — a whole-attribute delete, or replace-with-nothing. */
  const LSAttribute *values;
  size_t value_count;
} LSModOp;

/* Applies every op in one LDAP Modify operation against `dn`. Adding,
 * replacing or deleting a single attribute value are all one-op calls. */
int ls_modify_entry(LSConnection *conn, const char *dn, const LSModOp *ops,
                    size_t op_count, LSError *err);

/* ── Standalone helpers ────────────────────────────────────────────── */

/* libldap's text for an LDAP result code (e.g. 32 → "No such object") —
 * the `reason` a failed operation reports for it. Static; don't free. */
const char *ls_ldap_error_text(int result_code);

int ls_hash_password(const char *plaintext, LSPasswordScheme scheme, char **out,
                     LSError *err);

int ls_resize_photo_to_base64(const char *path, char **out, LSError *err);

/* ── Build info ────────────────────────────────────────────────────── */

/* Versions of the bundled native libraries this build was compiled
 * against (e.g. "2.7.1"). All members are static string literals — do
 * not free. */
typedef struct {
  const char *openldap;
  const char *openssl;
  const char *libxcrypt;
  const char *libssh2;
} LSDependencyVersions;

LSDependencyVersions ls_dependency_versions(void);

/* ── Freeing results ───────────────────────────────────────────────── */

void ls_string_free(char *s);
void ls_entries_free(LSEntry *entries,
                     size_t n); /* frees a page from ls_search_next_page */
void ls_schema_free(LSSchema *schema); /* recursive; also frees `schema` */

#ifdef __cplusplus
}
#endif

#endif /* LDAPSTUDIO_H */
