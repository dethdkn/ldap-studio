/*
 * ldap.c — connection, directory browsing/search, and modify operations.
 * A direct port of the old Rust connection.rs / directory.rs / modify.rs,
 * built on the system's OpenLDAP client (LDAP.framework).
 *
 * Every exported call opens a fresh connection, does its work, and
 * unbinds — exactly as the async Rust functions did.
 */
#include <ctype.h>
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <stdlib.h>
#include <string.h>

#include "internal_ldap.h"

/* ── connection ───────────────────────────────────────────────────── */

int ls_ldap_fail(LSError *err, LSErrorKind kind, int rc) {
  return ls_fail(err, kind, NULL, 0, ldap_err2string(rc));
}

/* Optional PEM CA bundle for LDAPS, set once at startup (see the header).
 * Written before any connection is opened, read-only thereafter. */
static char *g_tls_cacert;

/* Per-connection TLS policy — see ls_set_tls_policy in the header. Plain
 * globals, matching g_tls_cacert; the Swift layer rewrites them before
 * every operation. */
static bool g_tls_start_tls;
static bool g_tls_allow_untrusted;
static char
    *g_tls_pinned_sha256; /* lowercase hex, no separators; NULL = none */

void ls_set_tls_cacert(const char *path) {
  free(g_tls_cacert);
  g_tls_cacert = path ? ls_xstrdup(path) : NULL;
}

/* Lowercase a hex string in place and strip ':' separators. */
static char *normalize_hex(const char *s) {
  char *out = ls_xmalloc(strlen(s) + 1);
  size_t n = 0;
  for (const char *p = s; *p; p++) {
    if (*p == ':' || *p == ' ') continue;
    out[n++] = (char)tolower((unsigned char)*p);
  }
  out[n] = '\0';
  return out;
}

void ls_set_tls_policy(bool start_tls, bool allow_untrusted,
                       const char *pinned_sha256) {
  g_tls_start_tls = start_tls;
  g_tls_allow_untrusted = allow_untrusted;
  free(g_tls_pinned_sha256);
  g_tls_pinned_sha256 = pinned_sha256 ? normalize_hex(pinned_sha256) : NULL;
}

/* Lowercase-hex encode `len` bytes into `out` (needs len*2 + 1 bytes). */
static void hex_encode(const unsigned char *bytes, size_t len, char *out) {
  static const char digits[] = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) {
    out[i * 2] = digits[bytes[i] >> 4];
    out[(i * 2) + 1] = digits[bytes[i] & 0x0F];
  }
  out[len * 2] = '\0';
}

/* SHA-256 of the connection's peer leaf cert (DER), as lowercase hex into
 * `out` (needs >= 65 bytes). False if there's no peer cert yet. */
static bool peer_cert_sha256(LDAP *ld, char *out) {
  struct berval der = {0, NULL};
  if (ldap_get_option(ld, LDAP_OPT_X_TLS_PEERCERT, &der) != LDAP_OPT_SUCCESS ||
      !der.bv_val) {
    return false;
  }
  const unsigned char *p = (const unsigned char *)der.bv_val;
  X509 *cert = d2i_X509(NULL, &p, (long)der.bv_len);
  ldap_memfree(der.bv_val);
  if (!cert) return false;

  unsigned char md[EVP_MAX_MD_SIZE];
  unsigned int md_len = 0;
  int ok = X509_digest(cert, EVP_sha256(), md, &md_len);
  X509_free(cert);
  if (!ok || md_len == 0) return false;

  hex_encode(md, md_len, out);
  return true;
}

/* A failed TLS/StartTLS step is either the socket (real connect failure)
 * or the certificate being rejected. libldap blurs the two — StartTLS
 * verification failure comes back as LDAP_CONNECT_ERROR, ldaps:// as
 * LDAP_SERVER_DOWN, same as a dead host, and by then it has dropped the
 * TLS context so the peer cert is gone. So re-probe with verification
 * off: if the server still completes a handshake and presents a
 * certificate, the original failure was that cert being rejected — tell
 * the app so it can offer to trust it. Only when we were verifying; a
 * pinned or allow-untrusted connection that still failed is a real
 * fault. */
static LSErrorKind classify_tls_failure(const char *host, uint16_t port,
                                        bool use_ssl, int rc) {
  if (rc == LDAP_TIMEOUT) return LS_CONNECT_TIMED_OUT;
  if (g_tls_allow_untrusted || g_tls_pinned_sha256 != NULL) {
    return LS_CONNECT_FAILED;
  }
  LSCertInfo probe = {0};
  LSError probe_err = {0};
  int prc = ls_probe_certificate(host, port, use_ssl, g_tls_start_tls, &probe,
                                 &probe_err);
  ls_cert_info_dispose(&probe);
  ls_error_dispose(&probe_err);
  return prc == LS_OK ? LS_TLS_UNTRUSTED : LS_CONNECT_FAILED;
}

