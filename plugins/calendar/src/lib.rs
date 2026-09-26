use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_reha_calendar);

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("reha-calendar")
        .setup(|app, api| {
            #[cfg(target_os = "ios")]
            {
                use tauri::Manager;
                let handle = api.register_ios_plugin(init_plugin_reha_calendar)?;
                app.manage(Native(handle));
            }
            #[cfg(not(target_os = "ios"))]
            let _ = (app, api);
            Ok(())
        })
        .build()
}

#[cfg(target_os = "ios")]
pub struct Native<R: Runtime>(pub tauri::plugin::PluginHandle<R>);

pub fn call<R: Runtime>(
    app: &tauri::AppHandle<R>,
    command: &str,
    args: serde_json::Value,
) -> Result<serde_json::Value, String> {
    #[cfg(target_os = "ios")]
    {
        use tauri::Manager;
        app.state::<Native<R>>()
            .0
            .run_mobile_plugin(command, args)
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "ios"))]
    {
        let _ = (app, command, args);
        Err("Native calendar and camera are available in the iOS app. Use photo import and ICS export here.".into())
    }
}
