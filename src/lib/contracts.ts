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
export interface Appointment {
  id: string;
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
  schema_version: number;
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
}
export interface WriteResult {
  id: string;
  status: string;
  external_id: string | null;
  error: string | null;
}
export interface Preferences {
  timezone: string;
  reminder: number | null;
  detailed_debug: boolean;
}
export interface History {
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
export interface Calendar {
  id: string;
  title: string;
  is_default: boolean;
}
export interface Annotation {
  schema_version: number;
  day_id: string;
  document_hashes: string[];
  verified: boolean;
  reviewed_at: string | null;
  split: string;
  appointments: Appointment[];
  uncertainty_notes: string[];
}

export const defaultConfig: Config = {
  engine: "portable-small",
  timezone: "Europe/Vienna",
  detector_side: 1280,
  detector_threshold: 0.3,
  box_threshold: 0.6,
  detailed_debug: false,
  quarter_turns: 0,
  page_corners: null,
};
export const defaultPreferences: Preferences = {
  timezone: "Europe/Vienna",
  reminder: null,
  detailed_debug: false,
};