int ls_connect_and_bind(const char *host, uint16_t port, bool use_ssl,
                        const char *bind_dn, const char *password, LDAP **out,
                        LSError *err) {
  *out = NULL;

  const char *scheme = "ldap";
  if (use_ssl) scheme = "ldaps";
  char *uri =
      ls_aprintf("%s://%s:%u", scheme, host ? host : "", (unsigned)port);
  LDAP *ld = NULL;
  int rc = ldap_initialize(&ld, uri);
  free(uri);
  if (rc != LDAP_SUCCESS || !ld)
    return ls_fail(err, LS_CONNECT_FAILED, host, port, ldap_err2string(rc));

  int version = LDAP_VERSION3;
  ldap_set_option(ld, LDAP_OPT_PROTOCOL_VERSION, &version);
  ldap_set_option(ld, LDAP_OPT_REFERRALS, LDAP_OPT_OFF);

  struct timeval tv = {LS_CONNECT_TIMEOUT_SECS, 0};
  ldap_set_option(ld, LDAP_OPT_NETWORK_TIMEOUT, &tv);
  ldap_set_option(ld, LDAP_OPT_TIMEOUT, &tv);

  bool tls = use_ssl;
  if (g_tls_start_tls) tls = true;
  if (tls) {
    /* Verification stays at the library default (demand a valid chain)
     * unless the connection is pinned or the user chose "allow untrusted"
     * — then it's the pin (or nothing) that gates acceptance. */
    int require = (g_tls_allow_untrusted || g_tls_pinned_sha256)
                      ? LDAP_OPT_X_TLS_NEVER
                      : LDAP_OPT_X_TLS_DEMAND;
    ldap_set_option(ld, LDAP_OPT_X_TLS_REQUIRE_CERT, &require);
    /* The bundled OpenSSL can't reach its own default store under the
     * sandbox, so point it at the app's CA bundle when we're verifying. */
    if (g_tls_cacert && require == LDAP_OPT_X_TLS_DEMAND) {
      ldap_set_option(ld, LDAP_OPT_X_TLS_CACERTFILE, g_tls_cacert);
    }
    int newctx = 0; /* 0 = build a new client context now */
    ldap_set_option(ld, LDAP_OPT_X_TLS_NEWCTX, &newctx);
  }

  if (g_tls_start_tls && !use_ssl) {
    rc = ldap_start_tls_s(ld, NULL, NULL);
    if (rc != LDAP_SUCCESS) {
      int out_rc = ls_fail(err, classify_tls_failure(host, port, use_ssl, rc),
                           host, port, ldap_err2string(rc));
      ldap_unbind_ext_s(ld, NULL, NULL);
      return out_rc;
    }
  }

  if (tls) {
    /* Force the handshake now (ldaps:// otherwise defers it to the bind)
     * so a cert rejection is classified here and the peer cert is
     * available for pinning. */
    rc = ldap_connect(ld);
    if (rc != LDAP_SUCCESS) {
      int out_rc = ls_fail(err, classify_tls_failure(host, port, use_ssl, rc),
                           host, port, ldap_err2string(rc));
      ldap_unbind_ext_s(ld, NULL, NULL);
      return out_rc;
    }
  }

  if (g_tls_pinned_sha256 && tls) {
    char got[(EVP_MAX_MD_SIZE * 2) + 1] = {0};
    if (!peer_cert_sha256(ld, got) || strcmp(got, g_tls_pinned_sha256) != 0) {
      int out_rc = ls_fail(err, LS_TLS_UNTRUSTED, host, port,
                           "server certificate does not match the "
                           "fingerprint trusted for this connection");
      ldap_unbind_ext_s(ld, NULL, NULL);
      return out_rc;
    }
  }

  struct berval cred;
  cred.bv_val = (char *)(password ? password : "");
  cred.bv_len = password ? strlen(password) : 0;
  const char *dn = (bind_dn && *bind_dn) ? bind_dn : NULL;

  struct berval *server_cred = NULL;
  rc = ldap_sasl_bind_s(ld, dn, LDAP_SASL_SIMPLE, &cred, NULL, NULL,
                        &server_cred);
  if (server_cred) ber_bvfree(server_cred);

  if (rc != LDAP_SUCCESS) {
    LSErrorKind kind;
    if (rc == LDAP_TIMEOUT)
      kind = LS_CONNECT_TIMED_OUT;
    else if (rc == LDAP_SERVER_DOWN || rc == LDAP_CONNECT_ERROR ||
             rc == LDAP_UNAVAILABLE || rc == LDAP_LOCAL_ERROR)
      kind = LS_CONNECT_FAILED;
    else
      kind = LS_BIND_FAILED;
    int out_rc = ls_fail(err, kind, host, port, ldap_err2string(rc));
    ldap_unbind_ext_s(ld, NULL, NULL);
    return out_rc;
  }

  *out = ld;
  return LS_OK;
}

int ls_test_connection(const char *host, uint16_t port, bool use_ssl,
                       const char *bind_dn, const char *password,
                       LSError *err) {
  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) return rc;
  ldap_unbind_ext_s(ld, NULL, NULL);
  return LS_OK;
}

/* ── certificate probe (for the trust dialog) ─────────────────────── */

