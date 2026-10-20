/* Checks the SSH tunnel against a throwaway sshd (see check.sh): several
 * pooled connections open through one tunnel at once and stream a large
 * branch side by side, and the tunnel is reused afterwards. */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ldapstudio.h"

static char pin[200];
static const char *key_path;
static int failures;

static void check(int ok, const char *what) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

static void policy(void) {
  ls_set_tls_policy(false, false, NULL);
  ls_set_connection_policy(false, 8, LS_AUTH_SIMPLE, "", "", NULL, NULL);
  ls_set_ssh_policy(true, "127.0.0.1", 2222, getenv("USER"),
                    LS_SSH_PRIVATE_KEY, "", key_path, pin);
}

static int open_conn(LSConnection **out) {
  LSError e = {0};
  policy();
  int rc = ls_connection_open("127.0.0.1", 3389, false,
                              "cn=reader,ou=Service,dc=example,dc=com",
                              "reader", out, &e);
  if (rc == LS_SSH_HOST_KEY_UNTRUSTED) {
    snprintf(pin, sizeof pin, "%s", e.reason);
    ls_error_dispose(&e);
    return open_conn(out);
  }
  if (rc) {
    printf("   open failed: %s\n", e.reason);
    ls_error_dispose(&e);
  }
  return rc;
}

static long count_people(LSConnection *c) {
  LSSearch *s = NULL;
  LSError e = {0};
  long total = 0;
  const char *attrs[] = {"1.1"};
  ls_search_begin(c, "ou=People,dc=example,dc=com", LS_SCOPE_ONELEVEL, NULL,
                  attrs, 1, false, 500, 10, &s, &e);
  for (;;) {
    LSEntry *out;
    size_t n;
    bool done;
    bool truncated;
    if (ls_search_next_page(s, NULL, &out, &n, &done, &truncated, &e)) {
      ls_error_dispose(&e);
      total = -1;
      break;
    }
    total += (long)n;
    ls_entries_free(out, n);
    if (done) break;
  }
  ls_search_free(s);
  return total;
}

static LSConnection *conns[6];
static long counts[6];

static void *stream(void *arg) {
  long i = (long)arg;
  counts[i] = count_people(conns[i]);
  return NULL;
}

int main(int argc, char **argv) {
  key_path = argc > 1 ? argv[1] : "";
  int opened = 0;
  for (int i = 0; i < 6; i++) opened += open_conn(&conns[i]) == LS_OK;
  check(opened == 6, "SSH: six connections open through one tunnel at once");
  if (opened != 6) return 1;
  pthread_t threads[6];
  for (long i = 0; i < 6; i++) pthread_create(&threads[i], NULL, stream, (void *)i);
  int all = 1;
  for (int i = 0; i < 6; i++) {
    pthread_join(threads[i], NULL);
    all = all && counts[i] == 76000;
  }
  check(all, "SSH: six 76,000-entry searches stream side by side");
  for (int i = 0; i < 6; i++) ls_connection_close(conns[i]);
  LSConnection *again = NULL;
  check(open_conn(&again) == LS_OK && count_people(again) == 76000,
        "SSH: tunnel reused after every connection closed");
  ls_connection_close(again);
  ls_shutdown(3000);
  printf(failures ? "SSH CHECKS FAILED\n" : "SSH CHECKS PASSED\n");
  return failures ? 1 : 0;
}
