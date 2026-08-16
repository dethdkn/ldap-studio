use ldap3::{Ldap, LdapConnAsync};

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ConnectionError {
    #[error("Could not connect to {host}:{port}: {reason}")]
    ConnectFailed {
        host: String,
        port: u16,
        reason: String,
    },
    #[error("Bind failed: {reason}")]
    BindFailed { reason: String },
    #[error("Search failed: {reason}")]
    SearchFailed { reason: String },
}

/// Connects and binds, handing back a ready-to-use `Ldap` handle. Shared by
/// every feature that needs a live connection (connection testing, directory
/// browsing, and anything else added later).
pub(crate) async fn connect_and_bind(
    host: &str,
    port: u16,
    use_ssl: bool,
    bind_dn: &str,
    password: &str,
) -> Result<Ldap, ConnectionError> {
    let scheme = if use_ssl { "ldaps" } else { "ldap" };
    let url = format!("{scheme}://{host}:{port}");

    let (conn, mut ldap) =
        LdapConnAsync::new(&url)
            .await
            .map_err(|e| ConnectionError::ConnectFailed {
                host: host.to_string(),
                port,
                reason: e.to_string(),
            })?;
    ldap3::drive!(conn);

    let bind_result = if bind_dn.is_empty() {
        ldap.simple_bind("", "").await
    } else {
        ldap.simple_bind(bind_dn, password).await
    };

    bind_result
        .map_err(|e| ConnectionError::BindFailed {
            reason: e.to_string(),
        })?
        .success()
        .map_err(|e| ConnectionError::BindFailed {
            reason: e.to_string(),
        })?;

    Ok(ldap)
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn test_connection(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
) -> Result<(), ConnectionError> {
    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;
    let _ = ldap.unbind().await;
    Ok(())
}
