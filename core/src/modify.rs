use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use crate::connection::{connect_and_bind, ConnectionError};
use crate::directory::LdapAttribute;
use ldap3::Mod;
use std::collections::{HashMap, HashSet};

fn modify_err(e: impl ToString) -> ConnectionError {
    ConnectionError::ModifyFailed {
        reason: e.to_string(),
    }
}

/// Deletes a single leaf entry — LDAP's plain Delete operation rejects
/// non-leaf entries, so Swift walks a subtree bottom-up, calling this once
/// per node starting with the deepest descendants.
#[uniffi::export(async_runtime = "tokio")]
pub async fn delete_entry(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
    dn: String,
) -> Result<(), ConnectionError> {
    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;
    let outcome = ldap
        .delete(&dn)
        .await
        .map_err(modify_err)?
        .success()
        .map_err(modify_err);
    let _ = ldap.unbind().await;
    outcome.map(|_| ())
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn add_attribute_value(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
    dn: String,
    attribute: String,
    value: String,
) -> Result<(), ConnectionError> {
    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;
    let outcome = ldap
        .modify(&dn, vec![Mod::Add(attribute, HashSet::from([value]))])
        .await
        .map_err(modify_err)?
        .success()
        .map_err(modify_err);
    let _ = ldap.unbind().await;
    outcome.map(|_| ())
}

/// Replaces one value of a (possibly multi-valued) attribute, leaving any
/// other values of that attribute untouched — a plain `Replace` would wipe
/// them out, so this does a targeted delete-then-add of just this value.
#[uniffi::export(async_runtime = "tokio")]
pub async fn modify_attribute_value(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
    dn: String,
    attribute: String,
    old_value: String,
    new_value: String,
) -> Result<(), ConnectionError> {
    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;
    let outcome = ldap
        .modify(
            &dn,
            vec![
                Mod::Delete(attribute.clone(), HashSet::from([old_value])),
                Mod::Add(attribute, HashSet::from([new_value])),
            ],
        )
        .await
        .map_err(modify_err)?
        .success()
        .map_err(modify_err);
    let _ = ldap.unbind().await;
    outcome.map(|_| ())
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn delete_attribute_value(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
    dn: String,
    attribute: String,
    value: String,
) -> Result<(), ConnectionError> {
    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;
    let outcome = ldap
        .modify(&dn, vec![Mod::Delete(attribute, HashSet::from([value]))])
        .await
        .map_err(modify_err)?
        .success()
        .map_err(modify_err);
    let _ = ldap.unbind().await;
    outcome.map(|_| ())
}

/// Moves (and/or renames) an entry. The RDN is kept as-is — only the parent
/// changes — since Swift always has the entry's current RDN as `name` and
/// only needs to pick a new parent from the tree.
#[uniffi::export(async_runtime = "tokio")]
pub async fn move_entry(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
    dn: String,
    new_superior: String,
) -> Result<(), ConnectionError> {
    let rdn = dn.split(',').next().unwrap_or(&dn).to_string();

    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;
    let outcome = ldap
        .modifydn(&dn, &rdn, true, Some(&new_superior))
        .await
        .map_err(modify_err)?
        .success()
        .map_err(modify_err);
    let _ = ldap.unbind().await;
    outcome.map(|_| ())
}

/// Creates a brand-new entry at `dn` with the given attributes — LDAP has no
/// native "copy", so Swift reads the source entry's already-fetched subtree
/// and calls this once per node (parents before children) to recreate it
/// elsewhere.
#[uniffi::export(async_runtime = "tokio")]
pub async fn add_entry(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
    dn: String,
    attributes: Vec<LdapAttribute>,
) -> Result<(), ConnectionError> {
    let mut grouped: HashMap<String, HashSet<Vec<u8>>> = HashMap::new();
    for attribute in attributes {
        let bytes = if attribute.is_binary {
            BASE64.decode(&attribute.value).unwrap_or_default()
        } else {
            attribute.value.into_bytes()
        };
        grouped.entry(attribute.name).or_default().insert(bytes);
    }
    // ldap3's `add` requires attribute names and values to share the same
    // generic type — names go through as UTF-8 bytes here.
    let attrs: Vec<(Vec<u8>, HashSet<Vec<u8>>)> = grouped
        .into_iter()
        .map(|(name, values)| (name.into_bytes(), values))
        .collect();

    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;
    let outcome = ldap
        .add(&dn, attrs)
        .await
        .map_err(modify_err)?
        .success()
        .map_err(modify_err);
    let _ = ldap.unbind().await;
    outcome.map(|_| ())
}
