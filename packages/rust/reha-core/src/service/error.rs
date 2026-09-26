/// Native failure identity survives service dispatch without parsing display text.
/// Legacy preserves the existing domain-validation adapter until those callers
/// have explicit error variants; it must never wrap a native callback failure.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ServiceError {
    #[error("{0}")]
    Legacy(String),
    #[error("{0}")]
    Validation(String),
    #[error("{0}")]
    Storage(String),
    #[error("Kalenderzugriff fehlt.")]
    PermissionDenied,
    #[error("Zeitbudget der Aktion {0} erschöpft.")]
    Timeout(String),
    #[error("Schreibstatus unklar. Abgleich erforderlich.")]
    UncertainWrite,
    #[error("Scan wurde gelöscht oder ist abgelaufen.")]
    ExpiredScan,
    #[error("Neuere Änderungen vorhanden. Erneut laden.")]
    StaleRevision,
    #[error("Vorschau abgelaufen. Erneut erstellen.")]
    StaleProposal,
    #[error("Eine Erkennung läuft bereits.")]
    Busy,
    #[error("Abgebrochen; vorhandener Entwurf bleibt erhalten.")]
    Cancelled,
}

impl From<String> for ServiceError {
    fn from(message: String) -> Self {
        Self::Legacy(message)
    }
}
impl From<&str> for ServiceError {
    fn from(message: &str) -> Self {
        Self::Legacy(message.into())
    }
}
// Persisted diagnostics and maintenance warnings remain strings. This is a
// storage compatibility projection, never the transport for a native failure.
impl serde::Serialize for ServiceError {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_string())
    }
}
