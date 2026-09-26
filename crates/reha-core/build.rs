fn main() {
    println!("cargo:rerun-if-env-changed=ORT_LIB_LOCATION");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios")
        && std::env::var_os("CARGO_FEATURE_ONNX").is_some()
    {
        let path = std::env::var_os("ORT_LIB_LOCATION")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| {
                std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap())
                    .join("../../models/private/runtime")
                    .join(std::env::var("TARGET").unwrap())
            });
        assert!(
            path.join("libonnxruntime.a").exists(),
            "Pinned iOS runtime missing. Run uv run scripts/fetch-ios-runtime.py first."
        );
        println!("cargo:rustc-link-search=native={}", path.display());
        println!("cargo:rustc-link-lib=static=onnxruntime");
        println!("cargo:rustc-link-lib=c++");
        for framework in ["Accelerate", "CoreML", "Foundation"] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
    }
}
