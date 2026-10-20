/*
 * ldap.c — searching and the modify family, built on the OpenLDAP client
 * library. Every call works on an LSConnection the app already opened
 * (see connect.c), so nothing here connects or binds.
 *
 * Searches are asynchronous underneath (ldap_search_ext + ldap_result
 * with a short poll) so a search can be cancelled from another thread and
 * read one page at a time.
 */
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "internal_ldap.h"

/* ── DN helpers ──────────────────────────────────────────────────── */

/* The leftmost RDN of `dn` — everything before the first comma that isn't
 * escaped with a backslash (RFC 4514), so "cn=Smith\, John,ou=People"
 * gives "cn=Smith\, John". Caller frees. */
static char *display_name(const char *dn) {
  for (const char *p = dn; *p; ++p) {
    if (*p == '\\' && p[1]) {
      ++p;
    } else if (*p == ',') {
      return ls_strdup_n(dn, (size_t)(p - dn));
    }
  }
  return ls_xstrdup(dn);
}

/* ── attribute extraction ────────────────────────────────────────── */

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

/* ── cancellation ────────────────────────────────────────────────── */

struct LSCancel {
  atomic_int fired;
};

LSCancel *ls_cancel_new(void) { return ls_xcalloc(1, sizeof(LSCancel)); }

void ls_cancel_trigger(LSCancel *cancel) {
  if (cancel) atomic_store(&cancel->fired, 1);
}

void ls_cancel_free(LSCancel *cancel) { free(cancel); }

static bool is_cancelled(LSCancel *cancel) {
  return cancel && atomic_load(&cancel->fired);
}

/* ── paged search ────────────────────────────────────────────────── */

/* Smallest page size worth retrying with when a server refuses a page as
 * too large (OpenLDAP's size.pr answers adminLimitExceeded; Active
 * Directory just clamps to its MaxPageSize). */
#define LS_MIN_PAGE_SIZE 50

/* How often a waiting search wakes up to check its LSCancel. */
#define LS_POLL_USECS 100000

/* Cancelling a search the server hasn't answered for this long retires
 * the connection instead of returning it to the pool. */
#define LS_QUIET_SECS 1.5

struct LSSearch {
  LSConnection *conn;
  char *base;
  int scope;
  char *filter;
  char **attrs;       /* NULL-terminated, owned */
  unsigned page_size; /* 0 = no paging control */
  unsigned idle_timeout;
  struct berval *cookie; /* server's position between pages; NULL at start */
  bool started;
  bool done;
  /* Cancelled between or during pages: the server may still hold state
   * for the previous page's cookie, which ls_search_free releases. */
  bool cancelled;
};

static double now_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + ((double)ts.tv_nsec / 1e9);
}

int ls_search_begin(LSConnection *conn, const char *base_dn, LSScope scope,
                    const char *filter, const char *const *attributes,
                    size_t attribute_count, bool include_operational,
                    unsigned page_size, unsigned idle_timeout_seconds,
                    LSSearch **out, LSError *err) {
  (void)err;
  LSSearch *s = ls_xcalloc(1, sizeof *s);
  s->conn = conn;
  s->base = ls_xstrdup(base_dn ? base_dn : "");
  s->scope = LDAP_SCOPE_SUBTREE;
  if (scope == LS_SCOPE_BASE)
    s->scope = LDAP_SCOPE_BASE;
  else if (scope == LS_SCOPE_ONELEVEL)
    s->scope = LDAP_SCOPE_ONELEVEL;
  s->filter = ls_xstrdup((filter && *filter) ? filter : "(objectClass=*)");

  size_t n = 0;
  s->attrs = ls_xcalloc(attribute_count + 3, sizeof(char *));
  if (attribute_count == 0) s->attrs[n++] = ls_xstrdup("*");
  for (size_t i = 0; i < attribute_count; ++i)
    s->attrs[n++] = ls_xstrdup(attributes[i]);
  if (include_operational) s->attrs[n++] = ls_xstrdup("+");

  s->page_size = page_size;
  s->idle_timeout = idle_timeout_seconds;
  *out = s;
  return LS_OK;
}