/* An X509_NAME as a single RFC 2253-ish line. Caller frees. */
static char *x509_name_string(X509_NAME *name) {
  if (!name) return ls_xstrdup("");
  BIO *bio = BIO_new(BIO_s_mem());
  if (!bio) return ls_xstrdup("");
  X509_NAME_print_ex(bio, name, 0, XN_FLAG_RFC2253);
  char *data = NULL;
  long len = BIO_get_mem_data(bio, &data);
  char *out = ls_strdup_n(data, len > 0 ? (size_t)len : 0);
  BIO_free(bio);
  return out;
}

/* An ASN1_TIME rendered like "Sep 10 12:00:00 2026 GMT". Caller frees. */
static char *asn1_time_string(const ASN1_TIME *time) {
  if (!time) return ls_xstrdup("");
  BIO *bio = BIO_new(BIO_s_mem());
  if (!bio) return ls_xstrdup("");
  ASN1_TIME_print(bio, time);
  char *data = NULL;
  long len = BIO_get_mem_data(bio, &data);
  char *out = ls_strdup_n(data, len > 0 ? (size_t)len : 0);
  BIO_free(bio);
  return out;
}

static char *x509_sha256_hex(X509 *cert) {
  unsigned char md[EVP_MAX_MD_SIZE];
  unsigned int md_len = 0;
  if (!X509_digest(cert, EVP_sha256(), md, &md_len) || md_len == 0) {
    return ls_xstrdup("");
  }
  char *out = ls_xmalloc(((size_t)md_len * 2) + 1);
  hex_encode(md, md_len, out);
  return out;
}

int ls_probe_certificate(const char *host, uint16_t port, bool use_ssl,
                         bool start_tls, LSCertInfo *out, LSError *err) {
  memset(out, 0, sizeof *out);

  const char *scheme = "ldap";
  if (use_ssl) scheme = "ldaps";
  char *uri =
      ls_aprintf("%s://%s:%u", scheme, host ? host : "", (unsigned)port);
  LDAP *ld = NULL;
  int rc = ldap_initialize(&ld, uri);
  free(uri);
  if (rc != LDAP_SUCCESS || !ld) {
    return ls_fail(err, LS_CONNECT_FAILED, host, port, ldap_err2string(rc));
  }

  int version = LDAP_VERSION3;
  ldap_set_option(ld, LDAP_OPT_PROTOCOL_VERSION, &version);
  struct timeval tv = {LS_CONNECT_TIMEOUT_SECS, 0};
  ldap_set_option(ld, LDAP_OPT_NETWORK_TIMEOUT, &tv);
  ldap_set_option(ld, LDAP_OPT_TIMEOUT, &tv);

  int never = LDAP_OPT_X_TLS_NEVER;
  ldap_set_option(ld, LDAP_OPT_X_TLS_REQUIRE_CERT, &never);
  int newctx = 0;
  ldap_set_option(ld, LDAP_OPT_X_TLS_NEWCTX, &newctx);

  if (start_tls && !use_ssl) {
    rc = ldap_start_tls_s(ld, NULL, NULL);
  } else {
    rc = ldap_connect(ld);
  }
  if (rc != LDAP_SUCCESS) {
    int out_rc = ls_fail(
        err, rc == LDAP_TIMEOUT ? LS_CONNECT_TIMED_OUT : LS_CONNECT_FAILED,
        host, port, ldap_err2string(rc));
    ldap_unbind_ext_s(ld, NULL, NULL);
    return out_rc;
  }

  /* LDAP_OPT_X_TLS_PEERCERT fills a caller-provided struct berval (not a
   * pointer to one) with a malloc'd copy of the DER cert; free bv_val. */
  struct berval der = {0, NULL};
  if (ldap_get_option(ld, LDAP_OPT_X_TLS_PEERCERT, &der) != LDAP_OPT_SUCCESS ||
      !der.bv_val) {
    ldap_unbind_ext_s(ld, NULL, NULL);
    return ls_fail(err, LS_CONNECT_FAILED, host, port,
                   "the server did not present a certificate");
  }
  const unsigned char *p = (const unsigned char *)der.bv_val;
  X509 *cert = d2i_X509(NULL, &p, (long)der.bv_len);
  ldap_memfree(der.bv_val);
  ldap_unbind_ext_s(ld, NULL, NULL);
  if (!cert) {
    return ls_fail(err, LS_DECODE_FAILED, host, port,
                   "could not parse the server certificate");
  }

  X509_NAME *subject = X509_get_subject_name(cert);
  X509_NAME *issuer = X509_get_issuer_name(cert);
  out->subject = x509_name_string(subject);
  out->issuer = x509_name_string(issuer);
  out->sha256 = x509_sha256_hex(cert);
  out->not_before = asn1_time_string(X509_get0_notBefore(cert));
  out->not_after = asn1_time_string(X509_get0_notAfter(cert));
  out->self_signed = X509_NAME_cmp(subject, issuer) == 0;

  out->expired = false;
  if (X509_cmp_current_time(X509_get0_notAfter(cert)) < 0) out->expired = true;
  if (X509_cmp_current_time(X509_get0_notBefore(cert)) > 0) out->expired = true;

  out->host_mismatch = false;
  if (host && *host &&
      X509_check_host(cert, host, strlen(host), 0, NULL) != 1) {
    out->host_mismatch = true;
  }

  X509_free(cert);
  return LS_OK;
}

