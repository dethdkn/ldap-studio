use ldap3::LdapConnAsync;

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
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn test_connection(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
) -> Result<(), ConnectionError> {
    let scheme = if use_ssl { "ldaps" } else { "ldap" };
    let url = format!("{scheme}://{host}:{port}");

    let (conn, mut ldap) =
        LdapConnAsync::new(&url)
            .await
            .map_err(|e| ConnectionError::ConnectFailed {
                host: host.clone(),
                port,
                reason: e.to_string(),
            })?;
    ldap3::drive!(conn);

    let bind_result = if bind_dn.is_empty() {
        ldap.simple_bind("", "").await
    } else {
        ldap.simple_bind(&bind_dn, &password).await
    };

    bind_result
        .map_err(|e| ConnectionError::BindFailed {
            reason: e.to_string(),
        })?
        .success()
        .map_err(|e| ConnectionError::BindFailed {
            reason: e.to_string(),
        })?;

    let _ = ldap.unbind().await;

    Ok(())
}
