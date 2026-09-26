import { command } from "./native";
import type { Issue, Point, Proposal, WriteResult } from "./contracts";

export interface DraftAssessment {
  revision: string;
  policy_version: number;
  ready_ids: string[];
  unprocessed_page_ids: string[];
  appointments: {
    id: string;
    document_id: string;
    state: "ready" | "attention" | "excluded";
    issues: Issue[];
    warnings: Issue[];
  }[];
  questions: {
    id: string;
    document_id: string;
    appointment_ids: string[];
    field: string;
    message: string;
    polygon: Point[];
  }[];
}
export interface DraftPreview {
  assessment: DraftAssessment;
  proposal: (Proposal & { bindings: Record<string, string> }) | null;
}
export interface SaveOutcome {
  batch_id: string;
  results: WriteResult[];
  existing_ids: string[];
  remaining_ids: string[];
}

/** Preparation has no human-approval or calendar-write effects. */
export function assessDraft(id: string, timezone: string) {
  return command<DraftAssessment>("assess_draft", { id, timezone });
}
export function previewDraft(
  id: string,
  calendarId: string,
  timezone: string,
  reminder: number | null,
) {
  return command<DraftPreview>("preview_draft", {
    id,
    calendarId,
    timezone,
    reminder,
  });
}
export function answerDraftQuestion(
  id: string,
  revision: string,
  questionId: string,
  value: string | number | null,
  timezone: string,
) {
  return command<void>("answer_draft_question", {
    id,
    revision,
    questionId,
    value,
    timezone,
  });
}
/** This user action atomically accepts only the selected, revalidated values. */
export function acceptAndSave(
  token: string,
  selection: string[],
  approveRemovals = false,
) {
  return command<SaveOutcome>("accept_and_save", {
    token,
    selection,
    approveRemovals,
  });
}
export function exportDraftIcs(
  id: string,
  revision: string,
  timezone: string,
  reminder: number | null,
  selection: string[],
) {
  return command<string>("export_draft_ics", {
    id,
    revision,
    timezone,
    reminder,
    selection,
  });
}
