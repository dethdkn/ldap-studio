/*
 * schema.c — ls_fetch_schema: fetch and parse the server's objectClasses
 * and attributeTypes. A direct port of the old Rust schema.rs, including
 * its small hand-rolled RFC 4512 scanner.
 *
 * The schema isn't at a fixed DN: the Root DSE's subschemaSubentry
 * operational attribute points at it (RFC 4512), with cn=subschema as the
 * conventional fallback.
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h> /* strcasecmp */

#include "internal_ldap.h"

/* ── scanner ─────────────────────────────────────────────────────── */

typedef struct {
  const char *p;
  const char *end;
} Scanner;

static void sc_init(Scanner *s, const char *str) {
  s->p = str;
  s->end = str + strlen(str);
}

static void sc_skip_ws(Scanner *s) {
  while (s->p < s->end && isspace((unsigned char)*s->p)) s->p++;
}

static char sc_peek(Scanner *s) { return s->p < s->end ? *s->p : '\0'; }

/* Bare token: up to the next whitespace, parenthesis, or '$'. NULL if empty. */
static char *sc_read_word(Scanner *s) {
  sc_skip_ws(s);
  const char *start = s->p;
  while (s->p < s->end) {
    char c = *s->p;
    if (isspace((unsigned char)c) || c == '(' || c == ')' || c == '$') break;
    s->p++;
  }
  if (s->p == start) return NULL;
  return ls_strdup_n(start, (size_t)(s->p - start));
}

/* Single-quoted string, unescaping "\XX" hex-byte escapes. */
static char *sc_read_quoted(Scanner *s) {
  sc_skip_ws(s);
  if (sc_peek(s) != '\'') return NULL;
  s->p++;

  size_t cap = 16;
  size_t n = 0;
  char *out = ls_xmalloc(cap);
  while (s->p < s->end) {
    char c = *s->p++;
    if (c == '\'') break;
    if (c == '\\' && s->p + 1 < s->end) {
      char h1 = s->p[0];
      char h2 = s->p[1];
      char hex[3] = {h1, h2, 0};
      char *endp = NULL;
      long byte = strtol(hex, &endp, 16);
      if (endp == hex + 2) {
        s->p += 2;
        c = (char)byte;
      }
    }
    if (n + 1 >= cap) {
      cap *= 2;
      out = ls_xrealloc(out, cap);
    }
    out[n++] = c;
  }
  out[n] = '\0';
  return out;
}

/* One bare token, or a parenthesized '$'-separated list (SUP/MUST/MAY). */
static void sc_read_oid_list(Scanner *s, LSStrList *list) {
  ls_strlist_init(list);
  sc_skip_ws(s);
  if (sc_peek(s) != '(') {
    char *w = sc_read_word(s);
    if (w) ls_strlist_push(list, w);
    return;
  }
  s->p++;
  for (;;) {
    sc_skip_ws(s);
    char c = sc_peek(s);
    if (c == ')') {
      s->p++;
      break;
    }
    if (c == '$') {
      s->p++;
      continue;
    }
    if (c == '\0') break;
    char *w = sc_read_word(s);
    if (!w) break;
    ls_strlist_push(list, w);
  }
}

/* One quoted string, or a parenthesized list of them (NAME, X-... values). */
static void sc_read_qdescrs(Scanner *s, LSStrList *list) {
  ls_strlist_init(list);
  sc_skip_ws(s);
  if (sc_peek(s) != '(') {
    char *q = sc_read_quoted(s);
    if (q) ls_strlist_push(list, q);
    return;
  }
  s->p++;
  for (;;) {
    sc_skip_ws(s);
    char c = sc_peek(s);
    if (c == ')') {
      s->p++;
      break;
    }
    if (c == '\0') break;
    char *q = sc_read_quoted(s);
    if (!q) break;
    ls_strlist_push(list, q);
  }
}

static void upper_ascii(char *s) {
  for (; *s; ++s) *s = (char)toupper((unsigned char)*s);
}

static char *first_or_null(LSStrList *l) {
  if (l->count == 0) {
    ls_strlist_free_items(l);
    return NULL;
  }
  char *first = ls_xstrdup(l->items[0]);
  ls_strlist_free_items(l);
  return first;
}

/* ── parsers ─────────────────────────────────────────────────────── */

