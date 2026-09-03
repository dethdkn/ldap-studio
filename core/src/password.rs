use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use digest::Digest;
use rand::RngExt;

const PBKDF2_ITERATIONS: u32 = 100_000;
const PBKDF2_SALT_LEN: usize = 16;
const PBKDF2_KEY_LEN: usize = 64; // SHA-512 output length, the usual choice for "-SHA512" PBKDF2 variants
const SIMPLE_SALT_LEN: usize = 8; // conventional salt length for SMD5/SSHA

/// Every userPassword hashing scheme the "Set Password" picker offers.
/// PBKDF2-SHA512 is our own recommended default (a real, configurable work
/// factor); the rest exist so the hash matches whatever a specific server
/// or migration expects — several (plain MD5/SHA1, and the classic Unix
/// crypt) are only offered for compatibility and are not secure by modern
/// standards.
///
/// MD4 and RIPEMD-160 were deliberately left out: they were live-tested
/// against a real server (389 Directory Server) and turned out not to be
/// recognized `userPassword` schemes at all — the server silently treated
/// the whole `{MD4}...`/`{RIPEMD160}...` string as a literal cleartext
/// password and re-hashed *that*, permanently discarding the intended
/// password with no error shown. Every other scheme here was verified the
/// same way and round-tripped correctly.
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq)]
pub enum PasswordScheme {
    Pbkdf2Sha512,
    UnixCrypt,
    Md5Crypt,
    Md5,
    Sha1,
    Smd5,
    Ssha,
    Sha256Crypt,
    Sha512Crypt,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum PasswordError {
    #[error("Couldn't hash the password: {reason}")]
    HashFailed { reason: String },
}

/// Hashes `plaintext` using the chosen scheme, tagged the way LDAP's
/// userPassword expects: `{SCHEME}...` for the simple digest-based
/// schemes, `{CRYPT}...` for the crypt(3) family (whose own `$id$` marker,
/// already part of the hash string, identifies the specific algorithm).
#[uniffi::export]
#[allow(deprecated)] // the legacy crypt(3) schemes are offered deliberately, for compatibility
pub fn hash_password(plaintext: String, scheme: PasswordScheme) -> Result<String, PasswordError> {
    match scheme {
        PasswordScheme::Pbkdf2Sha512 => Ok(hash_pbkdf2_sha512(&plaintext)),
        PasswordScheme::Md5 => Ok(hash_plain::<md5::Md5>("MD5", &plaintext)),
        // LDAP's conventional tag for SHA-1 is "{SHA}", not "{SHA1}".
        PasswordScheme::Sha1 => Ok(hash_plain::<sha1::Sha1>("SHA", &plaintext)),
        PasswordScheme::Smd5 => Ok(hash_salted::<md5::Md5>("SMD5", &plaintext)),
        PasswordScheme::Ssha => Ok(hash_salted::<sha1::Sha1>("SSHA", &plaintext)),
        PasswordScheme::UnixCrypt => wrap_crypt(crypt3_rs::crypt::unix::hash(&plaintext)),
        PasswordScheme::Md5Crypt => wrap_crypt(crypt3_rs::crypt::md5::hash(&plaintext)),
        PasswordScheme::Sha256Crypt => wrap_crypt(crypt3_rs::crypt::sha256::hash(&plaintext)),
        PasswordScheme::Sha512Crypt => wrap_crypt(crypt3_rs::crypt::sha512::hash(&plaintext)),
    }
}

/// `{SCHEME}base64(digest(password))` — no salt: MD5, SHA1.
fn hash_plain<D: Digest>(tag: &str, plaintext: &str) -> String {
    let digest = D::digest(plaintext.as_bytes());
    format!("{{{tag}}}{}", BASE64.encode(digest))
}

/// `{SCHEME}base64(digest(password ++ salt) ++ salt)` — SMD5, SSHA. Same
/// construction as the {SSHA} scheme this app used before switching its
/// default to PBKDF2-SHA512, generalized over the digest type.
fn hash_salted<D: Digest>(tag: &str, plaintext: &str) -> String {
    let mut salt = [0u8; SIMPLE_SALT_LEN];
    rand::rng().fill(&mut salt);

    let mut hasher = D::new();
    hasher.update(plaintext.as_bytes());
    hasher.update(salt);
    let digest = hasher.finalize();

    let mut combined = digest.to_vec();
    combined.extend_from_slice(&salt);
    format!("{{{tag}}}{}", BASE64.encode(combined))
}

/// The crypt(3) family (Unix/DES, MD5, SHA-256, SHA-512 crypt) already
/// produces its own correctly-tagged `$id$salt$checksum` string (or, for
/// classic Unix crypt, the untagged salt+checksum format) — LDAP's
/// `{CRYPT}` scheme just means "whatever the OS crypt() function would
/// return, verbatim", so this only needs to add that prefix.
fn wrap_crypt(result: Result<crypt3_rs::Hash, crypt3_rs::error::Error>) -> Result<String, PasswordError> {
    result
        .map(|hash| format!("{{CRYPT}}{}", hash.as_str()))
        .map_err(|e| PasswordError::HashFailed { reason: e.to_string() })
}

fn hash_pbkdf2_sha512(plaintext: &str) -> String {
    let mut salt = [0u8; PBKDF2_SALT_LEN];
    rand::rng().fill(&mut salt);

    let mut key = [0u8; PBKDF2_KEY_LEN];
    pbkdf2::pbkdf2_hmac::<sha2::Sha512>(plaintext.as_bytes(), &salt, PBKDF2_ITERATIONS, &mut key);

    format!(
        "{{PBKDF2-SHA512}}{}${}${}",
        PBKDF2_ITERATIONS,
        BASE64.encode(salt),
        BASE64.encode(key)
    )
}
