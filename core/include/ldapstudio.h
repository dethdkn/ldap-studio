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
  LS_TLS_UNTRUSTED
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

typedef struct LSEntry {
  char *dn;
  char *name; /* the RDN, for display */
  bool has_children;
  LSAttribute *attributes;
  size_t attribute_count;
  struct LSEntry *children;
  size_t child_count;
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

/* ── Connection-based operations ───────────────────────────────────────
 *
 * Every one of these takes the same five connection parameters up front:
 *   host, port, use_ssl, bind_dn, password
 * An empty bind_dn means an anonymous bind. The whole connect+bind is
 * capped at 15 seconds.
 */

/* Point the LDAPS/TLS layer at a PEM CA-bundle file. The bundled OpenSSL
 * can't read Homebrew's default cert store from inside the App Sandbox,
 * so the app calls this once at startup with a path to a bundle shipped
 * in its own Resources. Pass NULL to fall back to OpenSSL's default. The
 * path is copied. Call before opening any ldaps:// connection. */
void ls_set_tls_cacert(const char *path);

/* Per-connection TLS policy, applied by the next connect the same sticky
 * way ls_set_tls_cacert is (the Swift layer sets it immediately before
 * every operation). `start_tls` upgrades a plain ldap:// connection with
 * StartTLS after connecting (ignored for ldaps://). When `pinned_sha256`
 * is non-NULL (lowercase hex SHA-256 of the server's leaf certificate,
 * DER), library chain verification is turned off and the connection is
 * accepted only if the presented leaf matches — trust-on-first-use for
 * self-signed / private-CA servers. `allow_untrusted` turns verification
 * off without pinning; the app only uses it transiently. Pass
 * start_tls=false, allow_untrusted=false, pinned_sha256=NULL to reset. */
void ls_set_tls_policy(bool start_tls, bool allow_untrusted,
                       const char *pinned_sha256);

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

int ls_test_connection(const char *host, uint16_t port, bool use_ssl,
                       const char *bind_dn, const char *password, LSError *err);

int ls_fetch_root_entry(const char *host, uint16_t port, bool use_ssl,
                        const char *bind_dn, const char *password,
                        const char *base_dn, LSEntry **out, LSError *err);

int ls_search_directory(const char *host, uint16_t port, bool use_ssl,
                        const char *bind_dn, const char *password,
                        const char *base_dn, LSScope scope, const char *filter,
                        LSEntry **out, size_t *out_count, LSError *err);

int ls_fetch_schema(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, LSSchema **out,
                    LSError *err);

int ls_delete_entry(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, const char *dn,
                    LSError *err);

int ls_add_attribute_value(const char *host, uint16_t port, bool use_ssl,
                           const char *bind_dn, const char *password,
                           const char *dn, const char *attribute,
                           const char *value, LSError *err);

/* Replace every value of `attribute` with the single `value` (LDAP
 * Replace). Unlike modify_attribute_value this doesn't need to match an
 * existing value — use it for effectively single-valued attributes like
 * jpegPhoto, where "set" means "this is the value now". */
int ls_set_attribute_value(const char *host, uint16_t port, bool use_ssl,
                           const char *bind_dn, const char *password,
                           const char *dn, const char *attribute,
                           const char *value, bool is_binary, LSError *err);

int ls_modify_attribute_value(const char *host, uint16_t port, bool use_ssl,
                              const char *bind_dn, const char *password,
                              const char *dn, const char *attribute,
                              const char *old_value, const char *new_value,
                              bool is_binary, LSError *err);

int ls_delete_attribute_value(const char *host, uint16_t port, bool use_ssl,
                              const char *bind_dn, const char *password,
                              const char *dn, const char *attribute,
                              const char *value, bool is_binary, LSError *err);

int ls_move_entry(const char *host, uint16_t port, bool use_ssl,
                  const char *bind_dn, const char *password, const char *dn,
                  const char *new_superior, LSError *err);

/* Rename / relocate an entry (LDAP ModifyDN). `new_rdn` is the entry's new
 * RDN (e.g. "cn=Bob"); `new_superior` NULL or empty keeps the current
 * parent. Used by the LDIF editor's `changetype: modrdn`. */
int ls_rename_entry(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, const char *dn,
                    const char *new_rdn, bool delete_old_rdn,
                    const char *new_superior, LSError *err);

int ls_add_entry(const char *host, uint16_t port, bool use_ssl,
                 const char *bind_dn, const char *password, const char *dn,
                 const LSAttribute *attributes, size_t attribute_count,
                 LSError *err);

/* ── Batched modify (LDIF `changetype: modify`) ────────────────────── */

typedef enum { LS_MOD_ADD = 0, LS_MOD_DELETE, LS_MOD_REPLACE } LSModKind;

typedef struct {
  LSModKind kind;
  const char *attribute;
  /* `values[i].value` (+ is_binary); `name` is ignored. `value_count` may
   * be 0 — a whole-attribute delete, or replace-with-nothing. */
  const LSAttribute *values;
  size_t value_count;
} LSModOp;

/* Applies every op in one LDAP Modify operation against `dn`. */
int ls_modify_entry(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, const char *dn,
                    const LSModOp *ops, size_t op_count, LSError *err);

/* ── Standalone helpers ────────────────────────────────────────────── */

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
} LSDependencyVersions;

LSDependencyVersions ls_dependency_versions(void);

/* ── Freeing results ───────────────────────────────────────────────── */

void ls_string_free(char *s);
void ls_entry_free(LSEntry *entry); /* recursive; also frees `entry` */
void ls_entries_free(LSEntry *entries,
                     size_t n); /* frees an array from ls_search_directory */
void ls_schema_free(LSSchema *schema); /* recursive; also frees `schema` */

#ifdef __cplusplus
}
#endif

#endif /* LDAPSTUDIO_H */