void ls_cert_info_dispose(LSCertInfo *info) {
  if (!info) return;
  free(info->subject);
  free(info->issuer);
  free(info->sha256);
  free(info->not_before);
  free(info->not_after);
  memset(info, 0, sizeof *info);
}

/* ── DN helpers (naive first-comma split, matching the old code) ───── */

/* Text before the first comma (or the whole DN). Caller frees. */
static char *display_name(const char *dn) {
  const char *comma = strchr(dn, ',');
  return comma ? ls_strdup_n(dn, (size_t)(comma - dn)) : ls_xstrdup(dn);
}

/* Text after the first comma, or NULL. Caller frees. */
static char *parent_dn(const char *dn) {
  const char *comma = strchr(dn, ',');
  return comma ? ls_xstrdup(comma + 1) : NULL;
}

/* ── flat entry + attribute extraction ───────────────────────────── */

typedef struct {
  char *dn;
  LSAttribute *attrs;
  size_t nattrs;
  bool taken; /* moved into the result tree already */
} FlatEntry;

static void push_attr(LSAttribute **arr, size_t *n, size_t *cap, char *name,
                      char *value, bool is_binary) {
  if (*n == *cap) {
    *cap = *cap ? *cap * 2 : 8;
    *arr = ls_xrealloc(*arr, *cap * sizeof(**arr));
  }
  (*arr)[*n].name = name;
  (*arr)[*n].value = value;
  (*arr)[(*n)++].is_binary = is_binary;
}

/* Pulls every attribute value out of one result message. Values that are
 * not valid UTF-8 (photos, certs, …) are base64-encoded with is_binary
 * set — the old code got this split for free from ldap3's bin_attrs. */
static LSAttribute *attributes_from(LDAP *ld, LDAPMessage *msg, size_t *out_n) {
  LSAttribute *arr = NULL;
  size_t n = 0;
  size_t cap = 0;

  BerElement *ber = NULL;
  for (char *name = ldap_first_attribute(ld, msg, &ber); name != NULL;
       name = ldap_next_attribute(ld, msg, ber)) {
    struct berval **vals = ldap_get_values_len(ld, msg, name);
    if (vals) {
      for (size_t i = 0; vals[i] != NULL; ++i) {
        const uint8_t *raw = (const uint8_t *)vals[i]->bv_val;
        size_t len = vals[i]->bv_len;
        if (ls_utf8_valid(raw, len))
          push_attr(&arr, &n, &cap, ls_xstrdup(name),
                    ls_strdup_n((const char *)raw, len), false);
        else
          push_attr(&arr, &n, &cap, ls_xstrdup(name), ls_b64_encode(raw, len),
                    true);
      }
      ldap_value_free_len(vals);
    }
    ldap_memfree(name);
  }
  if (ber) ber_free(ber, 0);

  *out_n = n;
  return arr;
}

static void free_attr_array(LSAttribute *arr, size_t n) {
  for (size_t i = 0; i < n; ++i) {
    free(arr[i].name);
    free(arr[i].value);
  }
  free(arr);
}

/* ── tiny string → index hash map (djb2, linear probing) ──────────── */

typedef struct {
  char *key;
  size_t val;
  bool used;
} MapSlot;
typedef struct {
  MapSlot *slots;
  size_t cap;
  size_t count;
} Map;

static void map_init(Map *m, size_t hint) {
  m->cap = 16;
  while (m->cap < hint * 2) m->cap *= 2;
  m->slots = ls_xcalloc(m->cap, sizeof(MapSlot));
  m->count = 0;
}
static void map_free(Map *m) {
  free(m->slots);
  m->slots = NULL;
  m->cap = m->count = 0;
}

static size_t djb2(const char *s) {
  size_t h = 5381;
  for (; *s; ++s) h = ((h << 5) + h) ^ (unsigned char)*s;
  return h;
}

static void map_put(Map *m, char *key, size_t val) {
  size_t i = djb2(key) & (m->cap - 1);
  while (m->slots[i].used) {
    if (strcmp(m->slots[i].key, key) == 0) {
      m->slots[i].val = val;
      return;
    }
    i = (i + 1) & (m->cap - 1);
  }
  m->slots[i].key = key;
  m->slots[i].val = val;
  m->slots[i].used = true;
  m->count++;
}

/* Returns index, or SIZE_MAX if absent. */
static size_t map_get(const Map *m, const char *key) {
  if (!key) return (size_t)-1;
  size_t i = djb2(key) & (m->cap - 1);
  while (m->slots[i].used) {
    if (strcmp(m->slots[i].key, key) == 0) return m->slots[i].val;
    i = (i + 1) & (m->cap - 1);
  }
  return (size_t)-1;
}

/* ── tree assembly for fetch_root_entry ──────────────────────────── */

typedef struct {
  size_t *items;
  size_t count;
  size_t cap;
} IdxList;

