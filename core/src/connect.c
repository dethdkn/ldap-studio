/*
 * connect.c — everything about getting a bound LDAP* handle: the
 * per-connection policy (TLS, auth, timeout, SSH), the SSH tunnel cache,
 * the hard connect deadline, the certificate probe used by the trust
 * dialog, and ls_connect_and_bind itself. Browsing, searching and
 * modifying live in ldap.c and only ever call ls_connect_and_bind.
 */
#include <ctype.h>
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <pthread.h>
#include <sasl/sasl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>

#include "internal_ldap.h"
#include "ssh_tunnel.h"

/* ── connection ───────────────────────────────────────────────────── */

int ls_ldap_fail(LSError *err, LSErrorKind kind, int rc) {
  return ls_fail(err, kind, NULL, 0, ldap_err2string(rc));
}

/* Wall-clock seconds, for measuring how long a connect/StartTLS attempt
 * actually took — see classify_tls_failure below for why. */
static double monotonic_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + ((double)ts.tv_nsec / 1e9);
}

/* Backs run_with_deadline below. */
typedef struct {
  LDAP *ld;
  double deadline;
  volatile bool call_done;
} ConnectDeadline;

static void *connect_deadline_watch(void *arg) {
  ConnectDeadline *w = arg;
  while (!w->call_done && monotonic_seconds() < w->deadline) {
    struct timespec nap = {0, 20L * 1000 * 1000}; /* 20ms */
    nanosleep(&nap, NULL);
  }
  if (!w->call_done) {
    /* The deadline passed and fn() (running on the caller's thread) still
     * hasn't returned. The fd only exists once fn() actually starts
     * connecting, so it's fetched here rather than up front. Shutting it
     * down unblocks whatever read/write fn() is stuck in. */
    ber_socket_t fd = (ber_socket_t)-1;
    if (ldap_get_option(w->ld, LDAP_OPT_DESC, &fd) == LDAP_OPT_SUCCESS &&
        fd != (ber_socket_t)-1) {
      shutdown(fd, SHUT_RDWR);
    }
  }
  return NULL;
}

/* Runs a blocking libldap connect/StartTLS attempt under a hard deadline.
 * LDAP_OPT_NETWORK_TIMEOUT only bounds the raw connect() syscall inside
 * ldap_connect()/ldap_start_tls_s() — the TLS handshake those same calls
 * do for ldaps:// and StartTLS has no reliable timeout of its own. A peer
 * that completes the TCP handshake and then stalls the TLS handshake (a
 * firewall that lets SYN/ACK through but drops the rest is a common way
 * this happens) can hang well past the configured timeout with nothing to
 * stop it.
 *
 * (An earlier version of this fix connected the socket ourselves and
 * handed it to libldap via ldap_init_fd so SO_RCVTIMEO/SO_SNDTIMEO could
 * be armed before any TLS traffic. That turned out to silently break
 * ldaps:// — confirmed against a real slapd instance: the TLS handshake
 * ldap_connect() is supposed to trigger for an implicit-TLS URL never
 * happens when the fd arrives pre-connected, and the bind fails
 * immediately. So instead: run the call on a deadline enforced from
 * outside it, without changing how the connection is established at
 * all.)
 *
 * If `fn` hasn't returned by the deadline, a watchdog thread shuts down
 * `ld`'s socket out from under it — the blocked read/write `fn` is
 * waiting on then fails and `fn` returns with an error, which the
 * caller's elapsed-time check (see classify_tls_failure) correctly
 * reports as a timeout. */
static int run_with_deadline(LDAP *ld, unsigned timeout_seconds,
                             int (*fn)(LDAP *)) {
  ConnectDeadline w = {
      .ld = ld,
      .deadline = monotonic_seconds() + (double)timeout_seconds,
      .call_done = false,
  };
  pthread_t thread;
  bool watching =
      pthread_create(&thread, NULL, connect_deadline_watch, &w) == 0;

  int rc = fn(ld);
  w.call_done = true;
  if (watching) pthread_join(thread, NULL);
  return rc;
}

static int call_ldap_connect(LDAP *ld) { return ldap_connect(ld); }

static int call_ldap_start_tls(LDAP *ld) {
  return ldap_start_tls_s(ld, NULL, NULL);
}

/* ── connection policy ────────────────────────────────────────────── */
/*
 * Everything that shapes how the next connection is made. The Swift layer
 * rewrites it (the ls_set_* calls) immediately before every operation, so
 * it lives in one process-wide struct — but a connection attempt never
 * reads that struct directly; it works on its own deep copy (policy_clone).
 * That matters because an attempt can outlive the call that started it
 * (see ls_connect_and_bind's hard deadline): without a private copy, the
 * next operation's ls_set_* would free() strings an abandoned attempt is
 * still reading.
 */