static bool parse_object_class(const char *raw, LSObjectClass *out) {
  Scanner s;
  sc_init(&s, raw);
  sc_skip_ws(&s);
  if (sc_peek(&s) != '(') return false;
  s.p++;

  char *oid = sc_read_word(&s);
  if (!oid) return false;

  memset(out, 0, sizeof *out);
  out->oid = oid;
  out->kind = ls_xstrdup("STRUCTURAL");
  out->raw = ls_xstrdup(raw);

  for (;;) {
    sc_skip_ws(&s);
    char c = sc_peek(&s);
    if (c == ')') {
      s.p++;
      break;
    }
    if (c == '\0') break;

    char *kw = sc_read_word(&s);
    if (!kw) break;
    char up[64];
    snprintf(up, sizeof up, "%s", kw);
    upper_ascii(up);

    if (strcmp(up, "NAME") == 0) {
      LSStrList l;
      sc_read_qdescrs(&s, &l);
      out->names = l.items;
      out->name_count = l.count;
    } else if (strcmp(up, "DESC") == 0) {
      free(out->description);
      out->description = sc_read_quoted(&s);
    } else if (strcmp(up, "OBSOLETE") == 0) {
      out->obsolete = true;
    } else if (strcmp(up, "SUP") == 0) {
      LSStrList l;
      sc_read_oid_list(&s, &l);
      out->superior_classes = l.items;
      out->superior_class_count = l.count;
    } else if (strcmp(up, "STRUCTURAL") == 0 || strcmp(up, "ABSTRACT") == 0 ||
               strcmp(up, "AUXILIARY") == 0) {
      free(out->kind);
      out->kind = ls_xstrdup(up);
    } else if (strcmp(up, "MUST") == 0) {
      LSStrList l;
      sc_read_oid_list(&s, &l);
      out->must = l.items;
      out->must_count = l.count;
    } else if (strcmp(up, "MAY") == 0) {
      LSStrList l;
      sc_read_oid_list(&s, &l);
      out->may = l.items;
      out->may_count = l.count;
    } else if (strncmp(up, "X-", 2) == 0) {
      LSStrList l;
      sc_read_qdescrs(&s, &l);
      if (strcasecmp(kw, "X-ORIGIN") == 0 && !out->x_origin)
        out->x_origin = first_or_null(&l);
      else
        ls_strlist_free_items(&l);
    }
    free(kw);
  }
  return true;
}

static bool parse_attribute_type(const char *raw, LSAttributeType *out) {
  Scanner s;
  sc_init(&s, raw);
  sc_skip_ws(&s);
  if (sc_peek(&s) != '(') return false;
  s.p++;

  char *oid = sc_read_word(&s);
  if (!oid) return false;

  memset(out, 0, sizeof *out);
  out->oid = oid;
  out->raw = ls_xstrdup(raw);

  for (;;) {
    sc_skip_ws(&s);
    char c = sc_peek(&s);
    if (c == ')') {
      s.p++;
      break;
    }
    if (c == '\0') break;

    char *kw = sc_read_word(&s);
    if (!kw) break;
    char up[64];
    snprintf(up, sizeof up, "%s", kw);
    upper_ascii(up);

    if (strcmp(up, "NAME") == 0) {
      LSStrList l;
      sc_read_qdescrs(&s, &l);
      out->names = l.items;
      out->name_count = l.count;
    } else if (strcmp(up, "DESC") == 0) {
      free(out->description);
      out->description = sc_read_quoted(&s);
    } else if (strcmp(up, "OBSOLETE") == 0) {
      out->obsolete = true;
    } else if (strcmp(up, "SUP") == 0) {
      free(out->superior_type);
      out->superior_type = sc_read_word(&s);
    } else if (strcmp(up, "EQUALITY") == 0) {
      free(out->equality_matching_rule);
      out->equality_matching_rule = sc_read_word(&s);
    } else if (strcmp(up, "ORDERING") == 0) {
      free(out->ordering_matching_rule);
      out->ordering_matching_rule = sc_read_word(&s);
    } else if (strcmp(up, "SUBSTR") == 0) {
      free(out->substring_matching_rule);
      out->substring_matching_rule = sc_read_word(&s);
    } else if (strcmp(up, "SYNTAX") == 0) {
      free(out->syntax_oid);
      out->syntax_oid = sc_read_word(&s);
    } else if (strcmp(up, "SINGLE-VALUE") == 0) {
      out->single_valued = true;
    } else if (strcmp(up, "COLLECTIVE") == 0) {
      out->collective = true;
    } else if (strcmp(up, "NO-USER-MODIFICATION") == 0) {
      out->no_user_modification = true;
    } else if (strcmp(up, "USAGE") == 0) {
      free(out->usage);
      out->usage = sc_read_word(&s);
    } else if (strncmp(up, "X-", 2) == 0) {
      LSStrList l;
      sc_read_qdescrs(&s, &l);
      if (strcasecmp(kw, "X-ORIGIN") == 0 && !out->x_origin)
        out->x_origin = first_or_null(&l);
      else
        ls_strlist_free_items(&l);
    }
    free(kw);
  }
  return true;
}

