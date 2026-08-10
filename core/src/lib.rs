uniffi::setup_scaffolding!();

mod connection;

#[uniffi::export]
fn greet(name: String) -> String {
    format!("Hello, {name}! (from Rust)")
}