typedef struct {
  LSEntry *items;
  size_t count;
  size_t cap;
} EntryList;

static void entry_list_push(EntryList *l, LDAP *ld, LDAPMessage *msg) {
  char *dn = ldap_get_dn(ld, msg);
  if (!dn) return;
  if (l->count == l->cap) {
    l->cap = l->cap ? l->cap * 2 : 64;
    l->items = ls_xrealloc(l->items, l->cap * sizeof(LSEntry));
  }
  LSEntry *e = &l->items[l->count++];
  e->dn = ls_xstrdup(dn);
  e->name = display_name(dn);
  e->attributes = attributes_from(ld, msg, &e->attribute_count);
  ldap_memfree(dn);
}

/* Reads the final SearchResultDone of a page: the result code, and the
 * cookie for the next page, if the server sent one. */
static int finish_page(LSSearch *s, LDAP *ld, LDAPMessage *msg, int *code) {
  LDAPControl **ctrls = NULL;
  int rc = ldap_parse_result(ld, msg, code, NULL, NULL, NULL, &ctrls, 1);
  if (rc != LDAP_SUCCESS) return rc;

  if (s->cookie) {
    ber_bvfree(s->cookie);
    s->cookie = NULL;
  }
  LDAPControl *page = ldap_control_find(LDAP_CONTROL_PAGEDRESULTS, ctrls, NULL);
  if (page) {
    ber_int_t estimate = 0;
    struct berval cookie = {0, NULL};
    if (ldap_parse_pageresponse_control(ld, page, &estimate, &cookie) ==
            LDAP_SUCCESS &&
        cookie.bv_len > 0) {
      s->cookie = ber_bvdup(&cookie);
    }
    if (cookie.bv_val) ber_memfree(cookie.bv_val);
  }
  if (ctrls) ldap_controls_free(ctrls);
  return LDAP_SUCCESS;
}

/* Sends one page's request. */
static int send_page(LSSearch *s, LDAP *ld, int *msgid) {
  LDAPControl *page = NULL;
  LDAPControl *ctrls[] = {NULL, NULL};
  if (s->page_size > 0) {
    int rc = ldap_create_page_control(ld, (ber_int_t)s->page_size, s->cookie,
                                      0 /* not critical */, &page);
    if (rc != LDAP_SUCCESS) return rc;
    ctrls[0] = page;
  }
  int rc =
      ldap_search_ext(ld, s->base, s->scope, s->filter, s->attrs, 0,
                      page ? ctrls : NULL, NULL, NULL, LDAP_NO_LIMIT, msgid);
  if (page) ldap_control_free(page);
  return rc;
}

