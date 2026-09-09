/*
 * version.c — ls_dependency_versions: the versions of the bundled native
 * libraries this build was compiled against, for the "About" window.
 *
 * Taken from each library's own header at compile time. Because the Xcode
 * build compiles against and bundles the dylibs from the same Homebrew
 * prefix, these match what actually ships in the .app.
 */
#include <crypt.h>            /* XCRYPT_VERSION_STR */
#include <ldap_features.h>    /* LDAP_VENDOR_VERSION_{MAJOR,MINOR,PATCH} */
#include <openssl/opensslv.h> /* OPENSSL_VERSION_STR */

#include "ldapstudio.h"

#define LS_STR_(x) #x
#define LS_STR(x) LS_STR_(x)

#define LS_OPENLDAP_VERSION         \
  LS_STR(LDAP_VENDOR_VERSION_MAJOR) \
  "." LS_STR(LDAP_VENDOR_VERSION_MINOR) "." LS_STR(LDAP_VENDOR_VERSION_PATCH)

LSDependencyVersions ls_dependency_versions(void) {
  LSDependencyVersions v = {
      .openldap = LS_OPENLDAP_VERSION,
      .openssl = OPENSSL_VERSION_STR,
      .libxcrypt = XCRYPT_VERSION_STR,
  };
  return v;
}
