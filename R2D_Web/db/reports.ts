export type BikeReportRow = {
  id: number;
  category: string;
  severity: string;
  description: string;
  latitude: number;
  longitude: number;
  locationLabel: string;
  source: string;
  status: string;
  officialStatus: string;
  createdAt: number;
};

export type NewBikeReport = Pick<
  BikeReportRow,
  "category" | "severity" | "description" | "latitude" | "longitude" | "locationLabel"
>;

async function database() {
  const { env } = await import("cloudflare:workers");
  if (!env.DB) {
    throw new Error("Cloudflare D1 binding `DB` is unavailable.");
  }
  return env.DB;
}

export async function ensureBikeReportsTable() {
  const db = await database();
  await db.batch([
    db.prepare(`
      CREATE TABLE IF NOT EXISTS bike_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        severity TEXT NOT NULL DEFAULT 'caution',
        description TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        location_label TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'r2d_citizen',
        status TEXT NOT NULL DEFAULT 'received',
        official_status TEXT NOT NULL DEFAULT 'not_submitted',
        created_at INTEGER NOT NULL
      )
    `),
    db.prepare(`
      CREATE INDEX IF NOT EXISTS bike_reports_created_at_idx
      ON bike_reports (created_at)
    `),
  ]);
}

export async function listBikeReports(limit = 100): Promise<BikeReportRow[]> {
  const db = await database();
  const result = await db
    .prepare(`
      SELECT
        id,
        category,
        severity,
        description,
        latitude,
        longitude,
        location_label AS locationLabel,
        source,
        status,
        official_status AS officialStatus,
        created_at AS createdAt
      FROM bike_reports
      ORDER BY created_at DESC
      LIMIT ?
    `)
    .bind(limit)
    .all<BikeReportRow>();

  return result.results;
}

export async function createBikeReport(report: NewBikeReport): Promise<BikeReportRow> {
  const createdAt = Date.now();
  const db = await database();
  const result = await db
    .prepare(`
      INSERT INTO bike_reports (
        category,
        severity,
        description,
        latitude,
        longitude,
        location_label,
        source,
        status,
        official_status,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, 'r2d_citizen', 'received', 'not_submitted', ?)
      RETURNING
        id,
        category,
        severity,
        description,
        latitude,
        longitude,
        location_label AS locationLabel,
        source,
        status,
        official_status AS officialStatus,
        created_at AS createdAt
    `)
    .bind(
      report.category,
      report.severity,
      report.description,
      report.latitude,
      report.longitude,
      report.locationLabel,
      createdAt,
    )
    .first<BikeReportRow>();

  if (!result) throw new Error("제보를 저장하지 못했습니다.");
  return result;
}