int ls_search_next_page(LSSearch *s, LSCancel *cancel, LSEntry **out,
                        size_t *out_count, bool *done, bool *truncated,
                        LSError *err) {
  *out = NULL;
  *out_count = 0;
  *done = false;
  *truncated = false;
  if (s->done) {
    *done = true;
    return LS_OK;
  }

  LDAP *ld = ls_connection_ld(s->conn);
  EntryList list = {0};

  for (;;) { /* once per attempt; again only after shrinking the page */
    int msgid = 0;
    int rc = send_page(s, ld, &msgid);
    if (rc != LDAP_SUCCESS) {
      s->done = true;
      return ls_connection_fail(s->conn, err, LS_SEARCH_FAILED, rc);
    }

    double last_heard = now_seconds();
    int code = LDAP_SUCCESS;
    for (;;) {
      if (is_cancelled(cancel)) {
        ldap_abandon_ext(ld, msgid, NULL, NULL);
        /* A server that's gone quiet may be unreachable (network dropped,
         * VPN down) rather than slow; don't hand that connection to the
         * next caller, who would wait on it forever. */
        if (now_seconds() - last_heard > LS_QUIET_SECS)
          ls_connection_mark_broken(s->conn);
        ls_entries_free(list.items, list.count);
        s->done = true;
        s->cancelled = true;
        return ls_fail(err, LS_CANCELLED, NULL, 0, "Cancelled");
      }
      struct timeval poll = {0, LS_POLL_USECS};
      LDAPMessage *msg = NULL;
      int type = ldap_result(ld, msgid, LDAP_MSG_ONE, &poll, &msg);
      if (type == 0) {
        if (s->idle_timeout > 0 &&
            now_seconds() - last_heard > (double)s->idle_timeout) {
          ldap_abandon_ext(ld, msgid, NULL, NULL);
          ls_connection_mark_broken(s->conn);
          ls_entries_free(list.items, list.count);
          s->done = true;
          return ls_fail(err, LS_SEARCH_FAILED, NULL, 0,
                         "The server stopped responding");
        }
        continue;
      }
      if (type < 0) {
        int lrc = LDAP_OTHER;
        ldap_get_option(ld, LDAP_OPT_RESULT_CODE, &lrc);
        ls_entries_free(list.items, list.count);
        s->done = true;
        return ls_connection_fail(s->conn, err, LS_SEARCH_FAILED, lrc);
      }
      last_heard = now_seconds();
      if (type == LDAP_RES_SEARCH_ENTRY) {
        entry_list_push(&list, ld, msg);
        ldap_msgfree(msg);
        continue;
      }
      if (type != LDAP_RES_SEARCH_RESULT) {
        /* Search references (AD's ForestDnsZones and the like) — the
         * entries they point at live on other naming contexts. */
        ldap_msgfree(msg);
        continue;
      }
      rc = finish_page(s, ld, msg, &code);
      if (rc != LDAP_SUCCESS) {
        ls_entries_free(list.items, list.count);
        s->done = true;
        return ls_connection_fail(s->conn, err, LS_SEARCH_FAILED, rc);
      }
      break;
    }

    if (code == LDAP_ADMINLIMIT_EXCEEDED && !s->started && list.count == 0 &&
        s->page_size > LS_MIN_PAGE_SIZE) {
      s->page_size /= 2;
      if (s->page_size < LS_MIN_PAGE_SIZE) s->page_size = LS_MIN_PAGE_SIZE;
      continue;
    }
    s->started = true;

    if (code == LDAP_SIZELIMIT_EXCEEDED) {
      /* Only reachable when the server ignored the paging control — keep
       * what arrived and say it's incomplete rather than failing. */
      *truncated = true;
      s->done = true;
    } else if (code != LDAP_SUCCESS) {
      ls_entries_free(list.items, list.count);
      s->done = true;
      return ls_connection_fail(s->conn, err, LS_SEARCH_FAILED, code);
    } else if (!s->cookie) {
      s->done = true;
    }
    break;
  }

  *out = list.items;
  *out_count = list.count;
  *done = s->done;
  return LS_OK;
}

void ls_search_free(LSSearch *s) {
  if (!s) return;
  if ((!s->done || s->cancelled) && s->cookie &&
      !ls_connection_is_broken(s->conn)) {
    /* RFC 2696: a page request with size 0 tells the server to drop the
     * paged search's state. Wait briefly for the reply so it can't be
     * mistaken for the next caller's; give up and retire the connection
     * if it doesn't come. */
    LDAP *ld = ls_connection_ld(s->conn);
    s->page_size = 0;
    LDAPControl *page = NULL;
    if (ldap_create_page_control(ld, 0, s->cookie, 0, &page) == LDAP_SUCCESS) {
      LDAPControl *ctrls[] = {page, NULL};
      int msgid = 0;
      if (ldap_search_ext(ld, s->base, s->scope, s->filter, s->attrs, 0, ctrls,
                          NULL, NULL, LDAP_NO_LIMIT, &msgid) == LDAP_SUCCESS) {
        struct timeval wait = {2, 0};
        LDAPMessage *msg = NULL;
        int type;
        while ((type = ldap_result(ld, msgid, LDAP_MSG_ONE, &wait, &msg)) > 0) {
          ldap_msgfree(msg);
          if (type == LDAP_RES_SEARCH_RESULT) break;
        }
        if (type <= 0) {
          ldap_abandon_ext(ld, msgid, NULL, NULL);
          ls_connection_mark_broken(s->conn);
        }
      }
      ldap_control_free(page);
    }
  }
  if (s->cookie) ber_bvfree(s->cookie);
  for (size_t i = 0; s->attrs[i]; ++i) free(s->attrs[i]);
  free(s->attrs);
  free(s->base);
  free(s->filter);
  free(s);
}

