#ifndef LDAPSTUDIO_SSH_TUNNEL_H
#define LDAPSTUDIO_SSH_TUNNEL_H

#include "ldapstudio.h"

typedef struct LSSSHTunnel LSSSHTunnel;
int ls_ssh_tunnel_start(const char *ssh_host, uint16_t ssh_port,
                        const char *username, LSSSHAuthMethod auth_method,
                        const char *password, const char *private_key_path,
                        const char *pinned_host_key_sha256,
                        const char *target_host, uint16_t target_port,
                        unsigned timeout_seconds, LSSSHTunnel **out,
                        uint16_t *local_port, LSError *err);
void ls_ssh_tunnel_stop(LSSSHTunnel *tunnel);

/* True while the tunnel's forwarding loop is still running and hasn't hit
 * an error. Checked before reusing a cached tunnel for a new operation. */
bool ls_ssh_tunnel_is_alive(const LSSSHTunnel *tunnel);

/* The loopback port the tunnel is listening on — the same value handed
 * back via `local_port` at start, kept for cache reuse. */
uint16_t ls_ssh_tunnel_local_port(const LSSSHTunnel *tunnel);

#endif
