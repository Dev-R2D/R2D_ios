import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("server-renders the R2D dashboard, map, and municipal report composer", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>R2D \| 실시간 도로 노면 관제<\/title>/i);
  assert.match(html, /property="og:image"/i);
  assert.match(html, /\/og\.png/);
  assert.match(html, /도로 상태를 한눈에/);
  assert.match(html, /현장 대응을 빠르게/);
  assert.doesNotMatch(html, /한강 자전거도로의/);
  assert.doesNotMatch(html, /실제 데이터 분석/);
  assert.doesNotMatch(html, /2026\.07\.17 · 잠원한강공원/);
  assert.match(html, /통합 도로 관제/);
  assert.match(html, /전체 관제 지도/);
  assert.match(html, /선택 구간 3D/);
  assert.match(html, /영상 확인 이벤트 후보/);
  assert.match(html, /센서 단독 이벤트 후보/);
  assert.match(html, /9(?:<!-- -->)?개 포함/);
  assert.match(html, /영상과 동기화된 노면 상태/);
  assert.match(html, /충격 전후 20초/);
  assert.match(html, /충격 전 1\.5초부터 재생/);
  assert.match(html, /이벤트 전후 약 3초/);
  assert.match(html, /latest-capture\/events\/event-01\.mp4/);
  assert.doesNotMatch(html, /DATA CONFIDENCE|RESEARCH TRANSFER|PRECISION MAP READINESS|PLAIN-LANGUAGE GLOSSARY|GPS FOUND/);
  assert.match(html, /MUNICIPAL ROAD OPERATIONS/);
  assert.match(html, /MUNICIPAL REPORT QUEUE/);
  assert.match(html, /노면 신호·충격·시민 제보를/);
  assert.match(html, /전체 경로와 현장 이슈/);
  assert.match(html, /잠원한강공원 실측 기록/);
  assert.match(html, /동탄 1차 실측 기록/);
  assert.match(html, /동탄 2차 실측 기록/);
  assert.match(html, /새 데이터는 이 지도에 누적/);
  assert.match(html, /지도에서 색상 구간을 누르면 이 관제 패널/);
  assert.match(html, /최신 실측 요약과 센서 신호/);
  assert.doesNotMatch(html, /1차·2차 측정 비교/);
  assert.doesNotMatch(html, /1차 시작 테스트/);
  assert.match(html, /화성시 동탄구 여울동 부근/);
  assert.doesNotMatch(html, /동탄 2차 실측 위치와 센서 신호|전체 경로 확인됨/);
  assert.match(html, /가속도.*147,795.*자이로.*147,796/s);
  assert.match(html, /주행거리/);
  assert.doesNotMatch(html, /센서와 직접 동기화된 실사 영상/);
  assert.doesNotMatch(html, /SYNCHRONIZED SENSOR VIDEO/);
  assert.match(html, /센서 주행, 충격 이벤트와 현장 제보를 한 지도에서 확인/);
  assert.doesNotMatch(html, /이전 주행 기록 — 잠원한강공원/);
  assert.doesNotMatch(html, /PREVIOUS GPS TRACE \/ NOT DONGTAN/);
  assert.match(html, /R2D-260809-123507/);
  assert.doesNotMatch(html, /latest-capture\/representative-preview\.mp4/);
  assert.doesNotMatch(html, /secondary-camera-preview/);
  assert.match(html, /latest-capture\/latest-capture-summary\.csv/);
  assert.match(html, /latest-capture\/dongtan-route-scores\.csv/);
  assert.doesNotMatch(html, /R2D-260809-123451-D1|영상 없음 · 센서 단독 분석|dongtan-first\/dongtan-first-route-scores\.csv/);
  assert.match(html, /공무원용 민원·현장제보/);
  assert.match(html, /사진으로 민원서 자동작성/);
  assert.match(html, /사진은 현재 브라우저에서 미리보기와 GPS 확인에만 사용/);
  assert.match(html, /동탄구청 안전건설과 도로관리팀/);
  assert.match(html, /민원 초안 복사/);
  assert.match(html, /R2D 저장 \+ 국민신문고 접수창 열기/);
  assert.match(html, /기관 로그인·본인확인·사진 첨부·최종 제출/);
  assert.doesNotMatch(html, /공식 민원 아님|현재 영상 프레임을 기준으로 한 카메라 장착 교정/);
  assert.match(html, /처음 불러오는 중/);
  assert.match(html, /공식 민원 채널/);
  assert.match(html, /서울시 응답소/);
  assert.match(html, /국민신문고/);
  assert.match(html, /기관 API 승인 후 지도에 연결/);
  assert.doesNotMatch(html, /현재 분석에 실제로 반영한 참고 논문 전체|Urban road pavements monitoring and assessment using bike and e-scooter as probe vehicles/);
  assert.doesNotMatch(html, /Your site is taking shape|Building your site/);
});

