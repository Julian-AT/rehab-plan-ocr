use super::Store;
use crate::{contracts::PipelineConfig, Error, Result};
use rusqlite::params;
use serde::{Deserialize, Serialize};
use std::{
    fs::{File, Metadata},
    io::{Read, Write},
    path::Path,
};

fn same_original(before: &Metadata, after: &Metadata) -> std::io::Result<bool> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if before.dev() != after.dev() || before.ino() != after.ino() {
            return Ok(false);
        }
    }
    Ok(after.is_file() && before.len() == after.len() && before.modified()? == after.modified()?)
}

/// A successful restaging acknowledges the durable bytes and lets the caller
/// remove its temporary copy. Verify the original itself, with bounded reads,
/// before issuing that acknowledgement. Never repair an existing corrupt file
/// by silently overwriting the immutable capture.
fn retained_original(path: &Path, expected: &[u8]) -> Result<bool> {
    let before = match std::fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    let changed = || {
        Error::Invalid(
            "Gespeichertes Original ist beschädigt oder verändert. Neue Aufnahme bleibt erhalten."
                .into(),
        )
    };
    if !before.is_file() || before.len() != expected.len() as u64 {
        return Err(changed());
    }
    let mut file = File::open(path)?;
    if !same_original(&before, &file.metadata()?)? {
        return Err(changed());
    }
    let mut buffer = [0; 64 * 1024];
    for chunk in expected.chunks(buffer.len()) {
        file.read_exact(&mut buffer[..chunk.len()])?;
        if &buffer[..chunk.len()] != chunk {
            return Err(changed());
        }
    }
    if file.read(&mut buffer[..1])? != 0
        || !same_original(&before, &file.metadata()?)?
        || !same_original(&before, &std::fs::symlink_metadata(path)?)?
    {
        return Err(changed());
    }
    Ok(true)
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Intake {
    pub id: String,
    pub source_hash: String,
    pub filename: String,
    pub imported_at: i64,
    pub config: PipelineConfig,
    pub status: String,
    pub error: Option<String>,
}
impl Store {
    /// The original is immutable and synced before acknowledging capture storage.
    /// Pipeline artifacts may be replaced; intake.bin must never be overwritten.
    pub fn stage_intake(
        &self,
        id: &str,
        filename: &str,
        bytes: &[u8],
        config: &PipelineConfig,
        now: i64,
    ) -> Result<Intake> {
        let dir = self.scan_dir(id)?;
        if bytes.is_empty() || bytes.len() > crate::photo_source::MAX_BYTES {
            return Err(Error::Invalid(
                "Foto ist leer oder größer als 40 MB.".into(),
            ));
        }
        let hash = crate::hash(bytes);
        if let Some(old) = self.intakes()?.into_iter().find(|v| v.id == id) {
            if old.source_hash != hash || old.status == "deleted" {
                return Err(Error::Invalid("Aufnahme-ID wird bereits verwendet.".into()));
            }
            if retained_original(&dir.join("intake.bin"), bytes)? {
                if self.setting(&format!("document:{id}"))?.is_none() {
                    self.ensure_page(id, old.imported_at)?;
                }
                return Ok(old);
            }
        }
        std::fs::create_dir_all(&dir)?;
        self.connection.execute("INSERT INTO intakes VALUES(?1,?2,?3,?4,?5,'receiving',NULL) ON CONFLICT(id) DO NOTHING",
            params![id, hash, filename, now, serde_json::to_string(config)?])?;
        let temp = dir.join("intake.part");
        let mut file = File::create(&temp)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        std::fs::rename(&temp, dir.join("intake.bin"))?;
        File::open(&dir)?.sync_all()?;
        File::open(
            dir.parent()
                .ok_or_else(|| Error::Invalid("Aufnahmeverzeichnis fehlt.".into()))?,
        )?
        .sync_all()?;
        self.intake_status(id, "stored", None)?;
        self.ensure_page(id, now)?;
        self.intakes()?
            .into_iter()
            .find(|v| v.id == id)
            .ok_or_else(|| Error::Invalid("Aufnahme fehlt.".into()))
    }
    pub fn intakes(&self) -> Result<Vec<Intake>> {
        let mut q = self.connection.prepare("SELECT id,source_hash,filename,imported_at,config,status,error FROM intakes ORDER BY imported_at DESC,id")?;
        let rows = q.query_map([], |r| {
            Ok((
                r.get(0)?,
                r.get(1)?,
                r.get(2)?,
                r.get(3)?,
                r.get::<_, String>(4)?,
                r.get(5)?,
                r.get(6)?,
            ))
        })?;
        rows.map(|r| {
            let (id, source_hash, filename, imported_at, config, status, error) = r?;
            Ok(Intake {
                id,
                source_hash,
                filename,
                imported_at,
                config: serde_json::from_str(&config)?,
                status,
                error,
            })
        })
        .collect()
    }
    pub fn intake_status(&self, id: &str, status: &str, error: Option<&str>) -> Result<()> {
        self.connection.execute(
            "UPDATE intakes SET status=?2,error=?3 WHERE id=?1 AND status!='deleted'",
            params![id, status, error],
        )?;
        Ok(())
    }
    pub(super) fn recover_intakes(&self) -> Result<()> {
        self.connection.execute("UPDATE processing_attempts SET status='interrupted',error='Verarbeitung unterbrochen' WHERE status='processing'", [])?;
        for intake in self.intakes()? {
            // A crash may occur after the atomic original rename but before the
            // archive index is inserted. Rebuild only ordinary page membership;
            // a PDF original is a parent, not an extra rendered page.
            if intake.status != "deleted"
                && self.setting(&format!("document:{}", intake.id))?.is_none()
            {
                self.ensure_page(&intake.id, intake.imported_at)?;
            }
            if ["receiving", "processing"].contains(&intake.status.as_str()) {
                let retained = self.scan_dir(&intake.id)?.join("intake.bin").is_file();
                self.intake_status(
                    &intake.id,
                    "interrupted",
                    Some(if retained {
                        "Verarbeitung unterbrochen. Original gespeichert; erneut versuchen."
                    } else {
                        "Aufnahme wurde vor dem Speichern unterbrochen."
                    }),
                )?;
            }
        }
        Ok(())
    }
    pub fn source_path(&self, id: &str) -> Result<std::path::PathBuf> {
        let dir = self.scan_dir(id)?;
        let original = dir.join("intake.bin");
        Ok(if original.is_file() {
            original
        } else {
            dir.join("source.bin")
        })
    }
}