static void idx_push(IdxList *l, size_t v) {
  if (l->count == l->cap) {
    l->cap = l->cap ? l->cap * 2 : 4;
    l->items = ls_xrealloc(l->items, l->cap * sizeof(size_t));
  }
  l->items[l->count++] = v;
}

static FlatEntry *g_flat; /* for the sort comparator */

static int cmp_by_name_ci(const void *a, const void *b) {
  const char *na = g_flat[*(const size_t *)a].dn;
  const char *nb = g_flat[*(const size_t *)b].dn;
  /* compare on the display name (RDN), case-insensitively */
  char *da = display_name(na);
  char *db = display_name(nb);
  for (char *p = da; *p; ++p) *p = (char)tolower((unsigned char)*p);
  for (char *p = db; *p; ++p) *p = (char)tolower((unsigned char)*p);
  int r = strcmp(da, db);
  free(da);
  free(db);
  return r;
}

/* Recursively materializes the entry at flat index `i` and its subtree. */
static LSEntry build_entry(size_t i, FlatEntry *flat, IdxList *children_of) {
  FlatEntry *fe = &flat[i];
  fe->taken = true;

  IdxList *kids = &children_of[i];
  if (kids->count > 1) {
    g_flat = flat;
    qsort(kids->items, kids->count, sizeof(size_t), cmp_by_name_ci);
  }

  LSEntry e;
  e.dn = ls_xstrdup(fe->dn);
  e.name = display_name(fe->dn);
  e.attributes = fe->attrs;
  e.attribute_count = fe->nattrs;
  fe->attrs = NULL; /* ownership moved into the tree */
  fe->nattrs = 0;
  e.child_count = kids->count;
  e.has_children = kids->count > 0;
  e.children = kids->count ? ls_xmalloc(kids->count * sizeof(LSEntry)) : NULL;
  for (size_t k = 0; k < kids->count; ++k)
    e.children[k] = build_entry(kids->items[k], flat, children_of);
  return e;
}

/* ── searching ───────────────────────────────────────────────────── */

static int run_search(LDAP *ld, const char *base, int scope, const char *filter,
                      bool include_operational, LDAPMessage **res,
                      LSError *err) {
  char *user_only[] = {(char *)"*", NULL};
  char *with_operational[] = {(char *)"*", (char *)"+", NULL};
  char **attrs = user_only;
  if (include_operational) attrs = with_operational;
  int rc = ldap_search_ext_s(ld, base ? base : "", scope,
                             (filter && *filter) ? filter : "(objectClass=*)",
                             attrs, 0, NULL, NULL, NULL, LDAP_NO_LIMIT, res);
  if (rc != LDAP_SUCCESS) {
    if (*res) {
      ldap_msgfree(*res);
      *res = NULL;
    }
    return ls_ldap_fail(err, LS_SEARCH_FAILED, rc);
  }
  return LS_OK;
}

int ls_fetch_root_entry(const char *host, uint16_t port, bool use_ssl,
                        const char *bind_dn, const char *password,
                        const char *base_dn, LSEntry **out, LSError *err) {
  *out = NULL;

  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) return rc;

  LDAPMessage *res = NULL;
  rc = run_search(ld, base_dn, LDAP_SCOPE_SUBTREE, "(objectClass=*)", false,
                  &res, err);
  if (rc != LS_OK) {
    ldap_unbind_ext_s(ld, NULL, NULL);
    return rc;
  }

  /* Flatten every returned entry. */
  size_t n = 0;
  size_t cap = 16;
  FlatEntry *flat = ls_xmalloc(cap * sizeof(FlatEntry));
  for (LDAPMessage *m = ldap_first_entry(ld, res); m;
       m = ldap_next_entry(ld, m)) {
    char *dn = ldap_get_dn(ld, m);
    if (!dn) continue;
    if (n == cap) {
      cap *= 2;
      flat = ls_xrealloc(flat, cap * sizeof(FlatEntry));
    }
    flat[n].dn = ls_xstrdup(dn);
    flat[n].attrs = attributes_from(ld, m, &flat[n].nattrs);
    flat[n].taken = false;
    n++;
    ldap_memfree(dn);
  }
  ldap_msgfree(res);
  ldap_unbind_ext_s(ld, NULL, NULL);

  /* Index by DN, then link each entry to its parent. */
  Map by_dn;
  map_init(&by_dn, n ? n : 1);
  for (size_t i = 0; i < n; ++i) map_put(&by_dn, flat[i].dn, i);

  IdxList *children_of = ls_xcalloc(n ? n : 1, sizeof(IdxList));
  for (size_t i = 0; i < n; ++i) {
    char *p = parent_dn(flat[i].dn);
    size_t pi = map_get(&by_dn, p);
    free(p);
    if (pi != (size_t)-1 && pi != i) idx_push(&children_of[pi], i);
  }

  size_t root = map_get(&by_dn, base_dn);
  if (root == (size_t)-1) {
    char *reason =
        ls_aprintf("Base DN \"%s\" was not found", base_dn ? base_dn : "");
    rc = ls_fail(err, LS_SEARCH_FAILED, NULL, 0, reason);
    free(reason);
  } else {
    *out = ls_xmalloc(sizeof(LSEntry));
    **out = build_entry(root, flat, children_of);
    rc = LS_OK;
  }

  for (size_t i = 0; i < n; ++i) {
    free(children_of[i].items);
    if (!flat[i].taken) free_attr_array(flat[i].attrs, flat[i].nattrs);
    free(flat[i].dn);
  }
  free(children_of);
  free(flat);
  map_free(&by_dn);
  return rc;
}

