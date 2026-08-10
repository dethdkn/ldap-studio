uniffi::setup_scaffolding!();

#[uniffi::export]
fn greet(name: String) -> String {
    format!("Hello, {name}! (from Rust)")
}
