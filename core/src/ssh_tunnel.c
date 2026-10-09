#include "ssh_tunnel.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <libssh2.h>
#include <netdb.h>
#include <openssl/evp.h>
#include <poll.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "internal.h"

struct LSSSHTunnel {
  int ssh_socket;
  int listen_socket;
  volatile int client_socket;
  LIBSSH2_SESSION *session;
  pthread_t thread;
  bool thread_started;
  volatile bool stopping;
  /* Set by forward_loop when it gives up because of an I/O error (as
   * opposed to being asked to stop) — the cache in ldap.c checks this
   * before handing the tunnel to another operation. */
  volatile bool broken;
  char *target_host;
  uint16_t target_port;
  uint16_t local_port;
};

/* Runs one non-blocking connect() to `addr` on `fd` and waits up to
 * `timeout_seconds` for it to finish. Returns 0 on success; on failure -1,
 * with the reason written to `why`. */
static int finish_connect(int fd, const struct addrinfo *addr,
                          unsigned timeout_seconds, char *why, size_t why_len) {
  if (connect(fd, addr->ai_addr, addr->ai_addrlen) == 0) return 0;
  if (errno != EINPROGRESS) {
    snprintf(why, why_len, "%s", strerror(errno));
    return -1;
  }

  struct pollfd pfd = {.fd = fd, .events = POLLOUT};
  int ready = poll(&pfd, 1, (int)timeout_seconds * 1000);
  if (ready == 0) {
    snprintf(why, why_len, "no response within %u seconds", timeout_seconds);
    return -1;
  }
  if (ready < 0) {
    snprintf(why, why_len, "%s", strerror(errno));
    return -1;
  }

  /* Any event means the attempt finished — success shows as writable, but a
   * refusal wakes poll with an error flag instead — so SO_ERROR is the
   * arbiter, not which flag fired. */
  int socket_error = 0;
  socklen_t error_length = sizeof socket_error;
  getsockopt(fd, SOL_SOCKET, SO_ERROR, &socket_error, &error_length);
  if (socket_error != 0) {
    snprintf(why, why_len, "%s", strerror(socket_error));
    return -1;
  }
  return 0;
}

/* Opens a TCP connection to host:port within `timeout_seconds` (per address
 * tried). On failure returns -1 and writes a short human-readable reason
 * into `why`. */
static int tcp_connect(const char *host, uint16_t port,
                       unsigned timeout_seconds, char *why, size_t why_len) {
  char service[8];
  snprintf(service, sizeof service, "%u", (unsigned)port);
  struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM};
  struct addrinfo *list = NULL;
  int gai = getaddrinfo(host, service, &hints, &list);
  if (gai != 0) {
    snprintf(why, why_len, "could not resolve %s (%s)", host,
             gai_strerror(gai));
    return -1;
  }
  snprintf(why, why_len, "no address for %s accepted a connection", host);

  int connected_fd = -1;
  for (struct addrinfo *a = list; a && connected_fd < 0; a = a->ai_next) {
    int fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
    if (fd < 0) continue;
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, (int)((unsigned)flags | (unsigned)O_NONBLOCK));
    if (finish_connect(fd, a, timeout_seconds, why, why_len) != 0) {
      close(fd);
      continue;
    }
    fcntl(fd, F_SETFL, flags);
    struct timeval timeout = {(time_t)timeout_seconds, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
    connected_fd = fd;
  }
  freeaddrinfo(list);
  return connected_fd;
}

static void sha256_hex(const unsigned char *bytes, size_t length,
                       char out[65]) {
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int n = 0;
  EVP_Digest(bytes, length, digest, &n, EVP_sha256(), NULL);
  static const char hex[] = "0123456789abcdef";
  for (size_t i = 0; i < n; i++) {
    unsigned byte = digest[i];
    out[i * 2] = hex[byte >> 4U];
    out[(i * 2) + 1] = hex[byte & 15U];
  }
  out[(size_t)n * 2] = 0;
}

/* Forwards one accepted local connection over its own SSH channel until
 * either side closes. Returns false if it gave up because of an I/O
 * error (as opposed to a clean EOF or a requested stop) — that marks the
 * whole tunnel broken so the cache won't hand it out again. */