typedef struct {
  /* TLS — see ls_set_tls_cacert / ls_set_tls_policy */
  char *tls_cacert; /* PEM CA bundle shipped in the app; set once at startup */
  bool start_tls;
  bool allow_untrusted;
  char *pinned_sha256; /* lowercase hex, no separators; NULL = none */
  /* behavior + bind method — see ls_set_connection_policy */
  bool chase_referrals;
  unsigned timeout_seconds;
  LSAuthMethod auth_method;
  char *auth_id;
  char *auth_realm;
  char *client_cert_path;
  char *client_key_path;
  /* SSH tunnel — see ls_set_ssh_policy */
  bool ssh_enabled;
  char *ssh_host;
  uint16_t ssh_port;
  char *ssh_username;
  LSSSHAuthMethod ssh_auth_method;
  char *ssh_password;
  char *ssh_private_key_path;
  char *ssh_host_key_sha256;
} ConnPolicy;

static ConnPolicy g_policy = {
    .timeout_seconds = LS_CONNECT_TIMEOUT_SECS,
    .auth_method = LS_AUTH_SIMPLE,
    .ssh_port = 22,
};

static int probe_certificate(const ConnPolicy *p, const char *host,
                             uint16_t port, bool use_ssl, bool start_tls,
                             LSCertInfo *out, LSError *err);

static void replace_string(char **slot, const char *value) {
  free(*slot);
  *slot = value && *value ? ls_xstrdup(value) : NULL;
}

/* Deep copy — scalars by value, every string re-duplicated. */
static ConnPolicy *policy_clone(const ConnPolicy *src) {
  ConnPolicy *p = ls_xmalloc(sizeof *p);
  *p = *src;
  p->tls_cacert = ls_xstrdup(src->tls_cacert);
  p->pinned_sha256 = ls_xstrdup(src->pinned_sha256);
  p->auth_id = ls_xstrdup(src->auth_id);
  p->auth_realm = ls_xstrdup(src->auth_realm);
  p->client_cert_path = ls_xstrdup(src->client_cert_path);
  p->client_key_path = ls_xstrdup(src->client_key_path);
  p->ssh_host = ls_xstrdup(src->ssh_host);
  p->ssh_username = ls_xstrdup(src->ssh_username);
  p->ssh_password = ls_xstrdup(src->ssh_password);
  p->ssh_private_key_path = ls_xstrdup(src->ssh_private_key_path);
  p->ssh_host_key_sha256 = ls_xstrdup(src->ssh_host_key_sha256);
  return p;
}

static void policy_free(ConnPolicy *p) {
  if (!p) return;
  free(p->tls_cacert);
  free(p->pinned_sha256);
  free(p->auth_id);
  free(p->auth_realm);
  free(p->client_cert_path);
  free(p->client_key_path);
  free(p->ssh_host);
  free(p->ssh_username);
  free(p->ssh_password);
  free(p->ssh_private_key_path);
  free(p->ssh_host_key_sha256);
  free(p);
}

void ls_set_connection_policy(bool chase_referrals, unsigned timeout_seconds,
                              LSAuthMethod auth_method, const char *auth_id,
                              const char *realm, const char *client_cert_path,
                              const char *client_key_path) {
  g_policy.chase_referrals = chase_referrals;
  g_policy.timeout_seconds = timeout_seconds > 0 ? timeout_seconds : 1;
  g_policy.auth_method = auth_method;
  replace_string(&g_policy.auth_id, auth_id);
  replace_string(&g_policy.auth_realm, realm);
  replace_string(&g_policy.client_cert_path, client_cert_path);
  replace_string(&g_policy.client_key_path, client_key_path);
}

void ls_set_ssh_policy(bool enabled, const char *host, uint16_t port,
                       const char *username, LSSSHAuthMethod auth_method,
                       const char *password, const char *private_key_path,
                       const char *pinned_host_key_sha256) {
  g_policy.ssh_enabled = enabled;
  replace_string(&g_policy.ssh_host, host);
  g_policy.ssh_port = port;
  replace_string(&g_policy.ssh_username, username);
  g_policy.ssh_auth_method = auth_method;
  replace_string(&g_policy.ssh_password, password);
  replace_string(&g_policy.ssh_private_key_path, private_key_path);
  replace_string(&g_policy.ssh_host_key_sha256, pinned_host_key_sha256);
}

void ls_disconnect(LDAP *ld) {
  if (!ld) return;
  ldap_unbind_ext_s(ld, NULL, NULL);
}

