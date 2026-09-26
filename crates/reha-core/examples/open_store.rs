//! Apply supported migrations and report only deidentified storage diagnostics.
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = std::env::args().nth(1).ok_or("store directory required")?;
    let store = reha_core::store::Store::open(std::path::Path::new(&root))?;
    let integrity: String = store
        .connection
        .query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
    println!(
        "{}",
        serde_json::json!({"schema_version":reha_core::store::STORE_VERSION,"integrity":integrity,"scans":store.list_scans()?.len(),"imports":store.records(None)?.len(),"pending_writes":store.pending()?.len()})
    );
    Ok(())
}
