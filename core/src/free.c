/*
 * free.c — the public ls_*_free functions plus the internal recursive
 * teardown they share. Every string/array handed across the ABI is
 * plain malloc'd memory, so this is all just free().
 *
 * Tree shape: LSEntry.children is a malloc'd contiguous block of
 * `child_count` LSEntry values, each of which may own its own children
 * block, and so on.
 */
#include <stdlib.h>

#include "internal.h"

void ls_string_free(char *s) { free(s); }

static void free_str_array(char **arr, size_t n) {
  for (size_t i = 0; i < n; ++i) free(arr[i]);
  free(arr);
}

static void free_attributes(LSAttribute *attrs, size_t n) {
  for (size_t i = 0; i < n; ++i) {
    free(attrs[i].name);
    free(attrs[i].value);
  }
  free(attrs);
}

/* Frees everything the entry owns, recursing into children, but NOT the
 * LSEntry struct itself (it may live inside a parent's children block). */
static void entry_dispose_contents(LSEntry *e) {
  free(e->dn);
  free(e->name);
  free_attributes(e->attributes, e->attribute_count);
  for (size_t i = 0; i < e->child_count; ++i)
    entry_dispose_contents(&e->children[i]);
  free(e->children);
}

void ls_entry_free(LSEntry *entry) {
  if (!entry) return;
  entry_dispose_contents(entry);
  free(entry);
}

void ls_entries_free(LSEntry *entries, size_t n) {
  if (!entries) return;
  for (size_t i = 0; i < n; ++i) entry_dispose_contents(&entries[i]);
  free(entries);
}

static void free_object_class(LSObjectClass *oc) {
  free(oc->oid);
  free_str_array(oc->names, oc->name_count);
  free(oc->description);
  free_str_array(oc->superior_classes, oc->superior_class_count);
  free(oc->kind);
  free_str_array(oc->must, oc->must_count);
  free_str_array(oc->may, oc->may_count);
  free(oc->x_origin);
  free(oc->raw);
}

static void free_attribute_type(LSAttributeType *at) {
  free(at->oid);
  free_str_array(at->names, at->name_count);
  free(at->description);
  free(at->superior_type);
  free(at->equality_matching_rule);
  free(at->ordering_matching_rule);
  free(at->substring_matching_rule);
  free(at->syntax_oid);
  free(at->usage);
  free(at->x_origin);
  free(at->raw);
}

void ls_schema_free(LSSchema *schema) {
  if (!schema) return;
  for (size_t i = 0; i < schema->object_class_count; ++i)
    free_object_class(&schema->object_classes[i]);
  free(schema->object_classes);
  for (size_t i = 0; i < schema->attribute_type_count; ++i)
    free_attribute_type(&schema->attribute_types[i]);
  free(schema->attribute_types);
  free(schema);
}