/* ── SSH tunnel cache ─────────────────────────────────────────────── */
/*
 * Every exported call above opens a fresh LDAP* and unbinds it when done
 * (see the file header) — fine for a bare TCP connect, but an SSH tunnel
 * means a full handshake plus authentication, which is far too expensive
 * to pay for every browse click or attribute edit. So a tunnel outlives
 * the single operation that first opened it: it's kept here, keyed by
 * the SSH + target-server settings that produced it, and reused by later
 * operations as long as those settings don't change. It's closed and
 * replaced when they do, when it's gone idle, or when the forwarding
 * loop reports it broke.
 */
typedef struct SSHTunnelCacheEntry {
  char *ssh_host;
  uint16_t ssh_port;
  char *ssh_username;
  LSSSHAuthMethod ssh_auth_method;
  char *target_host;
  uint16_t target_port;
  LSSSHTunnel *tunnel;
  time_t last_used;
  struct SSHTunnelCacheEntry *next;
} SSHTunnelCacheEntry;

#define LS_SSH_TUNNEL_IDLE_SECS 180

static SSHTunnelCacheEntry *g_ssh_cache;
static pthread_mutex_t g_ssh_cache_lock = PTHREAD_MUTEX_INITIALIZER;

static void free_cache_entry(SSHTunnelCacheEntry *entry) {
  ls_ssh_tunnel_stop(entry->tunnel);
  free(entry->ssh_host);
  free(entry->ssh_username);
  free(entry->target_host);
  free(entry);
}

/* Drops cache entries that have gone idle or whose forwarding loop
 * reported them broken — regardless of whether they match what the
 * current call wants, so a tunnel kept warm for another still-open
 * window isn't touched. Called with the lock held. */
static void reap_ssh_cache_locked(time_t now) {
  SSHTunnelCacheEntry **slot = &g_ssh_cache;
  while (*slot) {
    SSHTunnelCacheEntry *entry = *slot;
    if (!ls_ssh_tunnel_is_alive(entry->tunnel) ||
        now - entry->last_used > LS_SSH_TUNNEL_IDLE_SECS) {
      *slot = entry->next;
      free_cache_entry(entry);
      continue;
    }
    slot = &entry->next;
  }
}

/* Hands back a loopback port with a live SSH tunnel behind it, reusing a
 * cached one when the current SSH policy and target match, otherwise
 * opening (and caching) a new one. */
static int acquire_ssh_tunnel(const ConnPolicy *p, const char *host,
                              uint16_t port, uint16_t *connect_port,
                              LSError *err) {
  /* The UI won't save a tunnel without these, but an imported connection
   * file can still ask for one — and a NULL host would otherwise crash the
   * strcmp below or, worse, make getaddrinfo(NULL) connect to localhost. */
  if (!p->ssh_host || !p->ssh_username) {
    return ls_fail(err, LS_CONNECT_FAILED, host, port,
                   "The SSH tunnel needs a host and a username");
  }
  pthread_mutex_lock(&g_ssh_cache_lock);
  time_t now = time(NULL);
  reap_ssh_cache_locked(now);

  for (SSHTunnelCacheEntry *entry = g_ssh_cache; entry; entry = entry->next) {
    if (entry->ssh_port == p->ssh_port && entry->target_port == port &&
        entry->ssh_auth_method == p->ssh_auth_method &&
        strcmp(entry->ssh_host, p->ssh_host) == 0 &&
        strcmp(entry->ssh_username, p->ssh_username) == 0 &&
        strcmp(entry->target_host, host) == 0) {
      entry->last_used = now;
      *connect_port = ls_ssh_tunnel_local_port(entry->tunnel);
      pthread_mutex_unlock(&g_ssh_cache_lock);
      return LS_OK;
    }
  }

  LSSSHTunnel *tunnel = NULL;
  uint16_t local_port = 0;
  int rc = ls_ssh_tunnel_start(
      p->ssh_host, p->ssh_port, p->ssh_username, p->ssh_auth_method,
      p->ssh_password, p->ssh_private_key_path, p->ssh_host_key_sha256, host,
      port, p->timeout_seconds, &tunnel, &local_port, err);
  if (rc != LS_OK) {
    pthread_mutex_unlock(&g_ssh_cache_lock);
    return rc;
  }

  SSHTunnelCacheEntry *entry = ls_xmalloc(sizeof *entry);
  entry->ssh_host = ls_xstrdup(p->ssh_host);
  entry->ssh_port = p->ssh_port;
  entry->ssh_username = ls_xstrdup(p->ssh_username);
  entry->ssh_auth_method = p->ssh_auth_method;
  entry->target_host = ls_xstrdup(host);
  entry->target_port = port;
  entry->tunnel = tunnel;
  entry->last_used = now;
  entry->next = g_ssh_cache;
  g_ssh_cache = entry;

  *connect_port = local_port;
  pthread_mutex_unlock(&g_ssh_cache_lock);
  return LS_OK;
}

