pub(crate) use reha_core::service::{failure, Application as AppState, Proposal, Response};
pub(crate) struct TauriPlatform(pub tauri::AppHandle);
impl reha_core::service::Platform for TauriPlatform {
    fn overlaps(
        &self,
        events: std::collections::BTreeMap<String, reha_core::contracts::EventValues>,
        exclude: Vec<String>,
    ) -> Response<Option<Vec<reha_core::contracts::CalendarOverlap>>> {
        let response = self.call(
            "overlaps",
            serde_json::json!({"events":events,"exclude":exclude}),
        )?;
        serde_json::from_value(response["overlaps"].clone())
            .map(Some)
            .map_err(failure)
    }
    fn call(&self, command: &str, arguments: serde_json::Value) -> Response<serde_json::Value> {
        tauri_plugin_reha_calendar::call(&self.0, command, arguments)
    }
    fn progress(&self, value: serde_json::Value) {
        use tauri::Emitter;
        let _ = self.0.emit("processing-progress", value);
    }
}
