/* Checks the SSH tunnel against a throwaway sshd (see check.sh): several
 * pooled connections open through one tunnel at once and stream a large
 * branch side by side; a client that leaves responses unread doesn't
 * stall the others, and closing it doesn't kill the process; the tunnel
 * is reused afterwards. */
#include <ldap.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

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
static int open_rcs[4];

/* Opens without touching the connection policy (set once beforehand), so
 * several threads can do it at once. */
static void *open_concurrently(void *arg) {
  long i = (long)arg;
  LSError e = {0};
  LSConnection *c = NULL;
  open_rcs[i] = ls_connection_open("127.0.0.1", 3389, false,
                                   "cn=reader,ou=Service,dc=example,dc=com",
                                   "reader", &c, &e);
  if (open_rcs[i]) {
    printf("   concurrent open %ld failed: %s\n", i, e.reason);
    ls_error_dispose(&e);
  }
  ls_connection_close(c);
  return NULL;
}

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
  /* A raw client through the same tunnel that leaves eight pages of full
   * entries unread — what a cancelled export can leave on a pooled
   * connection. The tunnel's local port is found with lsof. */
  char cmd[256];
  snprintf(cmd, sizeof cmd,
           "lsof -nP -a -p %d -iTCP@127.0.0.1 -sTCP:LISTEN -Fn | "
           "sed -n 's/^n.*://p' | head -1",
           getpid());
  FILE *lsof = popen(cmd, "r");
  int port = 0;
  if (lsof) {
    if (fscanf(lsof, "%d", &port) != 1) port = 0;
    pclose(lsof);
  }
  char url[64];
  snprintf(url, sizeof url, "ldap://127.0.0.1:%d", port);
  LDAP *raw = NULL;
  ldap_initialize(&raw, url);
  int version = 3;
  ldap_set_option(raw, LDAP_OPT_PROTOCOL_VERSION, &version);
  struct berval cred = {6, (char *)"reader"};
  int bound = port > 0 && ldap_sasl_bind_s(raw,
                                          "cn=reader,ou=Service,dc=example,dc=com",
                                          NULL, &cred, NULL, NULL, NULL) == 0;
  check(bound, "SSH: raw client bound through the tunnel");
  for (int i = 0; bound && i < 8; i++) {
    LDAPControl *page = NULL;
    ldap_create_page_control(raw, 500, NULL, 0, &page);
    LDAPControl *ctrls[] = {page, NULL};
    int msgid;
    ldap_search_ext(raw, "ou=People,dc=example,dc=com", LDAP_SCOPE_ONELEVEL,
                    "(objectClass=*)", NULL, 0, ctrls, NULL, NULL, 0, &msgid);
    ldap_control_free(page);
  }
  sleep(1);
  struct timespec t0;
  struct timespec t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  long streamed = count_people(conns[0]);
  clock_gettime(CLOCK_MONOTONIC, &t1);
  double secs =
      (double)(t1.tv_sec - t0.tv_sec) + ((double)(t1.tv_nsec - t0.tv_nsec) / 1e9);
  printf("   streamed %ld past the stalled client in %.2fs\n", streamed, secs);
  check(streamed == 76000 && secs < 5,
        "SSH: a client with unread responses doesn't stall the others");
  ldap_unbind_ext(raw, NULL, NULL); /* the process must survive this */
  sleep(1);
  check(count_people(conns[1]) == 76000,
        "SSH: closing the stalled client is harmless; others keep working");

  for (int i = 0; i < 6; i++) ls_connection_close(conns[i]);
  LSConnection *again = NULL;
  check(open_conn(&again) == LS_OK && count_people(again) == 76000,
        "SSH: tunnel reused after every connection closed");
  ls_connection_close(again);

  /* With nothing using the tunnel, the server's keepalives (sshd here
   * sends one every second) must neither spin the forwarding thread nor
   * leave a dead tunnel for the next connection to trip over. */
  struct rusage before;
  struct rusage after;
  getrusage(RUSAGE_SELF, &before);
  sleep(5);
  getrusage(RUSAGE_SELF, &after);
  double cpu = (double)(after.ru_utime.tv_sec - before.ru_utime.tv_sec) +
               (double)(after.ru_stime.tv_sec - before.ru_stime.tv_sec) +
               ((double)(after.ru_utime.tv_usec - before.ru_utime.tv_usec) +
                (double)(after.ru_stime.tv_usec - before.ru_stime.tv_usec)) /
                   1e6;
  printf("   CPU over 5s with an idle tunnel: %.2fs\n", cpu);
  check(cpu < 0.5, "SSH: an idle tunnel doesn't spin on server keepalives");

  /* By now sshd has dropped the unanswered session, but the tunnel is
   * still cached: several connections opening through it at once must all
   * end up on a fresh tunnel. */
  policy();
  pthread_t openers[4];
  for (long i = 0; i < 4; i++)
    pthread_create(&openers[i], NULL, open_concurrently, (void *)i);
  int opened_ok = 0;
  for (int i = 0; i < 4; i++) {
    pthread_join(openers[i], NULL);
    opened_ok += open_rcs[i] == LS_OK;
  }
  check(opened_ok == 4,
        "SSH: four connections opening at once through a dead cached tunnel "
        "all succeed");
  LSConnection *later = NULL;
  check(open_conn(&later) == LS_OK && count_people(later) == 76000,
        "SSH: the next connection after the idle tunnel retired works first time");
  ls_connection_close(later);
  ls_shutdown(3000);
  printf(failures ? "SSH CHECKS FAILED\n" : "SSH CHECKS PASSED\n");
  return failures ? 1 : 0;
}