static bool serve_client(LSSSHTunnel *t, int client_socket) {
  /* The forwarding loop below runs the session non-blocking, and a tunnel
   * serves many connections one after another — so by the second one the
   * session is still non-blocking from the last. Opening a channel in that
   * state returns NULL (EAGAIN) almost every time, which used to fail
   * every other operation on a cached tunnel and mark it broken. Open (and
   * later close) the channel in blocking mode; only the shuttling loop is
   * non-blocking. */
  libssh2_session_set_blocking(t->session, 1);
  LIBSSH2_CHANNEL *channel = libssh2_channel_direct_tcpip_ex(
      t->session, t->target_host, t->target_port, "127.0.0.1", 0);
  if (!channel) return false;
  libssh2_session_set_blocking(t->session, 0);
  unsigned char buffer[32768];
  bool ok = true;
  while (!t->stopping) {
    struct pollfd pfds[2] = {
        {.fd = client_socket, .events = POLLIN},
        {.fd = t->ssh_socket, .events = POLLIN},
    };
    poll(pfds, 2, 200);
    if (((unsigned)pfds[0].revents & (unsigned)POLLIN) != 0) {
      ssize_t n = read(client_socket, buffer, sizeof buffer);
      if (n <= 0) break;
      size_t sent = 0;
      while (sent < (size_t)n && !t->stopping) {
        ssize_t w = libssh2_channel_write(channel, (char *)buffer + sent,
                                          (size_t)n - sent);
        if (w > 0) {
          sent += (size_t)w;
        } else if (w != LIBSSH2_ERROR_EAGAIN) {
          ok = false;
          goto done;
        }
      }
    }
    for (;;) {
      ssize_t n = libssh2_channel_read(channel, (char *)buffer, sizeof buffer);
      if (n == LIBSSH2_ERROR_EAGAIN || n == 0) break;
      if (n < 0) {
        ok = false;
        goto done;
      }
      size_t sent = 0;
      while (sent < (size_t)n) {
        ssize_t w = write(client_socket, buffer + sent, (size_t)n - sent);
        if (w <= 0) {
          ok = false;
          goto done;
        }
        sent += (size_t)w;
      }
    }
    if (libssh2_channel_eof(channel)) break;
  }
done:
  libssh2_session_set_blocking(t->session, 1);
  libssh2_channel_free(channel);
  return ok;
}

/* Runs for the whole lifetime of the tunnel, accepting one local
 * connection at a time and forwarding it — the tunnel (and its SSH
 * session) survives across many of these so the app doesn't pay for a
 * fresh SSH handshake on every LDAP operation. */
static void *forward_loop(void *arg) {
  LSSSHTunnel *t = arg;
  while (!t->stopping) {
    int client = accept(t->listen_socket, NULL, NULL);
    if (client < 0) {
      if (t->stopping) break;
      continue;
    }
    t->client_socket = client;
    bool ok = serve_client(t, client);
    close(client);
    t->client_socket = -1;
    if (!ok) {
      t->broken = true;
      break;
    }
  }
  return NULL;
}

