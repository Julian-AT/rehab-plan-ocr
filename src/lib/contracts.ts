export interface Point {
  x: number;
  y: number;
}
export interface Region {
  id: string;
  polygon: Point[];
  frame: string;
  kind: string;
  parent: string | null;
  children: string[];
}
export interface Observation {
  id: string;
  text: string;
  region_ids: string[];
  engine: string;
  score: number | null;
  alternatives: string[];
}
export interface Issue {
  code: string;
  message: string;
  field: string | null;
  blocking: boolean;
}
export interface AppointmentMetadata {
  clinic: string;
  department: string;
  address: string;
  contact: string;
  treatment_code: string;
  preparation: string;
  document_reference: string;
  appointment_notes: string;
}
export interface FieldOrigin {
  kind: "printed" | "derived" | "suggested" | "manual";
  evidence: string[];
  source: string;
}
export interface CompletionSuggestion {
  id: string;
  field: string;
  value: string | number;
  source: string;
  status: "pending" | "accepted" | "rejected";
}
export interface CompletionDefault {
  id: string;
  clinic: string;
  treatment: string;
  field: string;
  value: string | number;
}
export interface ScheduleSection {
  id: string;
  date: string | null;
  polygon: Point[];
  heading_ids: string[];
  observation_ids: string[];
  columns: Record<string, number>;
  metadata: AppointmentMetadata;
}
export interface RefinementAttempt {
  id: string;
  target_ids: string[];
  reason: string;
  variant: string;
  crop_to_original: number[];
  crop_to_page: number[];
  width: number;
  height: number;
  duration_ms: number;
  status: string;
  observation_ids: string[];
  detail: string;
}
export interface RefinementReading {
  appointment_id: string;
  field: string;
  value: string | number;
  evidence: string[];
  attempt: string;
}
export const emptyMetadata: AppointmentMetadata = {
  clinic: "",
  department: "",
  address: "",
  contact: "",
  treatment_code: "",
  preparation: "",
  document_reference: "",
  appointment_notes: "",
};
export interface Appointment {
  id: string;
  fields?: Record<string, FieldAssessment>;
  row_polygon?: Point[];
  section_id?: string | null;
  metadata?: AppointmentMetadata;
  origins?: Record<string, FieldOrigin>;
  suggestions?: CompletionSuggestion[];
  approval?: { values_hash: string; approved_at: number } | null;
  calendar_event_id?: string | null;
  ics_event_id?: string | null;
  calendar_saved_hash?: string | null;
  ics_exported_hash?: string | null;
  date: string | null;
  start: string | null;
  end: string | null;
  end_date: string | null;
  duration_minutes: number | null;
  title: string;
  location: string;
  therapist: string;
  notes: string;
  included: boolean;
  provenance: Record<string, string[]>;
  issues: Issue[];
}
export interface Config {
  engine: string;
  timezone: string;
  detector_side: number;
  detector_threshold: number;
  box_threshold: number;
  detailed_debug: boolean;
  quarter_turns: number;
  mirrored?: boolean;
  page_corners: [Point, Point, Point, Point] | null;
}
export interface Stage {
  name: string;
  status: string;
  duration_ms: number;
  detail: string;
  artifacts: string[];
}
export interface Run {
  /** Canonical native revision; never persisted inside the run. */
  revision?: string;
  schema_version: number;
  sections?: ScheduleSection[];
  refinement_attempts?: RefinementAttempt[];
  refinement_readings?: RefinementReading[];
  extraction_version?: number;
  id: string;
  document: {
    id: string;
    source_hash: string;
    filename: string;
    width: number;
    height: number;
    orientation: number;
    imported_at: number;
    source: string;
  };
  config: Config;
  engine: string;
  model_manifest: unknown;
  stages: Stage[];
  regions: Region[];
  observations: Observation[];
  appointments: Appointment[];
  issues: Issue[];
  unassigned: string[];
  original_to_page: number[];
  page_to_original: number[];
  page_width: number;
  page_height: number;
  complete_page_confirmed: boolean;
  review_confirmed: boolean;
  total_ms: number;
  peak_memory_bytes: number | null;
  cache_used: boolean;
}
export interface Values {
  title: string;
  start_utc: string;
  end_utc: string;
  timezone: string;
  location: string;
  notes: string;
  reminder_minutes: number | null;
}
export interface Operation {
  kind: string;
  id: string;
  calendar_id: string;
  external_id: string | null;
  before: Values | null;
  after: Values | null;
  requires_resolution: boolean;
  reason: string;
}
export interface Proposal {
  token: string;
  document_id: string;
  schedule_id: string;
  operations: Operation[];
  protected_event_ids?: string[];
}
export interface WriteResult {
  id: string;
  status: string;
  external_id: string | null;
  error: string | null;
}
export interface Preferences {
  app_reminders_enabled?: boolean;
  app_reminder_minutes?: number | null;
  reminder_sound?: boolean;
  reminder_preview?: boolean;
  appearance?: "system" | "light" | "dark";
  calendar_id?: string;
  completion_defaults?: CompletionDefault[];
  timezone: string;
  reminder: number | null;
  detailed_debug: boolean;
}
export interface History {
  intakes?: {
    id: string;
    filename: string;
    imported_at: number;
    status: string;
    error: string | null;
  }[];
  batches?: ImportBatch[];
  failures?: {
    id: string;
    filename: string;
    started_at: number;
    engine: string;
    error: string;
    internal_stage: string;
  }[];
  pending_details?: [string, Operation][];
  scans: {
    id: string;
    imported_at: number;
    retained: boolean;
    item_count: number;
    pending_count?: number;
    dates?: string[];
    schedule_id: string | null;
  }[];
  imports: {
    id: string;
    schedule_id: string;
    calendar_id: string;
    approved: Values;
    status: string;
  }[];
  pending: number;
}
export interface ImportBatch {
  id: string;
  document_ids: string[];
  created_at: number;
  undo_of: string | null;
  undone_by: string | null;
  operations: {
    attempt_id: string;
    operation: Operation;
    status: string;
    result: WriteResult | null;
  }[];
}
export interface Calendar {
  id: string;
  title: string;
  is_default: boolean;
  source?: string;
}
export interface CalendarConnection {
  calendars: Calendar[];
  dedicated_id?: string;
  setup_error?: string;
}
export interface Annotation {
  input_class?: "rehabilitation_plan" | "non_plan" | "unusable";
  schema_version: number;
  day_id: string;
  document_hashes: string[];
  verified: boolean;
  reviewed_at: string | null;
  split: string;
  appointments: Appointment[];
  uncertainty_notes: string[];
  sources?: ReferenceSource[];
  lines?: ReferenceLine[];
  coverage_confirmed?: boolean;
  content_hash?: string | null;
  approval_hash?: string | null;
}
export type PrintedState =
  | "unreviewed"
  | "legible"
  | "not_printed"
  | "illegible"
  | "cropped"
  | "contradictory";
