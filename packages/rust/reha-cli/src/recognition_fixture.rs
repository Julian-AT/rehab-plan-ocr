//! Host-only fixture output. This command does not load a model or call ONNX.
use reha_core::{
    recognition_input::{self, fixture},
    Error, Result,
};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::Path,
};

// Generated during this CLI's build: no later checkout lookup and no embedded
// source plaintext. Developer fixture IO and identity are excluded from iOS.
const SOURCE_HASHES: &str = include_str!(concat!(env!("OUT_DIR"), "/fixture-source-hashes.json"));

fn read_png(path: &Path) -> Result<Vec<u8>> {
    if !fs::metadata(path)?.is_file() {
        return Err(Error::Invalid(
            "Fixture input must be a regular PNG file.".into(),
        ));
    }
    let file = File::open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() || metadata.len() > fixture::MAX_PNG_BYTES as u64 {
        return Err(Error::Invalid(
            "Fixture input must be a regular PNG file of at most 16 MiB.".into(),
        ));
    }
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.take(fixture::MAX_PNG_BYTES as u64 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > fixture::MAX_PNG_BYTES {
        return Err(Error::Invalid(
            "Fixture input grew beyond the 16 MiB limit.".into(),
        ));
    }
    Ok(bytes)
}

fn write_new(path: &Path, bytes: &[u8]) -> Result<()> {
    let mut file = OpenOptions::new().write(true).create_new(true).open(path)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    Ok(())
}

pub fn write(input: &Path, output: &Path) -> Result<serde_json::Value> {
    let bytes = read_png(input)?;
    let crop = fixture::decode_png(&bytes)?;
    let mut values = Vec::new();
    let (resized_width, padded_width) = recognition_input::append(&crop, &mut values)?;
    // Serialization is host-only. The app appends f32 values directly to its batch.
    let tensor: Vec<u8> = values
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect();
    let executable = std::env::current_exe()?;
    let source_hashes: serde_json::Map<String, serde_json::Value> =
        serde_json::from_str(SOURCE_HASHES)?;
    let manifest = serde_json::json!({
        "schema_version": 1,
        "kind": "native-recognition-input-fixture",
        "complete": true,
        "model_loaded": false,
        "qualified": false,
        "input": {
            "path": input.to_string_lossy(), "sha256": reha_core::hash(&bytes),
            "bytes": bytes.len(), "format": "PNG", "decoded_rgb_shape": [crop.height(), crop.width(), 3]
        },
        "tensor": {
            "file": "tensor.f32le", "sha256": reha_core::hash(&tensor), "bytes": tensor.len(),
            "shape": [1, 3, 48, padded_width], "dtype": "float32", "byte_order": "little",
            "layout": "NCHW", "channels": "BGR", "resized_width": resized_width,
            "padded_width": padded_width, "padding_value": 0.0,
            "interpolation": "image::imageops::FilterType::Triangle",
            "normalization": "(u8 as f32 / 255. - 0.5) / 0.5"
        },
        "producer": {
            "package": env!("CARGO_PKG_NAME"), "version": env!("CARGO_PKG_VERSION"),
            "executable_sha256": fixture::file_sha256(&executable)?,
            "source_sha256": source_hashes,
            "rustc_verbose": include_str!(concat!(env!("OUT_DIR"), "/fixture-rustc.txt")),
            "cargo_encoded_rustflags": include_str!(concat!(env!("OUT_DIR"), "/fixture-rustflags.txt")),
            "target": env!("REHA_FIXTURE_TARGET"), "host": env!("REHA_FIXTURE_HOST"),
            "profile": env!("REHA_FIXTURE_PROFILE"), "opt_level": env!("REHA_FIXTURE_OPT_LEVEL"),
            "debug": env!("REHA_FIXTURE_DEBUG"),
            "features": {"onnx": cfg!(feature = "onnx"), "onnx-download": cfg!(feature = "onnx-download"), "voice": cfg!(feature = "voice")}
        },
        "input_limits": {"encoded_bytes": fixture::MAX_PNG_BYTES, "pixels": fixture::MAX_PIXELS, "side": fixture::MAX_SIDE}
    });
    let mut manifest_bytes = serde_json::to_vec_pretty(&manifest)?;
    manifest_bytes.push(b'\n');
    // Reserve the directory exclusively and write the completion manifest last.
    // A failed write can leave an incomplete directory; it is never overwritten.
    fs::create_dir(output)?;
    write_new(&output.join("tensor.f32le"), &tensor)?;
    write_new(&output.join("manifest.json"), &manifest_bytes)?;
    Ok(manifest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    struct Directory(PathBuf);
    impl Directory {
        fn new() -> Self {
            let path = std::env::temp_dir()
                .join(format!("reha-recognition-fixture-{}", uuid::Uuid::new_v4()));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
    }
    impl Drop for Directory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn input(directory: &Directory) -> PathBuf {
        let path = directory.0.join("input.png");
        fs::write(
            &path,
            include_bytes!("../../../../ml/evaluation/fixtures/synthetic-day.png"),
        )
        .unwrap();
        path
    }

    #[test]
    fn fixture_records_exact_bytes_shape_and_compiled_identity() {
        let directory = Directory::new();
        let input = input(&directory);
        let output = directory.0.join("fixture");
        let manifest = write(&input, &output).unwrap();
        let stored: serde_json::Value =
            serde_json::from_slice(&fs::read(output.join("manifest.json")).unwrap()).unwrap();
        assert_eq!(stored, manifest);
        let bytes = fs::read(output.join("tensor.f32le")).unwrap();
        assert_eq!(manifest["tensor"]["sha256"], reha_core::hash(&bytes));
        assert_eq!(
            bytes.len(),
            4 * 3 * 48 * manifest["tensor"]["padded_width"].as_u64().unwrap() as usize
        );
        assert!(bytes
            .as_chunks::<4>()
            .0
            .iter()
            .all(|b| f32::from_le_bytes(*b).is_finite()));
        let source_hashes = manifest["producer"]["source_sha256"].as_object().unwrap();
        assert!(source_hashes.contains_key("packages/rust/reha-core/src/recognition_input.rs"));
        assert!(source_hashes.contains_key("Cargo.lock"));
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..");
        for (path, digest) in source_hashes {
            assert_eq!(
                *digest,
                reha_core::hash(&fs::read(root.join(path)).unwrap()),
                "{path}"
            );
        }
        assert_eq!(
            manifest["producer"]["executable_sha256"],
            fixture::file_sha256(&std::env::current_exe().unwrap()).unwrap()
        );
        assert_eq!(manifest["model_loaded"], false);
    }

    #[test]
    fn existing_output_is_never_overwritten() {
        let directory = Directory::new();
        let input = input(&directory);
        let output = directory.0.join("fixture");
        fs::create_dir(&output).unwrap();
        let sentinel = output.join("tensor.f32le");
        fs::write(&sentinel, b"keep existing bytes").unwrap();
        assert!(write(&input, &output).is_err());
        assert_eq!(fs::read(sentinel).unwrap(), b"keep existing bytes");
        assert!(!output.join("manifest.json").exists());
    }

    #[test]
    fn invalid_and_oversized_files_create_no_outputs() {
        let directory = Directory::new();
        let input = directory.0.join("invalid.png");
        fs::write(&input, b"not PNG data").unwrap();
        let output = directory.0.join("fixture");
        assert!(write(&input, &output).is_err());
        assert!(!output.exists());
        File::create(&input)
            .unwrap()
            .set_len(fixture::MAX_PNG_BYTES as u64 + 1)
            .unwrap();
        assert!(write(&input, &output).is_err());
        assert!(!output.exists());
    }
}
