use crate::AppError;
use reha_core::service;

pub(crate) fn storage(e: impl std::fmt::Display) -> AppError {
    AppError::Storage {
        message: e.to_string(),
    }
}
pub(crate) fn failure(error: service::ServiceError) -> AppError {
    use service::{DomainFailure as D, ServiceError as E};
    match error {
        E::Legacy(message) | E::Validation(message) => AppError::Validation { message },
        E::Storage(message) => AppError::Storage { message },
        E::Domain { kind, .. } => match kind {
            D::ExpiredScan => AppError::ExpiredScan,
            D::StaleRevision => AppError::StaleRevision,
            D::StaleProposal => AppError::StaleProposal,
            D::Busy => AppError::Busy,
            D::UncertainWrite => AppError::UncertainWrite,
        },
        E::PermissionDenied => AppError::PermissionDenied,
        E::Timeout(operation) => AppError::Timeout { operation },
        E::UncertainWrite => AppError::UncertainWrite,
        E::ExpiredScan => AppError::ExpiredScan,
        E::StaleRevision => AppError::StaleRevision,
        E::StaleProposal => AppError::StaleProposal,
        E::Busy => AppError::Busy,
        E::Cancelled => AppError::Cancelled,
    }
}
pub(super) fn platform_failure(error: AppError) -> service::ServiceError {
    use service::ServiceError as E;
    match error {
        AppError::Validation { message } => E::Validation(message),
        AppError::Storage { message } => E::Storage(message),
        AppError::PermissionDenied => E::PermissionDenied,
        AppError::Timeout { operation } => E::Timeout(operation),
        AppError::UncertainWrite => E::UncertainWrite,
        AppError::ExpiredScan => E::ExpiredScan,
        AppError::StaleRevision => E::StaleRevision,
        AppError::StaleProposal => E::StaleProposal,
        AppError::Busy => E::Busy,
        AppError::Cancelled => E::Cancelled,
    }
}