int ls_search_directory(const char *host, uint16_t port, bool use_ssl,
                        const char *bind_dn, const char *password,
                        const char *base_dn, LSScope scope, const char *filter,
                        bool include_operational, LSEntry **out,
                        size_t *out_count, LSError *err) {
  *out = NULL;
  *out_count = 0;

  int lscope = LDAP_SCOPE_SUBTREE;
  if (scope == LS_SCOPE_BASE)
    lscope = LDAP_SCOPE_BASE;
  else if (scope == LS_SCOPE_ONELEVEL)
    lscope = LDAP_SCOPE_ONELEVEL;

  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) return rc;

  LDAPMessage *res = NULL;
  rc = run_search(ld, base_dn, lscope, filter, include_operational, &res, err);
  if (rc != LS_OK) {
    ldap_unbind_ext_s(ld, NULL, NULL);
    return rc;
  }

  size_t n = 0;
  size_t cap = 8;
  LSEntry *entries = ls_xmalloc(cap * sizeof(LSEntry));
  for (LDAPMessage *m = ldap_first_entry(ld, res); m;
       m = ldap_next_entry(ld, m)) {
    char *dn = ldap_get_dn(ld, m);
    if (!dn) continue;
    if (n == cap) {
      cap *= 2;
      entries = ls_xrealloc(entries, cap * sizeof(LSEntry));
    }
    LSEntry *e = &entries[n++];
    e->dn = ls_xstrdup(dn);
    e->name = display_name(dn);
    e->attributes = attributes_from(ld, m, &e->attribute_count);
    e->has_children = false;
    e->children = NULL;
    e->child_count = 0;
    ldap_memfree(dn);
  }
  ldap_msgfree(res);
  ldap_unbind_ext_s(ld, NULL, NULL);

  *out = entries;
  *out_count = n;
  return LS_OK;
}

/* ── modify family ───────────────────────────────────────────────── */

/* value bytes: base64-decode when is_binary, else the raw string. Caller
 * frees *bytes. Matches the old value_bytes() (bad base64 → empty). */
static void value_bytes(const char *value, bool is_binary, char **bytes,
                        ber_len_t *len) {
  if (is_binary) {
    size_t n = 0;
    uint8_t *decoded = ls_b64_decode(value, &n);
    *bytes = (char *)decoded;
    *len = n;
  } else {
    *bytes = ls_xstrdup(value ? value : "");
    *len = value ? strlen(value) : 0;
  }
}

/* Opens a connection, runs `mods` against `dn`, unbinds. */
static int run_modify(const char *host, uint16_t port, bool use_ssl,
                      const char *bind_dn, const char *password, const char *dn,
                      LDAPMod **mods, LSError *err) {
  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) return rc;

  int lrc = ldap_modify_ext_s(ld, dn, mods, NULL, NULL);
  ldap_unbind_ext_s(ld, NULL, NULL);
  if (lrc != LDAP_SUCCESS) return ls_ldap_fail(err, LS_MODIFY_FAILED, lrc);
  return LS_OK;
}

int ls_delete_entry(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, const char *dn,
                    LSError *err) {
  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) return rc;

  int lrc = ldap_delete_ext_s(ld, dn, NULL, NULL);
  ldap_unbind_ext_s(ld, NULL, NULL);
  if (lrc != LDAP_SUCCESS) return ls_ldap_fail(err, LS_MODIFY_FAILED, lrc);
  return LS_OK;
}

int ls_add_attribute_value(const char *host, uint16_t port, bool use_ssl,
                           const char *bind_dn, const char *password,
                           const char *dn, const char *attribute,
                           const char *value, LSError *err) {
  char *vals[] = {(char *)(value ? value : ""), NULL};
  LDAPMod mod = {
      .mod_op = LDAP_MOD_ADD,
      .mod_type = (char *)attribute,
      .mod_vals.modv_strvals = vals,
  };
  LDAPMod *mods[] = {&mod, NULL};
  return run_modify(host, port, use_ssl, bind_dn, password, dn, mods, err);
}

int ls_set_attribute_value(const char *host, uint16_t port, bool use_ssl,
                           const char *bind_dn, const char *password,
                           const char *dn, const char *attribute,
                           const char *value, bool is_binary, LSError *err) {
  char *bytes;
  ber_len_t len;
  value_bytes(value, is_binary, &bytes, &len);
  struct berval bv = {.bv_len = len, .bv_val = bytes};
  struct berval *bvals[] = {&bv, NULL};
  LDAPMod mod = {
      .mod_op = LDAP_MOD_REPLACE | LDAP_MOD_BVALUES,
      .mod_type = (char *)attribute,
      .mod_vals.modv_bvals = bvals,
  };
  LDAPMod *mods[] = {&mod, NULL};
  int rc = run_modify(host, port, use_ssl, bind_dn, password, dn, mods, err);
  free(bytes);
  return rc;
}

