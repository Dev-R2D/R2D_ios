import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(
    new Request("http://localhost/", { headers: { accept: "text/html", host: "localhost" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("server-renders the R2D first impression", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /R2D/);
  assert.match(html, /ROAD TO DATA/);
  assert.match(html, /Google로 계속하기/);
  assert.match(html, /Road to Data/);
  assert.match(html, /og-road-to-data\.png/);
  assert.doesNotMatch(html, /RoadPulse GO|codex-preview|react-loading-skeleton/);
});

test("contains the complete jury demo loop", async () => {
  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
  const required = [
    "당신의 도시는",
    "위치 항상 허용",
    "거치 캘리브레이션",
    "첫 탐사 팩",
    "애스팔트 와이번",
    "가장 빨리 깎는 경로",
    "길게 눌러 종료",
    "과속방지턱으로 판정",
    "총 데미지",
    "골드 팩 획득",
    "오늘의 탐사",
    "시그니처 카드",
    "지역 리그",
    "신리천",
    "당신이 처음 발견한",
    "우연히 들어온 스파이크",
    "활성 인원 보정",
    "케이던스 PSD",
    "D+1 이상치 검수",
    "궤적 편차",
  ];

  for (const copy of required) assert.ok(page.includes(copy), `missing required copy: ${copy}`);
  assert.match(page, /navigator\.share/);
  assert.match(page, /AudioContext/);
  assert.match(page, /onPointerDown/);
});

test("keeps conservative sensor rules and project social art", async () => {
  const [rules, gameplay, manifest, og] = await Promise.all([
    readFile(new URL("../app/sensor-rules.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/game-rules.ts", import.meta.url), "utf8"),
    readFile(new URL("../public/manifest.webmanifest", import.meta.url), "utf8"),
    stat(new URL("../public/og-road-to-data.png", import.meta.url)),
  ]);

  assert.match(rules, /analysisWindowSeconds:\s*4/);
  assert.match(rules, /speedReferenceMps:\s*5/);
  assert.match(rules, /speedCorrectionExponent:\s*1\.15/);
  assert.match(rules, /highImpactReviewMps2:\s*8/);
  assert.match(gameplay, /enum CellStatus/);
  assert.match(gameplay, /calculateRegionalBossHealth/);
  assert.match(gameplay, /evaluateMinionPass/);
  assert.match(gameplay, /useForVerification/);
  assert.match(gameplay, /rewardMileage = input\.spikeDetected && input\.missionActive \? 60 : 0/);
  assert.match(gameplay, /isRepairConfirmed/);
  assert.match(gameplay, /detectCyclingCadence/);
  assert.match(gameplay, /available: "D\+1"/);
  assert.match(gameplay, /localStorage\.setItem/);
  assert.equal(JSON.parse(manifest).short_name, "R2D");
  assert.equal(JSON.parse(manifest).name, "R2D — Road to Data");
  assert.ok(og.size > 100_000);
});
