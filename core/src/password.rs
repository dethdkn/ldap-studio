use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use rand::RngCore;

const ITERATIONS: u32 = 100_000;
const SALT_LEN: usize = 16;
const KEY_LEN: usize = 64; // SHA-512 output length, the usual choice for "-SHA512" PBKDF2 variants

/// Hashes `plaintext` as {PBKDF2-SHA512} — a client-side guarantee that
/// "Set Password" always stores a hash, regardless of whether the server
/// itself would have auto-hashed a plain userPassword write. Format:
/// `{PBKDF2-SHA512}<rounds>$<salt-b64>$<hash-b64>`, standard base64 with
/// padding — matches what 389-ds itself produces when it auto-hashes,
/// confirmed by decoding a real server-generated value during testing.
#[uniffi::export]
pub fn hash_password_pbkdf2_sha512(plaintext: String) -> String {
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);

    let mut key = [0u8; KEY_LEN];
    pbkdf2::pbkdf2_hmac::<sha2::Sha512>(plaintext.as_bytes(), &salt, ITERATIONS, &mut key);

    format!(
        "{{PBKDF2-SHA512}}{}${}${}",
        ITERATIONS,
        BASE64.encode(salt),
        BASE64.encode(key)
    )
}
