use super::Store;
use crate::{service::events::EventProposal, Result};
use rusqlite::params;
use serde_json::{json, Value};
impl Store {
    pub fn event_history(&self) -> Result<Vec<Value>> {
        let mut q = self.connection.prepare("SELECT id,created_at,proposal,status,result,undo_of,(SELECT id FROM event_mutations u WHERE u.undo_of=m.id AND u.status IN ('pending','uncertain','saved','acknowledged')) FROM event_mutations m ORDER BY created_at DESC,rowid DESC")?;
        let rows = q.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, Option<String>>(4)?,
                r.get::<_, Option<String>>(5)?,
                r.get::<_, Option<String>>(6)?,
            ))
        })?;
        rows.map(|row| { let (id,at,proposal,status,result,undo_of,undone_by)=row?;
            Ok(json!({"id":id,"created_at":at,"proposal":serde_json::from_str::<Value>(&proposal)?,"status":status,"result":result.map(|s|serde_json::from_str::<Value>(&s)).transpose()?,"undo_of":undo_of,"undone_by":undone_by}))
        }).collect()
    }
    pub fn begin_event_mutation(&self, proposal: &EventProposal) -> Result<()> {
        self.connection.execute("INSERT INTO event_mutations(id,created_at,proposal,status,undo_of) VALUES(?1,?2,?3,'pending',?4)", params![proposal.token,chrono::Utc::now().timestamp(),serde_json::to_string(proposal)?,proposal.undo_of])?;
        Ok(())
    }
    pub fn finish_event_mutation(&self, id: &str, result: &Value) -> Result<()> {
        self.connection.execute(
            "UPDATE event_mutations SET status=?2,result=?3 WHERE id=?1",
            params![
                id,
                result["status"].as_str().unwrap_or("uncertain"),
                result.to_string()
            ],
        )?;
        Ok(())
    }
}
