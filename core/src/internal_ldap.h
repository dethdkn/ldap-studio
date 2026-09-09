/*
 * internal_ldap.h — shared between ldap.c and schema.c.
 */
#ifndef LDAPSTUDIO_INTERNAL_LDAP_H
#define LDAPSTUDIO_INTERNAL_LDAP_H

#include <ldap.h>
#include <sys/time.h>

#include "internal.h"

#define LS_CONNECT_TIMEOUT_SECS 15

/*
 * Connects and binds, handing back a ready LDAP* (caller unbinds with
 * ldap_unbind_ext_s). Empty/NULL bind_dn → anonymous. The whole attempt
 * is capped at LS_CONNECT_TIMEOUT_SECS. On failure fills `err` with the
 * right LS_CONNECT_* / LS_BIND_FAILED kind and returns non-zero.
 */
int ls_connect_and_bind(const char *host, uint16_t port, bool use_ssl,
                        const char *bind_dn, const char *password, LDAP **out,
                        LSError *err);

/* Maps an ldap_* result code to reason text via ldap_err2string and fills
 * `err` with the given kind; returns that kind. */
int ls_ldap_fail(LSError *err, LSErrorKind kind, int rc);

#endif /* LDAPSTUDIO_INTERNAL_LDAP_H */
