use sha2::{Digest, Sha256};
use std::{env, fs, path::PathBuf, process::Command};

const SOURCES: &[&str] = &[
    "Cargo.toml",
    "Cargo.lock",
    "rust-toolchain.toml",
    "packages/rust/reha-core/Cargo.toml",
    "packages/rust/reha-core/build.rs",
    "packages/rust/reha-core/src/lib.rs",
    "packages/rust/reha-core/src/recognition_input.rs",
    "packages/rust/reha-core/src/ocr.rs",
    "packages/rust/reha-cli/Cargo.toml",
    "packages/rust/reha-cli/build.rs",
    "packages/rust/reha-cli/src/main.rs",
    "packages/rust/reha-cli/src/recognition_fixture.rs",
];

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=RUSTC");
    println!("cargo:rerun-if-env-changed=CARGO_ENCODED_RUSTFLAGS");
    let rustc = env::var_os("RUSTC").expect("Cargo must provide RUSTC");
    let version = Command::new(rustc)
        .args(["--version", "--verbose"])
        .output()
        .expect("Read the compiler identity");
    assert!(version.status.success(), "Compiler identity command failed");
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo must provide OUT_DIR"));
    fs::write(out.join("fixture-rustc.txt"), version.stdout).expect("Store compiler identity");
    let root = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("Cargo manifest directory"))
        .join("../../..");
    let mut hashes = Vec::new();
    for name in SOURCES {
        let path = root.join(name);
        println!("cargo:rerun-if-changed={}", path.display());
        let digest =
            Sha256::digest(fs::read(path).expect("Read build source for fixture identity"));
        // Keys are the fixed ASCII paths above; only digests enter the CLI binary.
        hashes.push(format!("  \"{name}\": \"{digest:x}\""));
    }
    fs::write(
        out.join("fixture-source-hashes.json"),
        format!("{{\n{}\n}}\n", hashes.join(",\n")),
    )
    .expect("Store build source hashes");
    for name in ["TARGET", "HOST", "PROFILE", "OPT_LEVEL", "DEBUG"] {
        println!(
            "cargo:rustc-env=REHA_FIXTURE_{name}={}",
            env::var(name).expect("Cargo build metadata")
        );
    }
    fs::write(
        out.join("fixture-rustflags.txt"),
        env::var("CARGO_ENCODED_RUSTFLAGS").unwrap_or_default(),
    )
    .expect("Store compiler flags");
}
