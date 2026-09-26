//! Bounded reads of encoded originals, before decoding or durable staging.
use crate::{Error, Result};
use std::{fs::File, io::Read, path::Path};

pub const MAX_BYTES: usize = 40 * 1024 * 1024;

/// Inspect the opened file, then enforce the same limit on the actual stream.
/// A file growing after metadata inspection must not cause an unbounded read.
/// Empty originals retain the existing validation at staging/decoding.
pub fn read(path: impl AsRef<Path>) -> Result<Vec<u8>> {
    let file = File::open(path)?;
    let size = file.metadata()?.len();
    read_with_size(file, size)
}

fn read_with_size(reader: impl Read, size: u64) -> Result<Vec<u8>> {
    let too_large = || Error::Invalid("Foto maximal 40 MB.".into());
    if size > MAX_BYTES as u64 {
        return Err(too_large());
    }
    let mut bytes = Vec::with_capacity(size as usize);
    // One sentinel byte distinguishes an exact-limit original from overflow.
    reader.take(MAX_BYTES as u64 + 1).read_to_end(&mut bytes)?;
    if bytes.len() > MAX_BYTES {
        return Err(too_large());
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io;

    #[test]
    fn exact_limit_and_empty_input_preserve_bytes() {
        assert!(read_with_size(io::empty(), 0).unwrap().is_empty());
        let bytes =
            read_with_size(io::repeat(37).take(MAX_BYTES as u64), MAX_BYTES as u64).unwrap();
        assert_eq!(bytes.len(), MAX_BYTES);
        assert!(bytes.iter().all(|value| *value == 37));
    }

    #[test]
    fn stale_small_metadata_stops_after_the_overflow_sentinel() {
        struct Counted {
            read: usize,
        }
        impl Read for Counted {
            fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
                // Finite even if a regression accidentally removes the read limit.
                let count = bytes.len().min(MAX_BYTES + 4096 - self.read);
                bytes[..count].fill(37);
                self.read += count;
                Ok(count)
            }
        }
        let mut stream = Counted { read: 0 };
        assert!(matches!(
            read_with_size(&mut stream, 1),
            Err(Error::Invalid(_))
        ));
        assert_eq!(stream.read, MAX_BYTES + 1);
        let mut oversized = Counted { read: 0 };
        assert!(matches!(
            read_with_size(&mut oversized, MAX_BYTES as u64 + 1),
            Err(Error::Invalid(_))
        ));
        assert_eq!(
            oversized.read, 0,
            "Reject known oversized files before reading"
        );
    }

    #[test]
    fn io_failure_is_not_reported_as_an_oversized_photo() {
        struct Broken;
        impl Read for Broken {
            fn read(&mut self, _: &mut [u8]) -> io::Result<usize> {
                Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "controlled failure",
                ))
            }
        }
        assert!(matches!(read_with_size(Broken, 1), Err(Error::Io(error))
            if error.kind() == io::ErrorKind::PermissionDenied));
    }

    #[test]
    fn opened_original_and_sparse_oversized_file_use_the_same_limit() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("original.bin");
        std::fs::write(&path, b"original bytes").unwrap();
        assert_eq!(read(&path).unwrap(), b"original bytes");
        File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_len(MAX_BYTES as u64 + 1)
            .unwrap();
        assert!(matches!(read(&path), Err(Error::Invalid(_))));
        std::fs::remove_file(&path).unwrap();
        assert!(matches!(read(&path), Err(Error::Io(error))
            if error.kind() == io::ErrorKind::NotFound));
    }
}
