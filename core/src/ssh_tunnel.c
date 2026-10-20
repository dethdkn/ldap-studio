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
#include <time.h>
#include <unistd.h>

#include "internal.h"

struct LSSSHTunnel {
  int ssh_socket;
  int listen_socket;
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
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
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

/* One local connection being forwarded over its own SSH channel. Both
 * directions are buffered, and the client socket is non-blocking, so one
 * client that stops reading (a pooled LDAP connection holding responses
 * nobody has read yet) only stalls its own channel — the SSH window
 * throttles it — never the thread that serves every other client. */
typedef struct {
  int socket; /* -1 once the client has gone */
  LIBSSH2_CHANNEL *channel;
  /* Client → server: read from the socket, not yet taken by the channel.
   * The socket isn't read again until all of it is sent. */
  unsigned char up[32768];
  size_t up_len;
  size_t up_sent;
  /* Server → client: read from the channel, not yet written to the
   * socket. The channel isn't read again until all of it is written. */
  unsigned char down[32768];
  size_t down_len;
  size_t down_sent;
  /* The socket is closed; the channel is being closed without waiting
   * for the server, and is freed once that's done. */
  bool closing;
} TunnelClient;

#define LS_SSH_MAX_CLIENTS 32

/* A tunnel nobody has used for this long closes itself. */
#define LS_SSH_RETIRE_IDLE_SECS 30

/* True when the session itself is gone (as opposed to one channel
 * closing), which ends the whole tunnel. */
static bool session_failed(LIBSSH2_SESSION *session) {
  int code = libssh2_session_last_errno(session);
  return code == LIBSSH2_ERROR_SOCKET_SEND ||
         code == LIBSSH2_ERROR_SOCKET_RECV ||
         code == LIBSSH2_ERROR_SOCKET_DISCONNECT ||
         code == LIBSSH2_ERROR_SOCKET_TIMEOUT || code == LIBSSH2_ERROR_TIMEOUT;
}

/* Closes the client's socket now and starts closing its channel without
 * waiting on the server; finish_close completes it on later rounds. */
static void drop_client(TunnelClient *c) {
  shutdown(c->socket, SHUT_RDWR);
  close(c->socket);
  c->socket = -1;
  c->closing = true;
  c->up_len = c->up_sent = c->down_len = c->down_sent = 0;
}

/* Frees a closing client's channel once libssh2 can do so without
 * blocking. Returns true when the slot is free again. */
static bool finish_close(TunnelClient *c) {
  if (libssh2_channel_free(c->channel) == LIBSSH2_ERROR_EAGAIN) return false;
  c->channel = NULL;
  c->closing = false;
  return true;
}

/* Writes as much of the server → client buffer as the socket takes now.
 * Returns false if the client has gone. */
static bool flush_down(TunnelClient *c) {
  while (c->down_sent < c->down_len) {
    ssize_t w =
        write(c->socket, c->down + c->down_sent, c->down_len - c->down_sent);
    if (w < 0 && (errno == EAGAIN || errno == EINTR)) return true;
    if (w <= 0) return false;
    c->down_sent += (size_t)w;
  }
  c->down_len = c->down_sent = 0;
  return true;
}

/* Moves whatever can move right now, both ways, without blocking. Returns
 * false when this client is done (either side closed, or its channel
 * failed). */
static bool pump_client(TunnelClient *c, bool readable, bool *moved) {
  if (c->up_len == 0 && readable) {
    ssize_t n = read(c->socket, c->up, sizeof c->up);
    if (n == 0) return false;
    if (n < 0 && errno != EAGAIN && errno != EINTR) return false;
    if (n > 0) {
      c->up_len = (size_t)n;
      c->up_sent = 0;
      *moved = true;
    }
  }
  while (c->up_sent < c->up_len) {
    ssize_t w = libssh2_channel_write(c->channel, (char *)c->up + c->up_sent,
                                      c->up_len - c->up_sent);
    if (w == LIBSSH2_ERROR_EAGAIN) break;
    if (w < 0) return false;
    c->up_sent += (size_t)w;
  }
  if (c->up_sent == c->up_len) c->up_len = c->up_sent = 0;

  if (!flush_down(c)) return false;
  while (c->down_len == 0) {
    ssize_t n =
        libssh2_channel_read(c->channel, (char *)c->down, sizeof c->down);
    if (n == LIBSSH2_ERROR_EAGAIN || n == 0) break;
    if (n < 0) return false;
    c->down_len = (size_t)n;
    c->down_sent = 0;
    *moved = true;
    if (!flush_down(c)) return false;
  }
  return !(c->down_len == 0 && libssh2_channel_eof(c->channel));
}

/* Accepted client sockets are non-blocking, and never raise SIGPIPE when
 * written after the client hung up (the core also ignores SIGPIPE, but
 * that's process-wide state this shouldn't have to rely on). */
static void prepare_client_socket(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  fcntl(fd, F_SETFL, (int)((unsigned)flags | (unsigned)O_NONBLOCK));
  int on = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
}

/* Runs for the whole lifetime of the tunnel on one thread (a libssh2
 * session isn't safe to use from several), forwarding every accepted
 * local connection over its own channel of the one SSH session. Several
 * connections are served at once: the app keeps LDAP connections open in
 * a pool, so one waiting on another to close would never get through. */
static void *forward_loop(void *arg) {
  LSSSHTunnel *t = arg;
  TunnelClient *clients = ls_xcalloc(LS_SSH_MAX_CLIENTS, sizeof(TunnelClient));
  for (size_t i = 0; i < LS_SSH_MAX_CLIENTS; ++i) clients[i].socket = -1;
  libssh2_session_set_blocking(t->session, 0);
  /* libssh2 reads ahead from the SSH socket, so data for a channel can be
   * sitting in its buffers with nothing left on the socket to wake poll.
   * After a round that moved data, look again straight away. */
  bool moved = false;
  time_t idle_since = 0;

  while (!t->stopping && !t->broken) {
    /* libssh2 only reads the SSH socket while a channel call is being
     * made: a client's channel read (when its down buffer has room) or a
     * closing channel's free. With none of those this round, a readable
     * SSH socket (a server keepalive, say) would wake poll at once,
     * forever — so it's only polled when something will read it. */
    size_t live = 0;
    size_t readers = 0;
    size_t closers = 0;
    for (size_t i = 0; i < LS_SSH_MAX_CLIENTS; ++i) {
      if (clients[i].closing) closers++;
      if (clients[i].socket < 0) continue;
      live++;
      if (clients[i].down_len == 0) readers++;
    }
    bool watch_ssh = readers > 0 || closers > 0;

    /* With nothing using it, the session can't answer keepalives and the
     * server will eventually drop it; retire the tunnel after a while so
     * the next connection opens a fresh one. (If the session dies sooner,
     * the next connection's channel open fails, which marks the tunnel
     * broken, and connect.c retries on a fresh one.) */
    if (live == 0 && closers == 0) {
      time_t now = time(NULL);
      if (idle_since == 0) idle_since = now;
      if (now - idle_since > LS_SSH_RETIRE_IDLE_SECS) {
        t->broken = true;
        break;
      }
    } else {
      idle_since = 0;
    }

    struct pollfd pfds[LS_SSH_MAX_CLIENTS + 2];
    size_t index_of[LS_SSH_MAX_CLIENTS];
    nfds_t n = 0;
    pfds[n++] = (struct pollfd){.fd = t->listen_socket, .events = POLLIN};
    if (watch_ssh)
      pfds[n++] = (struct pollfd){.fd = t->ssh_socket, .events = POLLIN};
    nfds_t first_client = n;
    for (size_t i = 0; i < LS_SSH_MAX_CLIENTS; ++i) {
      if (clients[i].socket < 0) continue;
      index_of[n - first_client] = i;
      short events = 0;
      if (clients[i].up_len == 0) events |= POLLIN;
      if (clients[i].down_len > clients[i].down_sent) events |= POLLOUT;
      pfds[n++] = (struct pollfd){.fd = clients[i].socket, .events = events};
    }
    poll(pfds, n, moved ? 0 : 100);
    moved = false;
    if (t->stopping) break;

    if (((unsigned)pfds[0].revents & (unsigned)POLLIN) != 0) {
      int client = accept(t->listen_socket, NULL, NULL);
      if (client >= 0) {
        size_t slot = LS_SSH_MAX_CLIENTS;
        for (size_t i = 0; i < LS_SSH_MAX_CLIENTS; ++i)
          if (clients[i].socket < 0 && !clients[i].closing) {
            slot = i;
            break;
          }
        /* Opened in blocking mode: non-blocking, opening a channel returns
         * EAGAIN almost every time. Other channels' data that arrives
         * meanwhile is buffered by libssh2 and picked up below. */
        libssh2_session_set_blocking(t->session, 1);
        LIBSSH2_CHANNEL *channel = slot < LS_SSH_MAX_CLIENTS
                                       ? libssh2_channel_direct_tcpip_ex(
                                             t->session, t->target_host,
                                             t->target_port, "127.0.0.1", 0)
                                       : NULL;
        libssh2_session_set_blocking(t->session, 0);
        if (channel) {
          prepare_client_socket(client);
          clients[slot] = (TunnelClient){.socket = client, .channel = channel};
        } else {
          /* Marked broken before the client sees its connection close, so
           * a caller retrying on a fresh tunnel finds this one dead. */
          if (slot < LS_SSH_MAX_CLIENTS && session_failed(t->session))
            t->broken = true;
          close(client);
        }
      }
    }

    /* Channel data can be waiting even when no socket is ready (it
     * arrived while another channel was being served), so every client
     * is pumped every time round. */
    for (size_t i = 0; i < LS_SSH_MAX_CLIENTS; ++i) {
      TunnelClient *c = &clients[i];
      if (c->closing) {
        finish_close(c);
        continue;
      }
      if (c->socket < 0) continue;
      bool readable = false;
      for (nfds_t k = first_client; k < n; ++k)
        if (index_of[k - first_client] == i &&
            ((unsigned)pfds[k].revents & (unsigned)(POLLIN | POLLHUP)) != 0)
          readable = true;
      if (!pump_client(c, readable, &moved)) {
        if (session_failed(t->session)) t->broken = true;
        drop_client(c);
        finish_close(c);
      }
    }
  }

  /* Stop listening as soon as the loop ends, for whatever reason, so a
   * connect that picked this tunnel just as it retired or broke is refused
   * at once (which connect.c retries on a fresh tunnel) instead of waiting
   * out its timeout. Only this thread ever closes the listening socket —
   * ls_ssh_tunnel_stop joins it first — so its descriptor number can't be
   * closed twice or reused underneath anyone. */
  close(t->listen_socket);
  t->listen_socket = -1;

  /* The session is about to be torn down, which frees whatever channels
   * are left; just let the clients go. */
  for (size_t i = 0; i < LS_SSH_MAX_CLIENTS; ++i)
    if (clients[i].socket >= 0) {
      shutdown(clients[i].socket, SHUT_RDWR);
      close(clients[i].socket);
    }
  free(clients);
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
  t->ssh_socket = t->listen_socket = -1;
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
      listen(t->listen_socket, LS_SSH_MAX_CLIENTS)) {
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
  /* The loop notices `stopping` within one 100ms poll and closes the
   * listening socket itself; it's only closed here if the loop never
   * started. */
  if (t->thread_started) {
    pthread_join(t->thread, NULL);
  } else if (t->listen_socket >= 0) {
    close(t->listen_socket);
  }
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
