/*
 * internal.h — helpers shared between the C core's translation units.
 * Not part of the public ABI (that's ldapstudio.h).
 */
#ifndef LDAPSTUDIO_INTERNAL_H
#define LDAPSTUDIO_INTERNAL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ldapstudio.h"

/* ── allocation (abort on OOM — the app has nothing useful to do with it) ── */
void *ls_xmalloc(size_t n);
void *ls_xcalloc(size_t count, size_t size);
void *ls_xrealloc(void *p, size_t n);
char *ls_xstrdup(const char *s); /* NULL in → NULL out */
char *ls_strdup_n(const char *s, size_t n);

/* printf into a freshly malloc'd string. */
char *ls_aprintf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

/* ── errors ──────────────────────────────────────────────────────────────
 * Fills *err (copying the strings) and returns `kind`, so call sites can do
 *   return ls_fail(err, LS_BIND_FAILED, NULL, 0, msg);
 * `host`/`reason` may be NULL.
 */
int ls_fail(LSError *err, LSErrorKind kind, const char *host, uint16_t port,
            const char *reason);

/* ── base64 ──────────────────────────────────────────────────────────────
 * Standard alphabet, with padding. `ls_b64_encode` returns a NUL-terminated
 * string. `ls_b64_decode` returns a malloc'd buffer and sets *out_len; on
 * malformed input it returns an empty (zero-length) buffer rather than
 * failing, matching the old Rust `unwrap_or_default()` behavior.
 */
char *ls_b64_encode(const uint8_t *data, size_t len);
uint8_t *ls_b64_decode(const char *text, size_t *out_len);

/* ── utf-8 ───────────────────────────────────────────────────────────────
 * True when `data` is well-formed UTF-8. Used to decide whether an LDAP
 * attribute value is "binary" (the old code leaned on ldap3 sorting values
 * into bin_attrs; libldap hands everything back as bytes, so we classify).
 */
bool ls_utf8_valid(const uint8_t *data, size_t len);

/* ── growable list of owned C strings ───────────────────────────────────── */
typedef struct {
  char **items;
  size_t count;
  size_t cap;
} LSStrList;

void ls_strlist_init(LSStrList *l);
void ls_strlist_push(LSStrList *l, char *owned); /* takes ownership */
void ls_strlist_free_items(LSStrList *l); /* frees strings + backing array */

#endif /* LDAPSTUDIO_INTERNAL_H */
