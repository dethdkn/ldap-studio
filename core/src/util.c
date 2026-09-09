#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

/* ── allocation ─────────────────────────────────────────────────────── */

void *ls_xmalloc(size_t n) {
  void *p = malloc(n ? n : 1);
  if (!p) abort();
  return p;
}

void *ls_xcalloc(size_t count, size_t size) {
  void *p = calloc(count ? count : 1, size ? size : 1);
  if (!p) abort();
  return p;
}

void *ls_xrealloc(void *p, size_t n) {
  void *q = realloc(p, n ? n : 1);
  if (!q) abort();
  return q;
}

char *ls_xstrdup(const char *s) {
  if (!s) return NULL;
  size_t n = strlen(s) + 1;
  char *out = ls_xmalloc(n);
  memcpy(out, s, n);
  return out;
}

char *ls_strdup_n(const char *s, size_t n) {
  char *out = ls_xmalloc(n + 1);
  if (n) memcpy(out, s, n);
  out[n] = '\0';
  return out;
}

char *ls_aprintf(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int need = vsnprintf(NULL, 0, fmt, ap);
  va_end(ap);
  if (need < 0) return ls_xstrdup("");

  char *out = ls_xmalloc((size_t)need + 1);
  va_start(ap, fmt);
  vsnprintf(out, (size_t)need + 1, fmt, ap);
  va_end(ap);
  return out;
}

/* ── errors ────────────────────────────────────────────────────────── */

int ls_fail(LSError *err, LSErrorKind kind, const char *host, uint16_t port,
            const char *reason) {
  if (err) {
    err->kind = kind;
    err->host = ls_xstrdup(host);
    err->port = port;
    err->reason = ls_xstrdup(reason);
  }
  return (int)kind;
}

void ls_error_dispose(LSError *err) {
  if (!err) return;
  free(err->host);
  free(err->reason);
  err->host = NULL;
  err->reason = NULL;
}

/* ── base64 ────────────────────────────────────────────────────────── */

static const char B64_ALPHABET[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

char *ls_b64_encode(const uint8_t *data, size_t len) {
  size_t groups = (len + 2) / 3;
  size_t out_len = groups * 4;
  char *out = ls_xmalloc(out_len + 1);

  for (size_t g = 0; g < groups; ++g) {
    /* invariant (out was sized groups*4 + 1): this group fits */
    assert((g * 4) + 4 <= out_len + 1);
    size_t i = g * 3;
    uint32_t n = (uint32_t)data[i] << 16;
    if (i + 1 < len) n |= (uint32_t)data[i + 1] << 8;
    if (i + 2 < len) n |= (uint32_t)data[i + 2];

    out[(g * 4) + 0] = B64_ALPHABET[(n >> 18) & 0x3F];
    out[(g * 4) + 1] = B64_ALPHABET[(n >> 12) & 0x3F];
    out[(g * 4) + 2] = (i + 1 < len) ? B64_ALPHABET[(n >> 6) & 0x3F] : '=';
    out[(g * 4) + 3] = (i + 2 < len) ? B64_ALPHABET[n & 0x3F] : '=';
  }
  out[out_len] = '\0';
  return out;
}

static int b64_value(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

uint8_t *ls_b64_decode(const char *text, size_t *out_len) {
  if (out_len) *out_len = 0;
  if (!text) return ls_xmalloc(1);

  size_t cap = ((strlen(text) / 4) * 3) + 3;
  uint8_t *out = ls_xmalloc(cap);
  size_t o = 0;

  uint32_t acc = 0;
  int bits = 0;
  for (const char *p = text; *p; ++p) {
    if (*p == '=' || *p == '\n' || *p == '\r' || *p == ' ' || *p == '\t')
      continue;
    int v = b64_value(*p);
    if (v < 0) { /* malformed → behave like unwrap_or_default() */
      o = 0;
      break;
    }
    acc = (acc << 6) | (uint32_t)v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[o++] = (uint8_t)((acc >> bits) & 0xFF);
    }
  }

  if (out_len) *out_len = o;
  return out;
}

/* ── utf-8 validation ──────────────────────────────────────────────── */

bool ls_utf8_valid(const uint8_t *data, size_t len) {
  size_t i = 0;
  while (i < len) {
    uint8_t b = data[i];
    size_t extra;
    uint32_t cp;
    uint32_t min;

    if (b < 0x80) {
      i++;
      continue;
    }
    if ((b & 0xE0) == 0xC0) {
      extra = 1;
      cp = b & 0x1F;
      min = 0x80;
    } else if ((b & 0xF0) == 0xE0) {
      extra = 2;
      cp = b & 0x0F;
      min = 0x800;
    } else if ((b & 0xF8) == 0xF0) {
      extra = 3;
      cp = b & 0x07;
      min = 0x10000;
    } else {
      return false;
    }

    if (i + extra >= len) return false;
    for (size_t k = 1; k <= extra; ++k) {
      uint8_t c = data[i + k];
      if ((c & 0xC0) != 0x80) return false;
      cp = (cp << 6) | (c & 0x3F);
    }
    if (cp < min) return false;                     /* overlong */
    if (cp > 0x10FFFF) return false;                /* out of range */
    if (cp >= 0xD800 && cp <= 0xDFFF) return false; /* surrogate */
    i += extra + 1;
  }
  return true;
}

/* ── string list ──────────────────────────────────────────────────── */

void ls_strlist_init(LSStrList *l) {
  l->items = NULL;
  l->count = 0;
  l->cap = 0;
}

void ls_strlist_push(LSStrList *l, char *owned) {
  if (l->count == l->cap) {
    l->cap = l->cap ? l->cap * 2 : 4;
    l->items = ls_xrealloc(l->items, l->cap * sizeof(*l->items));
  }
  l->items[l->count++] = owned;
}

void ls_strlist_free_items(LSStrList *l) {
  for (size_t i = 0; i < l->count; ++i) free(l->items[i]);
  free(l->items);
  ls_strlist_init(l);
}