/* Attempts the caller has given up on but that are still running. Counted so
 * ls_shutdown can let them finish unwinding before the process exits —
 * otherwise exit()'s OpenSSL cleanup can race a worker that is still inside
 * libssh2/OpenSSL teardown. */
static pthread_mutex_t g_abandoned_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_abandoned_cond = PTHREAD_COND_INITIALIZER;
static unsigned g_abandoned_count;

static void abandoned_attempts_add(int delta) {
  pthread_mutex_lock(&g_abandoned_lock);
  g_abandoned_count = (unsigned)((int)g_abandoned_count + delta);
  if (g_abandoned_count == 0) pthread_cond_broadcast(&g_abandoned_cond);
  pthread_mutex_unlock(&g_abandoned_lock);
}

/* Closes every cached SSH tunnel right away — for app shutdown, or after
 * the app-level connection settings change so a stale one isn't reused. */
void ls_close_ssh_tunnels(void) {
  pthread_mutex_lock(&g_ssh_cache_lock);
  while (g_ssh_cache) {
    SSHTunnelCacheEntry *entry = g_ssh_cache;
    g_ssh_cache = entry->next;
    free_cache_entry(entry);
  }
  pthread_mutex_unlock(&g_ssh_cache_lock);
}

void ls_shutdown(unsigned wait_ms) {
  struct timespec deadline;
  clock_gettime(CLOCK_REALTIME, &deadline);
  deadline.tv_sec += (time_t)(wait_ms / 1000U);
  deadline.tv_nsec += (long)(wait_ms % 1000U) * 1000000L;
  if (deadline.tv_nsec >= 1000000000L) {
    deadline.tv_sec += 1;
    deadline.tv_nsec -= 1000000000L;
  }

  pthread_mutex_lock(&g_abandoned_lock);
  int wait_rc = 0;
  while (g_abandoned_count > 0 && wait_rc == 0) {
    wait_rc =
        pthread_cond_timedwait(&g_abandoned_cond, &g_abandoned_lock, &deadline);
  }
  pthread_mutex_unlock(&g_abandoned_lock);

  ls_close_ssh_tunnels();
}

typedef struct {
  const char *auth_id;
  const char *password;
  const char *realm;
} LSSASLDefaults;

static int sasl_interact(LDAP *ld, unsigned flags, void *defaults,
                         void *interactions) {
  (void)ld;
  (void)flags;
  LSSASLDefaults *d = defaults;
  for (sasl_interact_t *i = interactions; i && i->id != SASL_CB_LIST_END; i++) {
    const char *value = "";
    if (i->id == SASL_CB_AUTHNAME || i->id == SASL_CB_USER)
      value = d->auth_id ? d->auth_id : "";
    else if (i->id == SASL_CB_PASS)
      value = d->password ? d->password : "";
    else if (i->id == SASL_CB_GETREALM)
      value = d->realm ? d->realm : "";
    i->result = value;
    i->len = (unsigned)strlen(value);
  }
  return LDAP_SUCCESS;
}

void ls_set_tls_cacert(const char *path) {
  free(g_policy.tls_cacert);
  g_policy.tls_cacert = path ? ls_xstrdup(path) : NULL;
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
  g_policy.start_tls = start_tls;
  g_policy.allow_untrusted = allow_untrusted;
  free(g_policy.pinned_sha256);
  g_policy.pinned_sha256 = pinned_sha256 ? normalize_hex(pinned_sha256) : NULL;
}

