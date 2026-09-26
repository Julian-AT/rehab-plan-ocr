//! Typed boundary for the native Apple application. Domain storage stays in reha-core.
use std::sync::OnceLock;
uniffi::setup_scaffolding!();
mod records;
pub use records::*;
mod agenda_queries;
pub use agenda_queries::*;
mod calendar_administration;
mod calendar_imports;
pub use calendar_administration::*;
mod calendar_mutations;
pub use calendar_mutations::*;
mod calendar_reads;
pub use calendar_reads::*;
mod recognition_jobs;
pub use recognition_jobs::RecognitionJob;
mod speech;
pub use speech::*;
mod application;
pub use application::*;
mod assistant;
pub use assistant::*;

fn runtime() -> &'static tokio::runtime::Runtime {
    static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("native runtime")
    })
}
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum AppError {
    #[error("{message}")]
    Validation { message: String },
    #[error("{message}")]
    Storage { message: String },
    #[error("Scan wurde gelöscht oder ist abgelaufen.")]
    ExpiredScan,
    #[error("Neuere Änderungen vorhanden. Erneut laden.")]
    StaleRevision,
    #[error("Vorschau abgelaufen. Erneut erstellen.")]
    StaleProposal,
    #[error("Kalenderzugriff fehlt.")]
    PermissionDenied,
    #[error("Schreibstatus unklar. Abgleich erforderlich.")]
    UncertainWrite,
    #[error("Eine Erkennung läuft bereits.")]
    Busy,
    #[error("Abgebrochen; vorhandener Entwurf bleibt erhalten.")]
    Cancelled,
    #[error("Zeitbudget der Aktion {operation} erschöpft.")]
    Timeout { operation: String },
}