test("keeps the merged map, report handoff, 3D interaction, and responsive styling in source", async () => {
  const [page, roadContextMap, immersiveMap, unifiedMap, municipalComposer, roadDatasets, reportRoute, schema, css] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/RoadContext3DMap.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/ImmersiveRouteMap.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/UnifiedRideMap.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/MunicipalReportComposer.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/road-datasets.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/reports/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../db/schema.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
  ]);

  assert.match(page, /function RoadTwin3D/);
  assert.match(page, /function RouteMap/);
  assert.match(page, /https:\/\/tile\.openstreetmap\.org\/\{z\}\/\{x\}\/\{y\}\.png/);
  assert.match(page, /지도 구간 확대/);
  assert.match(page, /지도 확대 구간 이동/);
  assert.match(page, /segment\.on\("click", \(\) => onSelect\(index\)\)/);
  assert.match(page, /onPointerMove=\{pointerMove\}/);
  assert.match(page, /addEventListener\("wheel", handleWheel, \{ passive: false \}\)/);
  assert.match(page, /event\.preventDefault\(\)/);
  assert.match(page, /event\.stopPropagation\(\)/);
  assert.doesNotMatch(page, /onWheel=\{zoomByWheel\}/);
  assert.match(page, /시점 자동변경 없음/);
  assert.doesNotMatch(page, /requestAnimationFrame\(orbit\)/);
  assert.match(page, /max="359"/);
  assert.match(page, /카메라 기울기/);
  assert.match(page, /굴곡 측면 보기/);
  assert.match(page, /\[cameraZoom, setCameraZoom\] = useState\(1\.35\)/);
  assert.match(page, /IMU 상대 추정/);
  assert.match(page, /실측 높이 아님/);
  assert.match(page, /3D 도로 구간 확대/);
  assert.match(page, /확대 구간 이동/);
  assert.match(page, /<UnifiedRideMap/);
  assert.match(page, /<RoadContext3DMap/);
  assert.doesNotMatch(page, /<ImmersiveRouteMap/);
  assert.match(page, /useState<RoadDataset\["id"\]>\("dongtan-2"\)/);
  assert.match(page, /dataset=\{selectedRoadDataset\}/);
  assert.match(unifiedMap, /roadDatasets\.forEach/);
  assert.match(unifiedMap, /liveReports\.forEach/);
  assert.match(unifiedMap, /marker\.bindPopup/);
  assert.match(unifiedMap, /reportSourceLabel/);
  assert.match(unifiedMap, /segment\.on\("click"/);
  assert.match(unifiedMap, /onOpen3D\(\)/);
  assert.match(unifiedMap, /dataset\.events\.forEach/);
  assert.match(unifiedMap, /영상 확인 후보/);
  assert.match(unifiedMap, /센서 단독 후보/);
  assert.match(unifiedMap, /fitDataset\("all"\)/);
  assert.match(municipalComposer, /extractJpegGps/);
  assert.match(municipalComposer, /resolveAuthority/);
  assert.match(municipalComposer, /navigator\.clipboard\.writeText/);
  assert.match(municipalComposer, /window\.open\(authority\.portalUrl/);
  assert.match(municipalComposer, /공인 IRI·PCI 또는 파손 확정 판정이 아닙니다/);
  assert.match(reportRoute, /cleanText\(body\.description, 2000\)/);
  assert.match(roadDatasets, /id: "jamwon"/);
  assert.match(roadDatasets, /id: "dongtan-1"/);
  assert.match(roadDatasets, /id: "dongtan-2"/);
  assert.match(roadDatasets, /dongtanFirstCapture\.location/);
  assert.match(roadDatasets, /latestCapture\.location/);
  assert.match(page, /zoomLevels = \[1, 2, 4, 8, 16\]/);
  assert.match(page, /\[zoomLevel, setZoomLevel\] = useState\(4\)/);
  assert.match(page, /충격 전 1\.5초부터 재생/);
  assert.match(page, /selectedEvent\.clip/);
  assert.doesNotMatch(page, /kakaoRoadViewUrl|kakaoMapUrl/);
  assert.match(page, /LiDAR 포인트의 반사강도/);
  assert.match(page, /function EventConditionGraph/);
  assert.match(page, /onTimeUpdate=\{\(event\) =>/);
  assert.match(page, /흰 선은 영상 현재 시점/);
  assert.match(page, /원본 MOV로 확인/);
  assert.doesNotMatch(page, /const selectedLabel/);
  assert.doesNotMatch(page, /const selectedTop/);
  assert.match(page, /추정 굴곡 강조/);
  assert.match(page, /roadSource = routeSlice/);
  assert.match(page, /GPS 실제 도로 선형/);
  assert.match(page, /강한 진동 감지·영상 확인 필요 구간/);
  assert.match(page, /카메라 보정이 된 스테레오 영상이나 LiDAR·RTK/);
  assert.match(page, /색·표면 굴곡/);
  assert.match(page, /Math\.pow\(5 \/ datum\.speed, 1\.15\)/);
  assert.match(page, /normalizedRms > 8/);
  assert.match(page, /영상 검토: 4초 · 유지관리: 10m/);
  assert.match(immersiveMap, /maplibre-gl/);
  assert.match(immersiveMap, /3d-buildings/);
  assert.match(immersiveMap, /fill-extrusion/);
  assert.match(immersiveMap, /terrain-tiles\/tiles\.json/);
  assert.match(immersiveMap, /tiles\.openfreemap\.org\/planet/);
  assert.match(immersiveMap, /정북 3D/);
  assert.match(immersiveMap, /changePitch/);
  assert.match(immersiveMap, /changeBearing/);
  assert.match(immersiveMap, /fitCurrentSection/);
  assert.match(immersiveMap, /map\.flyTo/);
  assert.match(immersiveMap, /route-direction-arrows/);
  assert.match(immersiveMap, /api\.vworld\.kr\/req\/wmts/);
  assert.match(immersiveMap, /<KakaoRoadview/);
  assert.match(immersiveMap, /live-civic-reports-circle/);
  assert.match(roadContextMap, /3d-buildings/);
  assert.match(roadContextMap, /mapped-green-areas/);
  assert.match(roadContextMap, /terrain-tiles\/tiles\.json/);
  assert.match(roadContextMap, /api\.vworld\.kr\/req\/wmts/);
  assert.match(roadContextMap, /context-score-segments-line/);
  assert.match(roadContextMap, /context-road-surface/);
  assert.match(roadContextMap, /context-road-surface-extrusion/);
  assert.match(roadContextMap, /"fill-extrusion-height": \["get", "height"\]/);
  assert.match(roadContextMap, /function roadSegmentPolygon/);
  assert.match(roadContextMap, /\[roadWidth, setRoadWidth\] = useState\(4\)/);
  assert.match(roadContextMap, /\[reliefScale, setReliefScale\] = useState\(9\)/);
  assert.match(roadContextMap, /LiDAR·수준측량 실측 형상 아님/);
  assert.match(page, /setInterval\(\(\) => void loadLiveReports\(\), 15_000\)/);
  assert.match(page, /function LatestSignalChart/);
  assert.match(page, /latestCapture\.video\.syncNote/);
  assert.match(page, /function LatestCaptureMap/);
  assert.match(page, /MEASURED GPS \+ IMU \+ VIDEO \/ DONGTAN RIDE 02/);
  assert.match(page, /주행 내 상대 노면 점수/);
  assert.match(page, /selectedEvent\.clip/);
  assert.match(page, /latestCapture\.events\.forEach/);
  assert.doesNotMatch(page, /FirstCaptureSignalChart/);
  assert.match(page, /dongtanFirstCapture\.metadata\.durationSec/);
  assert.match(page, /개별 민원 좌표·처리상태는 기관 API 승인 후 지도에 연결/);
  assert.match(page, /liveReports=\{liveReports\}/);
  assert.match(page, /reportStatusLabel/);
  assert.match(reportRoute, /export async function POST/);
  assert.match(reportRoute, /MUNICIPAL_REPORT_FEED_URL/);
  assert.match(reportRoute, /loadMunicipalFeed/);
  assert.match(reportRoute, /allowedOfficialSources/);
  assert.match(reportRoute, /isKoreaCoordinate/);
  assert.match(schema, /sqliteTable\(\s*"bike_reports"/);
  assert.match(css, /\.twin-layout/);
  assert.match(css, /\.twin-view-actions/);
  assert.match(css, /\.paper-transfer-grid/);
  assert.match(css, /\.actual-map/);
  assert.match(css, /\.latest-map-card/);
  assert.match(css, /\.operations-kpis/);
  assert.match(css, /\.municipal-integration-board/);
  assert.match(css, /\.official-channel-bar/);
  assert.match(css, /\.latest-map-metrics/);
  assert.match(css, /\.merged-actual-map/);
  assert.match(css, /\.merged-selection/);
  assert.match(css, /\.map-3d-status/);
  assert.match(css, /\.map-camera-toolbar/);
  assert.match(css, /\.map-zoom-actions/);
  assert.match(css, /\.twin-explanation-grid/);
  assert.match(css, /\.road-context-map/);
  assert.match(css, /\.road-surface-controls/);
  assert.match(css, /Readability pass/);
  assert.match(css, /--muted:\s*#a8bbb6/);
  assert.match(css, /:focus-visible/);
  assert.match(css, /\.map-3d-status span \{ font-size:\s*12px/);
  assert.match(css, /\.report-form-fields input, \.report-form-fields select, \.report-form-fields textarea \{ min-height:\s*44px; font-size:\s*14px/);
  assert.match(css, /\.research-reference-list/);
  assert.match(css, /\.event-condition-canvas/);
  assert.match(css, /\.kakao-roadview-card/);
  assert.match(css, /\.glossary-grid/);
  assert.match(css, /touch-action:\s*none/);
  assert.match(css, /@media \(max-width:\s*680px\)/);
});

test("ships the full Dongtan route and event media", async () => {
  const [poster, eventFrame, eventClip, summary, route] = await Promise.all([
    stat(new URL("../public/latest-capture/preview-synced.jpg", import.meta.url)),
    stat(new URL("../public/latest-capture/events/event-01.jpg", import.meta.url)),
    stat(new URL("../public/latest-capture/events/event-01.mp4", import.meta.url)),
    readFile(new URL("../public/latest-capture/latest-capture-summary.csv", import.meta.url), "utf8"),
    readFile(new URL("../public/latest-capture/dongtan-route-scores.csv", import.meta.url), "utf8"),
  ]);

  assert.ok(poster.size > 10_000);
  assert.ok(eventFrame.size > 10_000);
  assert.ok(eventClip.size > 100_000);
  assert.match(summary, /start,end,time,latitude,longitude/);
  assert.match(route, /seconds_elapsed,latitude,longitude,horizontalAccuracy,speed,score,eligible/);
});

test("ships the full sensor-only Dongtan first dataset", async () => {
  const [summary, route, geojson, socialPreview] = await Promise.all([
    readFile(new URL("../public/dongtan-first/dongtan-first-summary.csv", import.meta.url), "utf8"),
    readFile(new URL("../public/dongtan-first/dongtan-first-route-scores.csv", import.meta.url), "utf8"),
    readFile(new URL("../public/dongtan-first/dongtan-first-route.geojson", import.meta.url), "utf8"),
    stat(new URL("../public/og.png", import.meta.url)),
  ]);

  assert.match(summary, /start,end,time,latitude,longitude/);
  assert.match(route, /seconds_elapsed,latitude,longitude,horizontalAccuracy,speed,score,eligible/);
  assert.match(geojson, /"LineString"/);
  assert.ok(socialPreview.size > 100_000);
});