int ls_delete_attribute_value(const char *host, uint16_t port, bool use_ssl,
                              const char *bind_dn, const char *password,
                              const char *dn, const char *attribute,
                              const char *value, bool is_binary, LSError *err) {
  char *bytes;
  ber_len_t len;
  value_bytes(value, is_binary, &bytes, &len);
  struct berval bv = {.bv_len = len, .bv_val = bytes};
  struct berval *bvals[] = {&bv, NULL};
  LDAPMod mod = {
      .mod_op = LDAP_MOD_DELETE | LDAP_MOD_BVALUES,
      .mod_type = (char *)attribute,
      .mod_vals.modv_bvals = bvals,
  };
  LDAPMod *mods[] = {&mod, NULL};
  int rc = run_modify(host, port, use_ssl, bind_dn, password, dn, mods, err);
  free(bytes);
  return rc;
}

int ls_modify_attribute_value(const char *host, uint16_t port, bool use_ssl,
                              const char *bind_dn, const char *password,
                              const char *dn, const char *attribute,
                              const char *old_value, const char *new_value,
                              bool is_binary, LSError *err) {
  /* Targeted delete-then-add of just this value, so other values of a
   * multi-valued attribute survive (a plain Replace would wipe them). */
  char *old_bytes;
  char *new_bytes;
  ber_len_t old_len;
  ber_len_t new_len;
  value_bytes(old_value, is_binary, &old_bytes, &old_len);
  value_bytes(new_value, is_binary, &new_bytes, &new_len);

  struct berval old_bv = {.bv_len = old_len, .bv_val = old_bytes};
  struct berval new_bv = {.bv_len = new_len, .bv_val = new_bytes};
  struct berval *old_bvals[] = {&old_bv, NULL};
  struct berval *new_bvals[] = {&new_bv, NULL};

  LDAPMod del = {
      .mod_op = LDAP_MOD_DELETE | LDAP_MOD_BVALUES,
      .mod_type = (char *)attribute,
      .mod_vals.modv_bvals = old_bvals,
  };
  LDAPMod add = {
      .mod_op = LDAP_MOD_ADD | LDAP_MOD_BVALUES,
      .mod_type = (char *)attribute,
      .mod_vals.modv_bvals = new_bvals,
  };
  LDAPMod *mods[] = {&del, &add, NULL};
  int rc = run_modify(host, port, use_ssl, bind_dn, password, dn, mods, err);
  free(old_bytes);
  free(new_bytes);
  return rc;
}

int ls_move_entry(const char *host, uint16_t port, bool use_ssl,
                  const char *bind_dn, const char *password, const char *dn,
                  const char *new_superior, LSError *err) {
  char *rdn = display_name(dn); /* keep the current RDN */

  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) {
    free(rdn);
    return rc;
  }

  int lrc = ldap_rename_s(ld, dn, rdn,
                          (new_superior && *new_superior) ? new_superior : NULL,
                          1 /* deleteoldrdn */, NULL, NULL);
  ldap_unbind_ext_s(ld, NULL, NULL);
  free(rdn);
  if (lrc != LDAP_SUCCESS) return ls_ldap_fail(err, LS_MODIFY_FAILED, lrc);
  return LS_OK;
}

int ls_rename_entry(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, const char *dn,
                    const char *new_rdn, bool delete_old_rdn,
                    const char *new_superior, LSError *err) {
  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) return rc;

  int lrc = ldap_rename_s(ld, dn, new_rdn ? new_rdn : "",
                          (new_superior && *new_superior) ? new_superior : NULL,
                          (int)delete_old_rdn, NULL, NULL);
  ldap_unbind_ext_s(ld, NULL, NULL);
  if (lrc != LDAP_SUCCESS) return ls_ldap_fail(err, LS_MODIFY_FAILED, lrc);
  return LS_OK;
}

/* ── batched modify ─────────────────────────────────────────────── */

static int mod_op_flag(LSModKind kind) {
  switch (kind) {
    case LS_MOD_ADD:
      return LDAP_MOD_ADD;
    case LS_MOD_DELETE:
      return LDAP_MOD_DELETE;
    case LS_MOD_REPLACE:
      return LDAP_MOD_REPLACE;
  }
  return LDAP_MOD_ADD;
}

/* Fills `mod` (and the berval arrays it points at, all malloc'd) from one
 * LSModOp. `bvals`/`bptrs` must be freed by the caller along with each
 * bv_val; a NULL value list (whole-attribute op) leaves modv_bvals NULL. */
