use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use crate::connection::{connect_and_bind, ConnectionError};
use ldap3::{Scope, SearchEntry};
use std::collections::HashMap;

#[derive(uniffi::Record, Clone)]
pub struct LdapAttribute {
    pub name: String,
    /// For binary attributes (e.g. jpegPhoto), this is base64-encoded raw
    /// bytes rather than literal text — see `is_binary`.
    pub value: String,
    pub is_binary: bool,
}

#[derive(uniffi::Record, Clone)]
pub struct LdapEntry {
    pub dn: String,
    pub name: String,
    pub has_children: bool,
    pub attributes: Vec<LdapAttribute>,
    pub children: Vec<LdapEntry>,
}

fn display_name(dn: &str) -> String {
    dn.split(',').next().unwrap_or(dn).to_string()
}

/// Everything after the entry's own RDN — e.g. the parent of
/// "ou=People,dc=corp,dc=example,dc=com" is "dc=corp,dc=example,dc=com".
fn parent_dn(dn: &str) -> Option<String> {
    dn.splitn(2, ',').nth(1).map(str::to_string)
}

fn attributes_from(entry: &SearchEntry) -> Vec<LdapAttribute> {
    let mut attributes = Vec::new();

    for (name, values) in &entry.attrs {
        for value in values {
            attributes.push(LdapAttribute {
                name: name.clone(),
                value: value.clone(),
                is_binary: false,
            });
        }
    }

    // ldap3 routes any value that isn't valid UTF-8 (photos, certificates,
    // etc.) into `bin_attrs` instead — base64-encode it so it can still
    // cross the FFI boundary as a plain String.
    for (name, values) in &entry.bin_attrs {
        for value in values {
            attributes.push(LdapAttribute {
                name: name.clone(),
                value: BASE64.encode(value),
                is_binary: true,
            });
        }
    }

    attributes
}

/// Recursively assembles the tree for `dn`, using the already-fetched flat
/// results — no further network calls, everything came back in one search.
fn build_entry(
    dn: &str,
    by_dn: &HashMap<String, SearchEntry>,
    children_of: &HashMap<String, Vec<String>>,
) -> Option<LdapEntry> {
    let search_entry = by_dn.get(dn)?;

    let mut children: Vec<LdapEntry> = children_of
        .get(dn)
        .map(|child_dns| {
            child_dns
                .iter()
                .filter_map(|child_dn| build_entry(child_dn, by_dn, children_of))
                .collect()
        })
        .unwrap_or_default();

    children.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

    Some(LdapEntry {
        dn: dn.to_string(),
        name: display_name(dn),
        has_children: !children.is_empty(),
        attributes: attributes_from(search_entry),
        children,
    })
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn fetch_root_entry(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
    base_dn: String,
) -> Result<LdapEntry, ConnectionError> {
    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;

    // Subtree scope returns the base entry itself *and* every descendant at
    // any depth, in one round trip — no per-level fetching needed.
    let (results, _) = ldap
        .search(&base_dn, Scope::Subtree, "(objectClass=*)", vec!["*"])
        .await
        .map_err(|e| ConnectionError::SearchFailed {
            reason: e.to_string(),
        })?
        .success()
        .map_err(|e| ConnectionError::SearchFailed {
            reason: e.to_string(),
        })?;

    let _ = ldap.unbind().await;

    let mut by_dn: HashMap<String, SearchEntry> = HashMap::new();
    let mut children_of: HashMap<String, Vec<String>> = HashMap::new();

    for result in results {
        let entry = SearchEntry::construct(result);
        if let Some(parent) = parent_dn(&entry.dn) {
            children_of.entry(parent).or_default().push(entry.dn.clone());
        }
        by_dn.insert(entry.dn.clone(), entry);
    }

    build_entry(&base_dn, &by_dn, &children_of).ok_or_else(|| ConnectionError::SearchFailed {
        reason: format!("Base DN \"{base_dn}\" was not found"),
    })
}
