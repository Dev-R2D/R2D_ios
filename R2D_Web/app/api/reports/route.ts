import {
  createBikeReport,
  ensureBikeReportsTable,
  listBikeReports,
  type NewBikeReport,
} from "../../../db/reports";

const allowedCategories = new Set([
  "missing",
  "step",
  "damage",
  "pothole",
  "wear",
  "joint_gap",
  "heave",
  "drainage",
  "tactile_block",
  "utility_cover",
  "unknown",
]);
const allowedSeverities = new Set(["caution", "urgent"]);
const allowedOfficialSources = new Set(["seoul_eungdapso", "hwaseong_epetition", "safety_report", "official_partner"]);

function cleanText(value: unknown, maxLength: number) {
  if (typeof value !== "string") return "";
  return value.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, maxLength);
}

function isKoreaCoordinate(latitude: number, longitude: number) {
  return latitude >= 33 && latitude <= 39 && longitude >= 124 && longitude <= 132;
}

function stableExternalId(value: string) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return -Math.max(1, hash >>> 0);
}

async function loadMunicipalFeed() {
  const { env } = await import("cloudflare:workers");
  const bindings = env as typeof env & {
    MUNICIPAL_REPORT_FEED_URL?: string;
    MUNICIPAL_REPORT_FEED_TOKEN?: string;
  };
  const feedUrl = bindings.MUNICIPAL_REPORT_FEED_URL;
  if (!feedUrl) return { reports: [], status: "not_configured" as const };

  try {
    const response = await fetch(feedUrl, {
      headers: bindings.MUNICIPAL_REPORT_FEED_TOKEN
        ? { Authorization: `Bearer ${bindings.MUNICIPAL_REPORT_FEED_TOKEN}` }
        : undefined,
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) throw new Error(`Municipal feed returned ${response.status}`);
    const payload = await response.json() as { reports?: Array<Record<string, unknown>> };
    const reports = (Array.isArray(payload.reports) ? payload.reports : [])
      .slice(0, 500)
      .flatMap((item) => {
        const externalId = cleanText(item.externalId, 80);
        const category = cleanText(item.category, 24);
        const severity = cleanText(item.severity, 16);
        const description = cleanText(item.description, 240);
        const locationLabel = cleanText(item.locationLabel, 80);
        const source = cleanText(item.source, 32);
        const status = cleanText(item.status, 24) || "received";
        const officialStatus = cleanText(item.officialStatus, 24) || "submitted";
        const latitude = Number(item.latitude);
        const longitude = Number(item.longitude);
        const createdAt = Number(item.createdAt);
        if (
          !externalId
          || !allowedCategories.has(category)
          || !allowedSeverities.has(severity)
          || !allowedOfficialSources.has(source)
          || description.length < 2
          || !Number.isFinite(createdAt)
          || !Number.isFinite(latitude)
          || !Number.isFinite(longitude)
          || !isKoreaCoordinate(latitude, longitude)
        ) return [];
        return [{
          id: stableExternalId(`${source}:${externalId}`),
          category,
          severity,
          description,
          latitude,
          longitude,
          locationLabel,
          source,
          status,
          officialStatus,
          createdAt,
        }];
      });
    return { reports, status: "connected" as const };
  } catch (error) {
    console.error("Failed to load municipal report feed", error);
    return { reports: [], status: "error" as const };
  }
}

export async function GET() {
  try {
    await ensureBikeReportsTable();
    const [r2dReports, municipalFeed] = await Promise.all([listBikeReports(), loadMunicipalFeed()]);
    const reports = [...municipalFeed.reports, ...r2dReports]
      .sort((left, right) => right.createdAt - left.createdAt)
      .slice(0, 500);
    return Response.json(
      {
        reports,
        updatedAt: Date.now(),
        refreshSeconds: 15,
        municipalFeed: { status: municipalFeed.status, count: municipalFeed.reports.length },
      },
      { headers: { "Cache-Control": "no-store, max-age=0" } },
    );
  } catch (error) {
    console.error("Failed to list bike reports", error);
    return Response.json(
      { reports: [], error: "제보 목록을 불러오지 못했습니다." },
      { status: 503, headers: { "Cache-Control": "no-store, max-age=0" } },
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as Record<string, unknown>;
    const category = cleanText(body.category, 24);
    const severity = cleanText(body.severity, 16);
    const description = cleanText(body.description, 2000);
    const locationLabel = cleanText(body.locationLabel, 80);
    const latitude = Number(body.latitude);
    const longitude = Number(body.longitude);

    if (!allowedCategories.has(category) || !allowedSeverities.has(severity)) {
      return Response.json({ error: "제보 유형 또는 심각도를 확인해 주세요." }, { status: 400 });
    }
    if (description.length < 5) {
      return Response.json({ error: "현장 상황을 5자 이상 적어 주세요." }, { status: 400 });
    }
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || !isKoreaCoordinate(latitude, longitude)) {
      return Response.json({ error: "대한민국 내의 올바른 위도·경도를 입력해 주세요." }, { status: 400 });
    }

    const report: NewBikeReport = {
      category,
      severity,
      description,
      latitude,
      longitude,
      locationLabel,
    };

    await ensureBikeReportsTable();
    const saved = await createBikeReport(report);
    return Response.json(
      { report: saved },
      { status: 201, headers: { "Cache-Control": "no-store, max-age=0" } },
    );
  } catch (error) {
    console.error("Failed to create bike report", error);
    return Response.json({ error: "제보를 저장하지 못했습니다. 잠시 후 다시 시도해 주세요." }, { status: 500 });
  }
}