/* ── fetch ───────────────────────────────────────────────────────── */

/* First value of `attr` on the first entry of `res`, as an owned string. */
static char *first_value(LDAP *ld, LDAPMessage *res, const char *attr) {
  LDAPMessage *e = ldap_first_entry(ld, res);
  if (!e) return NULL;
  struct berval **vals = ldap_get_values_len(ld, e, attr);
  if (!vals || !vals[0]) {
    if (vals) ldap_value_free_len(vals);
    return NULL;
  }
  char *out = ls_strdup_n(vals[0]->bv_val, vals[0]->bv_len);
  ldap_value_free_len(vals);
  return out;
}

int ls_fetch_schema(const char *host, uint16_t port, bool use_ssl,
                    const char *bind_dn, const char *password, LSSchema **out,
                    LSError *err) {
  *out = NULL;

  LDAP *ld = NULL;
  int rc =
      ls_connect_and_bind(host, port, use_ssl, bind_dn, password, &ld, err);
  if (rc != LS_OK) return rc;

  /* Root DSE → subschemaSubentry. */
  char *rootattrs[] = {(char *)"subschemaSubentry", NULL};
  LDAPMessage *dse = NULL;
  int lrc =
      ldap_search_ext_s(ld, "", LDAP_SCOPE_BASE, "(objectClass=*)", rootattrs,
                        0, NULL, NULL, NULL, LDAP_NO_LIMIT, &dse);
  if (lrc != LDAP_SUCCESS) {
    if (dse) ldap_msgfree(dse);
    ldap_unbind_ext_s(ld, NULL, NULL);
    return ls_ldap_fail(err, LS_SEARCH_FAILED, lrc);
  }
  char *subschema = first_value(ld, dse, "subschemaSubentry");
  ldap_msgfree(dse);
  if (!subschema) subschema = ls_xstrdup("cn=subschema");

  /* The schema entry itself. */
  char *schemaattrs[] = {(char *)"objectClasses", (char *)"attributeTypes",
                         NULL};
  LDAPMessage *sres = NULL;
  lrc =
      ldap_search_ext_s(ld, subschema, LDAP_SCOPE_BASE, "(objectClass=*)",
                        schemaattrs, 0, NULL, NULL, NULL, LDAP_NO_LIMIT, &sres);
  if (lrc != LDAP_SUCCESS) {
    if (sres) ldap_msgfree(sres);
    ldap_unbind_ext_s(ld, NULL, NULL);
    char *reason = ls_aprintf("Schema entry \"%s\" was not found", subschema);
    free(subschema);
    int r = ls_fail(err, LS_SEARCH_FAILED, NULL, 0, reason);
    free(reason);
    return r;
  }

  LDAPMessage *entry = ldap_first_entry(ld, sres);
  if (!entry) {
    char *reason = ls_aprintf("Schema entry \"%s\" was not found", subschema);
    free(subschema);
    ldap_msgfree(sres);
    ldap_unbind_ext_s(ld, NULL, NULL);
    int r = ls_fail(err, LS_SEARCH_FAILED, NULL, 0, reason);
    free(reason);
    return r;
  }
  free(subschema);

  LSSchema *schema = ls_xcalloc(1, sizeof(LSSchema));

  struct berval **ocs = ldap_get_values_len(ld, entry, "objectClasses");
  if (ocs) {
    size_t n = 0;
    while (ocs[n]) n++;
    schema->object_classes = ls_xmalloc((n ? n : 1) * sizeof(LSObjectClass));
    for (size_t i = 0; i < n; ++i) {
      char *raw = ls_strdup_n(ocs[i]->bv_val, ocs[i]->bv_len);
      if (parse_object_class(
              raw, &schema->object_classes[schema->object_class_count]))
        schema->object_class_count++;
      free(raw);
    }
    ldap_value_free_len(ocs);
  }

  struct berval **ats = ldap_get_values_len(ld, entry, "attributeTypes");
  if (ats) {
    size_t n = 0;
    while (ats[n]) n++;
    schema->attribute_types = ls_xmalloc((n ? n : 1) * sizeof(LSAttributeType));
    for (size_t i = 0; i < n; ++i) {
      char *raw = ls_strdup_n(ats[i]->bv_val, ats[i]->bv_len);
      if (parse_attribute_type(
              raw, &schema->attribute_types[schema->attribute_type_count]))
        schema->attribute_type_count++;
      free(raw);
    }
    ldap_value_free_len(ats);
  }

  ldap_msgfree(sres);
  ldap_unbind_ext_s(ld, NULL, NULL);

  *out = schema;
  return LS_OK;
}