/* ── modify family ───────────────────────────────────────────────── */

/* Every modification here carries binary-safe values, so LDAP_MOD_BVALUES is
 * OR'd onto each operation code. Both are plain signed-int macros; combine
 * them as unsigned so the bitwise OR is well-defined. */
static int mod_op_bvalues(int op) {
  return (int)((unsigned)op | (unsigned)LDAP_MOD_BVALUES);
}

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

int ls_delete_entry(LSConnection *conn, const char *dn, LSError *err) {
  LDAP *ld = ls_connection_ld(conn);
  int lrc = ldap_delete_ext_s(ld, dn, NULL, NULL);
  if (lrc != LDAP_SUCCESS)
    return ls_connection_fail(conn, err, LS_MODIFY_FAILED, lrc);
  return LS_OK;
}

int ls_rename_entry(LSConnection *conn, const char *dn, const char *new_rdn,
                    bool delete_old_rdn, const char *new_superior,
                    LSError *err) {
  LDAP *ld = ls_connection_ld(conn);
  int lrc = ldap_rename_s(ld, dn, new_rdn ? new_rdn : "",
                          (new_superior && *new_superior) ? new_superior : NULL,
                          (int)delete_old_rdn, NULL, NULL);
  if (lrc != LDAP_SUCCESS)
    return ls_connection_fail(conn, err, LS_MODIFY_FAILED, lrc);
  return LS_OK;
}

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
  mod->mod_op = mod_op_bvalues(mod_op_flag(op->kind));
  mod->mod_type = (char *)op->attribute;
  mod->mod_vals.modv_bvals = *bptrs;
}

int ls_modify_entry(LSConnection *conn, const char *dn, const LSModOp *ops,
                    size_t op_count, LSError *err) {
  LDAPMod *mods = ls_xcalloc(op_count, sizeof(LDAPMod));
  LDAPMod **modp = ls_xcalloc(op_count + 1, sizeof(LDAPMod *));
  struct berval **all_bvals = ls_xcalloc(op_count, sizeof(struct berval *));
  struct berval ***all_bptrs = ls_xcalloc(op_count, sizeof(struct berval **));

  for (size_t i = 0; i < op_count; ++i) {
    build_mod(&ops[i], &mods[i], &all_bvals[i], &all_bptrs[i]);
    modp[i] = &mods[i];
  }
  modp[op_count] = NULL;

  LDAP *ld = ls_connection_ld(conn);
  int rc = LS_OK;
  int lrc = ldap_modify_ext_s(ld, dn, modp, NULL, NULL);
  if (lrc != LDAP_SUCCESS)
    rc = ls_connection_fail(conn, err, LS_MODIFY_FAILED, lrc);

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

int ls_add_entry(LSConnection *conn, const char *dn,
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

    mods[g].mod_op = mod_op_bvalues(LDAP_MOD_ADD);
    mods[g].mod_type = groups[g].name;
    mods[g].mod_vals.modv_bvals = groups[g].bptrs;
    modp[g] = &mods[g];
  }
  modp[ngroups] = NULL;

  LDAP *ld = ls_connection_ld(conn);
  int rc = LS_OK;
  int lrc = ldap_add_ext_s(ld, dn, modp, NULL, NULL);
  if (lrc != LDAP_SUCCESS)
    rc = ls_connection_fail(conn, err, LS_MODIFY_FAILED, lrc);

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