static void build_mod(const LSModOp *op, LDAPMod *mod, struct berval **bvals,
                      struct berval ***bptrs) {
  *bvals = NULL;
  *bptrs = NULL;
  if (op->value_count > 0) {
    *bvals = ls_xmalloc(op->value_count * sizeof(struct berval));
    *bptrs = ls_xmalloc((op->value_count + 1) * sizeof(struct berval *));
    for (size_t i = 0; i < op->value_count; ++i) {
      char *bytes = NULL;
      ber_len_t len = 0;
      value_bytes(op->values[i].value, op->values[i].is_binary, &bytes, &len);
      (*bvals)[i].bv_val = bytes;
      (*bvals)[i].bv_len = len;
      (*bptrs)[i] = &(*bvals)[i];
    }
    (*bptrs)[op->value_count] = NULL;
  }
  mod->mod_op = mod_op_flag(op->kind) | LDAP_MOD_BVALUES;
  mod->mod_type = (char *)op->attribute;
  mod->mod_vals.modv_bvals = *bptrs;
}

int ls_modify_entry(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, const char *dn,
                    const LSModOp *ops, size_t op_count, LSError *err) {
  LDAPMod *mods = ls_xcalloc(op_count, sizeof(LDAPMod));
  LDAPMod **modp = ls_xcalloc(op_count + 1, sizeof(LDAPMod *));
  struct berval **all_bvals = ls_xcalloc(op_count, sizeof(struct berval *));
  struct berval ***all_bptrs = ls_xcalloc(op_count, sizeof(struct berval **));

  for (size_t i = 0; i < op_count; ++i) {
    build_mod(&ops[i], &mods[i], &all_bvals[i], &all_bptrs[i]);
    modp[i] = &mods[i];
  }
  modp[op_count] = NULL;

  int rc = run_modify(host, port, use_ssl, bind_dn, password, dn, modp, err);

  for (size_t i = 0; i < op_count; ++i) {
    if (all_bvals[i]) {
      for (size_t k = 0; k < ops[i].value_count; ++k)
        free(all_bvals[i][k].bv_val);
      free(all_bvals[i]);
    }
    free(all_bptrs[i]);
  }
  free(all_bvals);
  free(all_bptrs);
  free(mods);
  free(modp);
  return rc;
}

/* ── add_entry ───────────────────────────────────────────────────── */

typedef struct {
  char *name;
  struct berval *bvals;  /* array of values */
  struct berval **bptrs; /* NULL-terminated pointer array for LDAPMod */
  size_t count;
  size_t cap;
} AttrGroup;

int ls_add_entry(const char *host, uint16_t port, bool use_ssl,
                 const char *bind_dn, const char *password, const char *dn,
                 const LSAttribute *attributes, size_t attribute_count,
                 LSError *err) {
  /* Group values by attribute name. */
  AttrGroup *groups = NULL;
  size_t ngroups = 0;
  size_t gcap = 0;

  for (size_t i = 0; i < attribute_count; ++i) {
    const LSAttribute *a = &attributes[i];

    size_t gi = (size_t)-1;
    for (size_t g = 0; g < ngroups; ++g)
      if (strcmp(groups[g].name, a->name) == 0) {
        gi = g;
        break;
      }
    if (gi == (size_t)-1) {
      if (ngroups == gcap) {
        gcap = gcap ? gcap * 2 : 4;
        groups = ls_xrealloc(groups, gcap * sizeof(AttrGroup));
      }
      gi = ngroups++;
      groups[gi] = (AttrGroup){.name = ls_xstrdup(a->name)};
    }

    AttrGroup *g = &groups[gi];
    if (g->count == g->cap) {
      g->cap = g->cap ? g->cap * 2 : 4;
      g->bvals = ls_xrealloc(g->bvals, g->cap * sizeof(struct berval));
    }
    char *bytes;
    ber_len_t len;
    value_bytes(a->value, a->is_binary, &bytes, &len);
    g->bvals[g->count].bv_val = bytes;
    g->bvals[g->count].bv_len = len;
    g->count++;
  }

  LDAPMod *mods = ls_xcalloc(ngroups + 1, sizeof(LDAPMod));
  LDAPMod **modp = ls_xcalloc(ngroups + 1, sizeof(LDAPMod *));
  for (size_t g = 0; g < ngroups; ++g) {
    groups[g].bptrs =
        ls_xmalloc((groups[g].count + 1) * sizeof(struct berval *));
    for (size_t k = 0; k < groups[g].count; ++k)
      groups[g].bptrs[k] = &groups[g].bvals[k];
    groups[g].bptrs[groups[g].count] = NULL;

    mods[g].mod_op = LDAP_MOD_ADD | LDAP_MOD_BVALUES;
    mods[g].mod_type = groups[g].name;
    mods[g].mod_vals.modv_bvals = groups[g].bptrs;
    modp[g] = &mods[g];
  }
  modp[ngroups] = NULL;

  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc == LS_OK) {
    int lrc = ldap_add_ext_s(ld, dn, modp, NULL, NULL);
    ldap_unbind_ext_s(ld, NULL, NULL);
    if (lrc != LDAP_SUCCESS) rc = ls_ldap_fail(err, LS_MODIFY_FAILED, lrc);
  }

  for (size_t g = 0; g < ngroups; ++g) {
    for (size_t k = 0; k < groups[g].count; ++k)
      free(groups[g].bvals[k].bv_val);
    free(groups[g].bvals);
    free(groups[g].bptrs);
    free(groups[g].name);
  }
  free(groups);
  free(mods);
  free(modp);
  return rc;
}
