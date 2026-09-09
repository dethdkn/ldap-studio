/*
 * hash.c — ls_hash_password: every userPassword hashing scheme the
 * "Set Password" picker offers, tagged the way LDAP expects.
 *
 *   {PBKDF2-SHA512}iter$b64(salt)$b64(key)   — recommended default
 *   {MD5} / {SHA}      base64(digest)                     (no salt)
 *   {SMD5} / {SSHA}    base64(digest(pw||salt) || salt)   (8-byte salt)
 *   {CRYPT}...         crypt(3): DES, or $1$/$5$/$6$ modular formats
 *
 * PBKDF2 and the plain/salted digests use OpenSSL (libcrypto); the whole
 * crypt(3) family — including the $1$/$5$/$6$ formats macOS's own
 * crypt(3) can't do — comes from libxcrypt. Salt bytes come from
 * arc4random_buf (a system CSPRNG, no extra library).
 */
#include <crypt.h> /* libxcrypt */
#include <openssl/evp.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

#define PBKDF2_ITERATIONS 100000
#define PBKDF2_SALT_LEN 16
#define PBKDF2_KEY_LEN 64 /* SHA-512 output length */
#define SIMPLE_SALT_LEN 8 /* conventional for SMD5 / SSHA */

static const char CRYPT_ALPHABET[] =
    "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/* One-shot digest via EVP (no OpenSSL 3 deprecation warnings). */
static void digest(const EVP_MD *md, const void *data, size_t len,
                   unsigned char *out, unsigned int *out_len) {
  EVP_Digest(data, len, out, out_len, md, NULL);
}

/* {TAG}base64(digest(pw)) — no salt. */
static char *hash_plain(const EVP_MD *md, const char *tag,
                        const char *plaintext) {
  unsigned char d[EVP_MAX_MD_SIZE];
  unsigned int dl = 0;
  digest(md, plaintext, strlen(plaintext), d, &dl);
  char *b64 = ls_b64_encode(d, dl);
  char *out = ls_aprintf("{%s}%s", tag, b64);
  free(b64);
  return out;
}

/* {TAG}base64(digest(pw || salt) || salt). */
static char *hash_salted(const EVP_MD *md, const char *tag,
                         const char *plaintext) {
  unsigned char salt[SIMPLE_SALT_LEN];
  arc4random_buf(salt, sizeof salt);

  size_t pw_len = strlen(plaintext);
  unsigned char *buf = ls_xmalloc(pw_len + sizeof salt);
  memcpy(buf, plaintext, pw_len);
  memcpy(buf + pw_len, salt, sizeof salt);

  unsigned char d[EVP_MAX_MD_SIZE];
  unsigned int dl = 0;
  digest(md, buf, pw_len + sizeof salt, d, &dl);
  free(buf);

  unsigned char *combined = ls_xmalloc(dl + sizeof salt);
  memcpy(combined, d, dl);
  memcpy(combined + dl, salt, sizeof salt);
  char *b64 = ls_b64_encode(combined, dl + sizeof salt);
  char *out = ls_aprintf("{%s}%s", tag, b64);
  free(combined);
  free(b64);
  return out;
}

static char *pbkdf2_sha512(const char *plaintext) {
  unsigned char salt[PBKDF2_SALT_LEN];
  unsigned char key[PBKDF2_KEY_LEN];
  arc4random_buf(salt, sizeof salt);

  PKCS5_PBKDF2_HMAC(plaintext, (int)strlen(plaintext), salt, sizeof salt,
                    PBKDF2_ITERATIONS, EVP_sha512(), sizeof key, key);

  char *b64_salt = ls_b64_encode(salt, sizeof salt);
  char *b64_key = ls_b64_encode(key, sizeof key);
  char *out = ls_aprintf("{PBKDF2-SHA512}%d$%s$%s", PBKDF2_ITERATIONS, b64_salt,
                         b64_key);
  free(b64_salt);
  free(b64_key);
  return out;
}

/* {CRYPT}<crypt(3) output> for a given setting string (libxcrypt). */
static char *crypt_with_setting(const char *plaintext, const char *setting,
                                LSError *err) {
  void *data = NULL;
  int size = 0;
  char *hash = crypt_ra(plaintext, setting, &data, &size);
  if (!hash || hash[0] == '*') { /* libxcrypt marks failure with '*' */
    free(data);
    ls_fail(err, LS_HASH_FAILED, NULL, 0, "crypt(3) rejected the settings");
    return NULL;
  }
  char *out = ls_aprintf("{CRYPT}%s", hash);
  free(data);
  return out;
}

/* {CRYPT} for one of the modular $id$ formats, salt from libxcrypt. */
static char *crypt_modular(const char *plaintext, const char *prefix,
                           LSError *err) {
  char setting[CRYPT_GENSALT_OUTPUT_SIZE];
  if (!crypt_gensalt_rn(prefix, 0 /* default cost */, NULL, 0, setting,
                        sizeof setting)) {
    ls_fail(err, LS_HASH_FAILED, NULL, 0, "could not generate a crypt salt");
    return NULL;
  }
  return crypt_with_setting(plaintext, setting, err);
}

int ls_hash_password(const char *plaintext, LSPasswordScheme scheme, char **out,
                     LSError *err) {
  if (!plaintext || !out)
    return ls_fail(err, LS_HASH_FAILED, NULL, 0, "missing argument");
  *out = NULL;

  switch (scheme) {
    case LS_PBKDF2_SHA512:
      *out = pbkdf2_sha512(plaintext);
      return LS_OK;
    case LS_MD5:
      *out = hash_plain(EVP_md5(), "MD5", plaintext);
      return LS_OK;
    case LS_SHA1:
      *out = hash_plain(EVP_sha1(), "SHA", plaintext); /* LDAP tag is {SHA} */
      return LS_OK;
    case LS_SMD5:
      *out = hash_salted(EVP_md5(), "SMD5", plaintext);
      return LS_OK;
    case LS_SSHA:
      *out = hash_salted(EVP_sha1(), "SSHA", plaintext);
      return LS_OK;

    case LS_UNIX_CRYPT: {
      unsigned char r[2];
      arc4random_buf(r, sizeof r);
      char salt[3] = {CRYPT_ALPHABET[r[0] & 0x3F], CRYPT_ALPHABET[r[1] & 0x3F],
                      '\0'};
      *out = crypt_with_setting(plaintext, salt, err);
      return *out ? LS_OK : LS_HASH_FAILED;
    }
    case LS_MD5_CRYPT:
      *out = crypt_modular(plaintext, "$1$", err);
      return *out ? LS_OK : LS_HASH_FAILED;
    case LS_SHA256_CRYPT:
      *out = crypt_modular(plaintext, "$5$", err);
      return *out ? LS_OK : LS_HASH_FAILED;
    case LS_SHA512_CRYPT:
      *out = crypt_modular(plaintext, "$6$", err);
      return *out ? LS_OK : LS_HASH_FAILED;
  }

  return ls_fail(err, LS_HASH_FAILED, NULL, 0, "unknown password scheme");
}