export interface FieldAssessment {
  state: PrintedState;
  polygon: Point[];
  frame: string;
  reasons: string[];
  confirmed_value: string | number | null;
  confirmed_at: number | null;
}
export interface ReferenceSource {
  source_hash: string;
  original_hash: string;
  logical_page: string;
  capture_series: string;
  treatment_days: string[];
  width: number;
  height: number;
  table_polygon: Point[];
  relationships_confirmed: boolean;
}
export interface ReferenceLine {
  id: string;
  source_hash: string;
  appointment_id: string;
  field: string;
  text: string;
  polygon: Point[];
  state: PrintedState;
  error_causes: string[];
}

export const defaultConfig: Config = {
  engine: "portable-small",
  timezone: "Europe/Vienna",
  detector_side: 1280,
  detector_threshold: 0.3,
  box_threshold: 0.6,
  detailed_debug: false,
  quarter_turns: 0,
  mirrored: false,
  page_corners: null,
};
export const defaultPreferences: Preferences = {
  appearance: "system",
  calendar_id: "",
  completion_defaults: [],
  timezone: "Europe/Vienna",
  reminder: 10,
  app_reminders_enabled: false,
  app_reminder_minutes: 10,
  reminder_sound: true,
  reminder_preview: true,
  detailed_debug: false,
};