/* Lowercase-hex encode `len` bytes into `out` (needs len*2 + 1 bytes). */
static void hex_encode(const unsigned char *bytes, size_t len, char *out) {
  static const char digits[] = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) {
    unsigned byte = bytes[i];
    out[i * 2] = digits[byte >> 4U];
    out[(i * 2) + 1] = digits[byte & 0x0FU];
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
 * fault.
 *
 * `elapsed_seconds` is how long the attempt that just failed actually
 * took. In practice libldap never reports our own connect-phase deadline
 * (SO_RCVTIMEO / LDAP_OPT_NETWORK_TIMEOUT expiring) as LDAP_TIMEOUT — an
 * unreachable host comes back as LDAP_SERVER_DOWN just like a live host
 * that rejects the connection outright, so `rc == LDAP_TIMEOUT` below
 * essentially never fires for this case. Without the elapsed-time check,
 * every timed-out TLS/StartTLS attempt would fall through to the re-probe
 * and silently wait the full timeout a second time. */
static LSErrorKind classify_tls_failure(const ConnPolicy *p, const char *host,
                                        uint16_t port, bool use_ssl, int rc,
                                        double elapsed_seconds) {
  if (rc == LDAP_TIMEOUT) return LS_CONNECT_TIMED_OUT;
  if (elapsed_seconds >= (double)p->timeout_seconds - 0.5) {
    return LS_CONNECT_TIMED_OUT;
  }
  /* Verification is already off for pinned / allow-untrusted attempts and
   * for SSH-tunneled ones (the cert can't match 127.0.0.1), so a failure
   * there can't be a rejected certificate — and a direct re-probe of an
   * SSH-only-reachable host would just wait out the timeout again. */
  if (p->allow_untrusted || p->pinned_sha256 != NULL || p->ssh_enabled) {
    return LS_CONNECT_FAILED;
  }
  LSCertInfo probe = {0};
  LSError probe_err = {0};
  int prc = probe_certificate(p, host, port, use_ssl, p->start_tls, &probe,
                              &probe_err);
  ls_cert_info_dispose(&probe);
  ls_error_dispose(&probe_err);
  return prc == LS_OK ? LS_TLS_UNTRUSTED : LS_CONNECT_FAILED;
}

/* Sets the client-side TLS options (verification mode, CA bundle, client
 * cert/key, and the "build a new context" trigger) once TLS is known to
 * apply to this connection. Split out of ls_connect_and_bind to keep its
 * cognitive complexity down. */
static void apply_tls_client_options(const ConnPolicy *p, LDAP *ld) {
  /* Verification stays at the library default (demand a valid chain)
   * unless the connection is pinned, the user chose "allow untrusted", or
   * it's going over a local SSH forward (whose cert can't match the real
   * hostname) — then it's the pin (or nothing) that gates acceptance. */
  int require = (p->allow_untrusted || p->pinned_sha256 || p->ssh_enabled)
                    ? LDAP_OPT_X_TLS_NEVER
                    : LDAP_OPT_X_TLS_DEMAND;
  ldap_set_option(ld, LDAP_OPT_X_TLS_REQUIRE_CERT, &require);
  /* The bundled OpenSSL can't reach its own default store under the
   * sandbox, so point it at the app's CA bundle when we're verifying. */
  if (p->tls_cacert && require == LDAP_OPT_X_TLS_DEMAND) {
    ldap_set_option(ld, LDAP_OPT_X_TLS_CACERTFILE, p->tls_cacert);
  }
  if (p->client_cert_path) {
    ldap_set_option(ld, LDAP_OPT_X_TLS_CERTFILE, p->client_cert_path);
  }
  if (p->client_key_path) {
    ldap_set_option(ld, LDAP_OPT_X_TLS_KEYFILE, p->client_key_path);
  }
  int newctx = 0; /* 0 = build a new client context now */
  ldap_set_option(ld, LDAP_OPT_X_TLS_NEWCTX, &newctx);
}

/* A failed ldap_connect() is either the TLS handshake rejecting the
 * certificate or a plain socket/timeout failure. `elapsed_seconds` — see
 * classify_tls_failure — is what actually catches our own configured
 * timeout firing, since libldap doesn't report it as LDAP_TIMEOUT. */
static LSErrorKind classify_connect_failure(const ConnPolicy *p, bool tls,
                                            const char *host, uint16_t port,
                                            bool use_ssl, int rc,
                                            double elapsed_seconds) {
  if (tls)
    return classify_tls_failure(p, host, port, use_ssl, rc, elapsed_seconds);
  if (rc == LDAP_TIMEOUT ||
      elapsed_seconds >= (double)p->timeout_seconds - 0.5) {
    return LS_CONNECT_TIMED_OUT;
  }
  return LS_CONNECT_FAILED;
}

/* Runs whichever bind p->auth_method calls for and returns the ldap_*
 * result code. */
static int perform_bind(const ConnPolicy *p, LDAP *ld, const char *bind_dn,
                        const char *password) {
  if (p->auth_method == LS_AUTH_SIMPLE) {
    struct berval cred;
    cred.bv_val = (char *)(password ? password : "");
    cred.bv_len = password ? strlen(password) : 0;
    const char *dn = (bind_dn && *bind_dn) ? bind_dn : NULL;
    struct berval *server_cred = NULL;
    int rc = ldap_sasl_bind_s(ld, dn, LDAP_SASL_SIMPLE, &cred, NULL, NULL,
                              &server_cred);
    if (server_cred) ber_bvfree(server_cred);
    return rc;
  }
  if (p->auth_method == LS_AUTH_EXTERNAL) {
    struct berval empty = {0, ""};
    struct berval *server_cred = NULL;
    int rc = ldap_sasl_bind_s(ld, NULL, "EXTERNAL", &empty, NULL, NULL,
                              &server_cred);
    if (server_cred) ber_bvfree(server_cred);
    return rc;
  }
  LSSASLDefaults defaults = {p->auth_id, password, p->auth_realm};
  const char *mechanism =
      p->auth_method == LS_AUTH_GSSAPI ? "GSSAPI" : "DIGEST-MD5";
  return ldap_sasl_interactive_bind_s(ld, NULL, mechanism, NULL, NULL,
                                      LDAP_SASL_QUIET, sasl_interact,
                                      &defaults);
}

/* A failed bind: timeout, an outright connection drop, or the mechanism
 * itself rejecting the credentials. */
static LSErrorKind classify_bind_failure(int rc) {
  if (rc == LDAP_TIMEOUT) return LS_CONNECT_TIMED_OUT;
  if (rc == LDAP_SERVER_DOWN || rc == LDAP_CONNECT_ERROR ||
      rc == LDAP_UNAVAILABLE || rc == LDAP_LOCAL_ERROR) {
    return LS_CONNECT_FAILED;
  }
  return LS_BIND_FAILED;
}

/* The actual connect+bind attempt — everything ls_connect_and_bind did
 * before the hard-deadline wrapper below was added. Still reads the g_*
 * policy globals directly; see ls_connect_and_bind for why that's safe
 * even though this can now run on a worker thread. */
static int ls_connect_and_bind_now(const ConnPolicy *p, const char *host,
                                   uint16_t port, bool use_ssl,
                                   const char *bind_dn, const char *password,
                                   LDAP **out, LSError *err) {
  *out = NULL;

  uint16_t connect_port = port;
  const char *connect_host = host;
  if (p->ssh_enabled) {
    int tunnel_rc = acquire_ssh_tunnel(p, host, port, &connect_port, err);
    if (tunnel_rc != LS_OK) return tunnel_rc;
    connect_host = "127.0.0.1";
  }

  bool tls = use_ssl;
  if (p->start_tls) tls = true;

  const char *scheme = "ldap";
  if (use_ssl) scheme = "ldaps";
  char *uri = ls_aprintf("%s://%s:%u", scheme, connect_host ? connect_host : "",
                         (unsigned)connect_port);
  LDAP *ld = NULL;
  int rc = ldap_initialize(&ld, uri);
  free(uri);
  if (rc != LDAP_SUCCESS || !ld) {
    /* The tunnel (if any) is cached independently of this LDAP* and
     * stays up for the next attempt — this failure is local to
     * ldap_initialize, not a sign the tunnel itself is bad. */
    return ls_fail(err, LS_CONNECT_FAILED, host, port, ldap_err2string(rc));
  }

  int version = LDAP_VERSION3;
  ldap_set_option(ld, LDAP_OPT_PROTOCOL_VERSION, &version);
  if (p->chase_referrals) {
    ldap_set_option(ld, LDAP_OPT_REFERRALS, LDAP_OPT_ON);
  } else {
    ldap_set_option(ld, LDAP_OPT_REFERRALS, LDAP_OPT_OFF);
  }

  struct timeval tv = {(time_t)p->timeout_seconds, 0};
  ldap_set_option(ld, LDAP_OPT_NETWORK_TIMEOUT, &tv);
  ldap_set_option(ld, LDAP_OPT_TIMEOUT, &tv);

  if (tls) apply_tls_client_options(p, ld);

  if (p->start_tls && !use_ssl) {
    double attempt_start = monotonic_seconds();
    rc = run_with_deadline(ld, p->timeout_seconds, call_ldap_start_tls);
    if (rc != LDAP_SUCCESS) {
      double elapsed = monotonic_seconds() - attempt_start;
      int out_rc = ls_fail(
          err, classify_tls_failure(p, host, port, use_ssl, rc, elapsed), host,
          port, ldap_err2string(rc));
      ldap_unbind_ext_s(ld, NULL, NULL);
      return out_rc;
    }
  }

  /* Connect explicitly even for plain LDAP. Leaving this deferred to a
   * synchronous bind lets some socket/read paths escape LDAP_OPT_TIMEOUT.
   * run_with_deadline is what actually bounds the ldaps:// TLS handshake
   * this triggers — see its comment. */
  double ldap_connect_start = monotonic_seconds();
  rc = run_with_deadline(ld, p->timeout_seconds, call_ldap_connect);
  if (rc != LDAP_SUCCESS) {
    double elapsed = monotonic_seconds() - ldap_connect_start;
    LSErrorKind kind =
        classify_connect_failure(p, tls, host, port, use_ssl, rc, elapsed);
    int out_rc = ls_fail(err, kind, host, port, ldap_err2string(rc));
    ldap_unbind_ext_s(ld, NULL, NULL);
    return out_rc;
  }

  /* Also apply the deadline at the connected socket level. OpenLDAP's
   * general timeout does not consistently cap every synchronous SASL/bind
   * read, whereas SO_RCVTIMEO/SO_SNDTIMEO does. -1 is the invalid-fd
   * sentinel here; AC_SOCKET_INVALID is an OpenLDAP-internal macro not
   * exposed by the public headers this target builds against. */
  ber_socket_t socket_fd = (ber_socket_t)-1;
  if (ldap_get_option(ld, LDAP_OPT_DESC, &socket_fd) == LDAP_OPT_SUCCESS &&
      socket_fd != (ber_socket_t)-1) {
    setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(socket_fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
  }

  if (p->pinned_sha256 && tls) {
    char got[(EVP_MAX_MD_SIZE * 2) + 1] = {0};
    if (!peer_cert_sha256(ld, got) || strcmp(got, p->pinned_sha256) != 0) {
      int out_rc = ls_fail(err, LS_TLS_UNTRUSTED, host, port,
                           "server certificate does not match the "
                           "fingerprint trusted for this connection");
      ldap_unbind_ext_s(ld, NULL, NULL);
      return out_rc;
    }
  }

  rc = perform_bind(p, ld, bind_dn, password);

  if (rc != LDAP_SUCCESS) {
    LSErrorKind kind = classify_bind_failure(rc);
    int out_rc = ls_fail(err, kind, host, port, ldap_err2string(rc));
    ldap_unbind_ext_s(ld, NULL, NULL);
    return out_rc;
  }

  *out = ld;
  return LS_OK;
}

/* ── hard connect deadline ────────────────────────────────────────── */
/*
 * run_with_deadline (above) bounds the two specific libldap calls that
 * usually stall, by shutting down the socket they're blocked on. That
 * assumes the stall is a blocked read/write on an already-open socket —
 * true for a TLS handshake that stops mid-negotiation, but not the only
 * way a "5 second timeout" can turn into 20+ seconds in practice: DNS
 * lookup, a multi-address host (this app's own dev server resolves to
 * both an A and a AAAA record) falling back from an unreachable address
 * to a working one, or the kernel's own connect()-retry behavior on a
 * route that never answers can each add delay LDAP_OPT_NETWORK_TIMEOUT
 * and run_with_deadline don't reach, because there's no libldap-owned
 * socket yet for either to act on.
 *
 * So this is the actual backstop: the whole attempt runs on its own
 * thread, and the caller simply stops waiting at the deadline — no
 * matter what the attempt turns out to be stuck on. The worker isn't
 * killed (POSIX has no safe way to do that); it's left to finish or fail
 * on its own and clean up after itself once nobody's waiting on it
 * anymore.
 */
typedef struct {
  /* Inputs — all owned copies, so the worker never touches the caller's
   * buffers or the live g_policy (see ConnPolicy for why). */
  ConnPolicy *policy;
  char *host;
  uint16_t port;
  bool use_ssl;
  char *bind_dn;
  char *password;

  pthread_mutex_t lock;
  pthread_cond_t cond;
  bool done;      /* protected by lock */
  bool abandoned; /* protected by lock — set if the waiter gave up */

  /* Filled in by the worker; only safe to read after observing `done`. */
  int rc;
  LDAP *ld;
  LSError err;
} ConnectAttempt;

static void connect_attempt_free(ConnectAttempt *a) {
  policy_free(a->policy);
  free(a->host);
  free(a->bind_dn);
  free(a->password);
  pthread_mutex_destroy(&a->lock);
  pthread_cond_destroy(&a->cond);
  free(a);
}

static void *connect_attempt_run(void *arg) {
  ConnectAttempt *a = arg;
  LDAP *ld = NULL;
  LSError err = {0};
  int rc = ls_connect_and_bind_now(a->policy, a->host, a->port, a->use_ssl,
                                   a->bind_dn, a->password, &ld, &err);

  pthread_mutex_lock(&a->lock);
  bool abandoned = a->abandoned;
  if (!abandoned) {
    a->rc = rc;
    a->ld = ld;
    a->err = err;
    a->done = true;
    pthread_cond_signal(&a->cond);
  }
  pthread_mutex_unlock(&a->lock);

  if (abandoned) {
    /* The caller already gave up and moved on — clean up ourselves
     * instead of handing a result nobody will read. */
    if (rc == LS_OK && ld) ldap_unbind_ext_s(ld, NULL, NULL);
    ls_error_dispose(&err);
    connect_attempt_free(a);
    abandoned_attempts_add(-1);
  }
  return NULL;
}

int ls_connect_and_bind(const char *host, uint16_t port, bool use_ssl,
                        const char *bind_dn, const char *password, LDAP **out,
                        LSError *err) {
  *out = NULL;

  ConnectAttempt *a = ls_xcalloc(1, sizeof *a);
  a->policy = policy_clone(&g_policy); /* snapshot before spawning */
  unsigned timeout_seconds = a->policy->timeout_seconds;
  a->host = ls_xstrdup(host);
  a->port = port;
  a->use_ssl = use_ssl;
  a->bind_dn = ls_xstrdup(bind_dn);
  a->password = ls_xstrdup(password);
  pthread_mutex_init(&a->lock, NULL);
  pthread_cond_init(&a->cond, NULL);

  pthread_t thread;
  if (pthread_create(&thread, NULL, connect_attempt_run, a) != 0) {
    connect_attempt_free(a);
    return ls_fail(err, LS_CONNECT_FAILED, host, port,
                   "Could not start the connection attempt");
  }

  struct timespec deadline;
  clock_gettime(CLOCK_REALTIME, &deadline);
  deadline.tv_sec += timeout_seconds;

  pthread_mutex_lock(&a->lock);
  int wait_rc = 0;
  while (!a->done && wait_rc == 0) {
    wait_rc = pthread_cond_timedwait(&a->cond, &a->lock, &deadline);
  }
  bool finished = a->done;
  if (!finished) {
    a->abandoned = true;
    abandoned_attempts_add(1);
  }
  pthread_mutex_unlock(&a->lock);

  if (finished) {
    pthread_join(thread, NULL); /* already done — returns immediately */
    *out = a->ld;
    int rc = a->rc;
    if (rc != LS_OK) {
      *err = a->err; /* transfers ownership of err's strings */
    } else {
      ls_error_dispose(&a->err);
    }
    connect_attempt_free(a);
    return rc;
  }

  /* Deadline hit first. The worker keeps running and cleans up after
   * itself (see connect_attempt_run) — `a` isn't touched again here. */
  pthread_detach(thread);
  return ls_fail(err, LS_CONNECT_TIMED_OUT, host, port,
                 "Did not finish within the configured timeout");
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
  /* XN_FLAG_RFC2253 is an OpenSSL macro built from signed bit-ORs. */
  /* NOLINTNEXTLINE(bugprone-signed-bitwise) */
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

static int probe_certificate(const ConnPolicy *p, const char *host,
                             uint16_t port, bool use_ssl, bool start_tls,
                             LSCertInfo *out, LSError *err) {
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
  struct timeval tv = {(time_t)p->timeout_seconds, 0};
  ldap_set_option(ld, LDAP_OPT_NETWORK_TIMEOUT, &tv);
  ldap_set_option(ld, LDAP_OPT_TIMEOUT, &tv);

  int never = LDAP_OPT_X_TLS_NEVER;
  ldap_set_option(ld, LDAP_OPT_X_TLS_REQUIRE_CERT, &never);
  int newctx = 0;
  ldap_set_option(ld, LDAP_OPT_X_TLS_NEWCTX, &newctx);

  double attempt_start = monotonic_seconds();
  if (start_tls && !use_ssl) {
    rc = run_with_deadline(ld, p->timeout_seconds, call_ldap_start_tls);
  } else {
    rc = run_with_deadline(ld, p->timeout_seconds, call_ldap_connect);
  }
  if (rc != LDAP_SUCCESS) {
    /* See classify_tls_failure: libldap reports our own connect-phase
     * timeout as LDAP_SERVER_DOWN, not LDAP_TIMEOUT, so elapsed time is
     * what actually catches it. */
    double elapsed = monotonic_seconds() - attempt_start;
    LSErrorKind kind = LS_CONNECT_FAILED;
    if (rc == LDAP_TIMEOUT || elapsed >= (double)p->timeout_seconds - 0.5) {
      kind = LS_CONNECT_TIMED_OUT;
    }
    int out_rc = ls_fail(err, kind, host, port, ldap_err2string(rc));
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
  const unsigned char *der_cursor = (const unsigned char *)der.bv_val;
  X509 *cert = d2i_X509(NULL, &der_cursor, (long)der.bv_len);
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

int ls_probe_certificate(const char *host, uint16_t port, bool use_ssl,
                         bool start_tls, LSCertInfo *out, LSError *err) {
  return probe_certificate(&g_policy, host, port, use_ssl, start_tls, out, err);
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
