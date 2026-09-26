//! Read-only projections of existing capture, recognition and calendar journals.
use crate::{application::storage, runtime, AppError, NativeApplication};
use reha_core::store;

#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum ActivitySource {
    Capture,
    Recognition,
    CalendarImport,
    EventMutation,
}
impl ActivitySource {
    fn stored(self) -> &'static str {
        match self {
            Self::Capture => "capture",
            Self::Recognition => "recognition",
            Self::CalendarImport => "import",
            Self::EventMutation => "event",
        }
    }
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct ActivityRecord {
    pub id: String,
    pub created_at: i64,
    pub source: ActivitySource,
    pub source_id: String,
    pub document_id: Option<String>,
    // Historical display values retain their forward-compatible fallback labels.
    pub kind: String,
    pub status: String,
    pub count: u32,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct ActivityPage {
    pub items: Vec<ActivityRecord>,
    // Opaque keyset cursor; only the store interprets its persisted ordering keys.
    pub next_cursor: Option<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct RecognitionActivityDetail {
    pub document_id: String,
    pub status: String,
    pub error: Option<String>,
}
impl TryFrom<store::ActivityItem> for ActivityRecord {
    type Error = AppError;
    fn try_from(value: store::ActivityItem) -> Result<Self, Self::Error> {
        let source = match value.source.as_str() {
            "capture" => ActivitySource::Capture,
            "recognition" => ActivitySource::Recognition,
            "import" => ActivitySource::CalendarImport,
            "event" => ActivitySource::EventMutation,
            _ => return Err(storage("Unbekannte Quelle im lokalen Verlauf.")),
        };
        Ok(Self {
            id: value.id,
            created_at: value.created_at,
            source,
            source_id: value.source_id,
            document_id: value.document_id,
            kind: value.kind,
            status: value.status,
            count: value.count,
        })
    }
}
impl From<store::RecognitionActivityDetail> for RecognitionActivityDetail {
    fn from(value: store::RecognitionActivityDetail) -> Self {
        Self {
            document_id: value.document_id,
            status: value.status,
            error: value.error,
        }
    }
}
#[uniffi::export]
impl NativeApplication {
    pub async fn activity_page(
        &self,
        cursor: Option<String>,
        limit: Option<u32>,
        source: Option<ActivitySource>,
    ) -> Result<ActivityPage, AppError> {
        let state = self.state.clone();
        runtime()
            .spawn_blocking(move || {
                let page = state
                    .store
                    .lock()
                    .map_err(storage)?
                    .activity_page(limit, cursor.as_deref(), source.map(ActivitySource::stored))
                    .map_err(|error| match error {
                        reha_core::Error::Invalid(_) | reha_core::Error::Json(_) => {
                            AppError::Validation {
                                message: error.to_string(),
                            }
                        }
                        other => storage(other),
                    })?;
                Ok(ActivityPage {
                    items: page
                        .items
                        .into_iter()
                        .map(TryInto::try_into)
                        .collect::<Result<_, _>>()?,
                    next_cursor: page.next_cursor,
                })
            })
            .await
            .map_err(storage)?
    }
    pub async fn recognition_activity_detail(
        &self,
        id: String,
    ) -> Result<RecognitionActivityDetail, AppError> {
        let state = self.state.clone();
        runtime()
            .spawn_blocking(move || {
                state
                    .store
                    .lock()
                    .map_err(storage)?
                    .recognition_activity_detail(&id)
                    .map(Into::into)
                    .map_err(storage)
            })
            .await
            .map_err(storage)?
    }
}