int ls_ssh_tunnel_start(const char *ssh_host, uint16_t ssh_port,
                        const char *username, LSSSHAuthMethod auth_method,
                        const char *password, const char *private_key_path,
                        const char *pinned_host_key_sha256,
                        const char *target_host, uint16_t target_port,
                        unsigned timeout_seconds, LSSSHTunnel **out,
                        uint16_t *local_port, LSError *err) {
  *out = NULL;
  libssh2_init(0);
  LSSSHTunnel *t = ls_xcalloc(1, sizeof *t);
  t->ssh_socket = t->listen_socket = t->client_socket = -1;
  t->target_host = ls_xstrdup(target_host);
  t->target_port = target_port;
  char why[256] = "unknown error";
  t->ssh_socket =
      tcp_connect(ssh_host, ssh_port, timeout_seconds, why, sizeof why);
  if (t->ssh_socket < 0) {
    char *reason =
        ls_aprintf("Could not open a connection to the SSH server: %s", why);
    int rc = ls_fail(err, LS_CONNECT_FAILED, ssh_host, ssh_port, reason);
    free(reason);
    ls_ssh_tunnel_stop(t);
    return rc;
  }
  t->session = libssh2_session_init();
  if (t->session) {
    /* SO_RCVTIMEO alone isn't enough: libssh2 treats the resulting EAGAIN as
     * "would block" and waits again with no limit, so a server that accepts
     * the TCP connection and then stalls would hang the handshake, auth, or
     * channel open forever (holding the tunnel cache lock with it). */
    libssh2_session_set_timeout(t->session, (long)timeout_seconds * 1000);
  }
  if (!t->session) {
    snprintf(why, sizeof why, "could not create an SSH session");
    goto connect_fail;
  }
  int handshake_rc = libssh2_session_handshake(t->session, t->ssh_socket);
  if (handshake_rc != 0) {
    char *detail = NULL;
    libssh2_session_last_error(t->session, &detail, NULL, 0);
    snprintf(why, sizeof why, "SSH handshake failed: %s (code %d)",
             detail ? detail : "unknown", handshake_rc);
    goto connect_fail;
  }

  size_t key_len = 0;
  int key_type = 0;
  const char *key = libssh2_session_hostkey(t->session, &key_len, &key_type);
  (void)key_type;
  char fingerprint[65] = {0};
  if (!key) {
    snprintf(why, sizeof why, "the SSH server did not provide a host key");
    goto connect_fail;
  }
  sha256_hex((const unsigned char *)key, key_len, fingerprint);
  if (!pinned_host_key_sha256 || !*pinned_host_key_sha256 ||
      strcasecmp(fingerprint, pinned_host_key_sha256) != 0) {
    int rc = ls_fail(err, LS_SSH_HOST_KEY_UNTRUSTED, ssh_host, ssh_port,
                     fingerprint);
    ls_ssh_tunnel_stop(t);
    return rc;
  }

  int auth_rc =
      auth_method == LS_SSH_PRIVATE_KEY
          ? libssh2_userauth_publickey_fromfile(t->session, username, NULL,
                                                private_key_path, password)
          : libssh2_userauth_password(t->session, username,
                                      password ? password : "");
  if (auth_rc) {
    char *detail = NULL;
    libssh2_session_last_error(t->session, &detail, NULL, 0);
    /* What the server will actually accept — usually the whole story when
     * a password is offered to a key-only server, or the reverse. */
    const char *offered =
        libssh2_userauth_list(t->session, username, (unsigned)strlen(username));
    char *reason = ls_aprintf(
        "SSH authentication failed (%s). The server accepts: %s",
        detail ? detail : "unknown error", offered ? offered : "unknown");
    int rc = ls_fail(err, LS_CONNECT_FAILED, ssh_host, ssh_port, reason);
    free(reason);
    ls_ssh_tunnel_stop(t);
    return rc;
  }

  t->listen_socket = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in address = {.sin_family = AF_INET};
  inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
  if (t->listen_socket < 0 ||
      bind(t->listen_socket, (struct sockaddr *)&address, sizeof address) ||
      listen(t->listen_socket, 1)) {
    snprintf(why, sizeof why, "could not open a local port for the tunnel: %s",
             strerror(errno));
    goto connect_fail;
  }
  socklen_t address_len = sizeof address;
  getsockname(t->listen_socket, (struct sockaddr *)&address, &address_len);
  *local_port = ntohs(address.sin_port);
  t->local_port = *local_port;
  if (pthread_create(&t->thread, NULL, forward_loop, t)) {
    snprintf(why, sizeof why, "could not start the tunnel thread");
    goto connect_fail;
  }
  t->thread_started = true;
  *out = t;
  return LS_OK;

connect_fail: {
  int rc = ls_fail(err, LS_CONNECT_FAILED, ssh_host, ssh_port, why);
  ls_ssh_tunnel_stop(t);
  return rc;
}
}

void ls_ssh_tunnel_stop(LSSSHTunnel *t) {
  if (!t) return;
  t->stopping = true;
  if (t->listen_socket >= 0) {
    shutdown(t->listen_socket, SHUT_RDWR);
    close(t->listen_socket);
  }
  if (t->client_socket >= 0) {
    shutdown(t->client_socket, SHUT_RDWR);
    close(t->client_socket);
  }
  if (t->thread_started) pthread_join(t->thread, NULL);
  if (t->session) {
    libssh2_session_set_blocking(t->session, 1);
    libssh2_session_disconnect(t->session, "tunnel closed");
    libssh2_session_free(t->session);
  }
  if (t->ssh_socket >= 0) close(t->ssh_socket);
  free(t->target_host);
  free(t);
}

bool ls_ssh_tunnel_is_alive(const LSSSHTunnel *t) {
  if (t == NULL) return false;
  if (t->stopping) return false;
  if (t->broken) return false;
  return true;
}

uint16_t ls_ssh_tunnel_local_port(const LSSSHTunnel *t) {
  return t ? t->local_port : 0;
}
