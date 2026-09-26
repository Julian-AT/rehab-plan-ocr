fn main() {
    phonemizer();
    println!("cargo:rerun-if-env-changed=ORT_LIB_LOCATION");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios")
        && std::env::var_os("CARGO_FEATURE_ONNX").is_some()
    {
        let path = std::env::var_os("ORT_LIB_LOCATION")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| {
                std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap())
                    .join("../../../.local/models/runtime/runtime")
                    .join(std::env::var("TARGET").unwrap())
            });
        assert!(
            path.join("libonnxruntime.a").exists(),
            "Pinned iOS runtime missing. Run uv run tooling/build/fetch-ios-runtime.py first."
        );
        println!("cargo:rustc-link-search=native={}", path.display());
        println!("cargo:rustc-link-lib=static=onnxruntime");
        println!("cargo:rustc-link-lib=c++");
        for framework in ["Accelerate", "CoreML", "Foundation"] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
    }
}

fn phonemizer() {
    println!("cargo:rerun-if-env-changed=REHA_ESPEAK_LIB_DIR");
    if std::env::var_os("CARGO_FEATURE_KOKORO").is_none() {
        return;
    }
    let target = std::env::var("TARGET").unwrap();
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../.local/builds/phonemizer");
    let directory = std::env::var_os("REHA_ESPEAK_LIB_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            root.join(if target.contains("ios") {
                &target
            } else {
                "host"
            })
            .join("src/libespeak-ng")
        });
    assert!(
        directory.join("libespeak-ng.a").exists(),
        "Build pinned eSpeak first: python3 tooling/build/build-phonemizer.py"
    );
    println!("cargo:rustc-link-search=native={}", directory.display());
    println!("cargo:rustc-link-lib=static=espeak-ng");
    println!(
        "cargo:rustc-link-search=native={}",
        directory.parent().unwrap().join("ucd-tools").display()
    );
    println!("cargo:rustc-link-lib=static=ucd");
    println!(
        "cargo:rerun-if-changed={}",
        directory.join("libespeak-ng.a").display()
    );
}
