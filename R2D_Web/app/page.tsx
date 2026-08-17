"use client";

import { ChangeEvent, CSSProperties, MouseEvent as ReactMouseEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import rideData from "./data/ride-data.json";
import dongtanFirstCapture from "./data/dongtan-first-capture.json";
import latestCapture from "./data/latest-capture.json";
import RoadContext3DMap from "./RoadContext3DMap";
import UnifiedRideMap from "./UnifiedRideMap";
import MunicipalReportComposer from "./MunicipalReportComposer";
import { getRoadDataset, roadDatasets, type RoadDataset } from "./road-datasets";

type EventDatum = (typeof rideData.events)[number];
type LatestCaptureEvent = (typeof latestCapture.events)[number];
type LiveReport = {
  id: number;
  category: string;
  severity: "caution" | "urgent";
  description: string;
  latitude: number;
  longitude: number;
  locationLabel: string;
  source: string;
  status: string;
  officialStatus: string;
  createdAt: number;
};

const reportCategoryLabel: Record<string, string> = {
  missing: "탈락",
  step: "단차",
  damage: "파손",
  pothole: "포트홀",
  wear: "마모",
  joint_gap: "줄눈벌어짐",
  heave: "융기",
  drainage: "배수시설",
  tactile_block: "점자블록",
  utility_cover: "시설물커버",
  unknown: "판단불가",
};

function reportSourceLabel(source: string) {
  if (source === "seoul_eungdapso") return "서울시 응답소";
  if (source === "hwaseong_epetition") return "화성시·국민신문고";
  if (source === "safety_report") return "안전신문고";
  return "R2D 시민 제보";
}

function reportStatusLabel(status: string, officialStatus: string) {
  if (officialStatus === "completed" || status === "completed") return "조치 완료";
  if (officialStatus === "submitted") return "기관 접수";
  if (status === "confirmed") return "현장 확인";
  return "접수·확인 대기";
}

const gradeLabel: Record<string, string> = {
  good: "양호",
  fair: "보통",
  caution: "주의",
  poor: "집중 확인",
};

const gradeColor: Record<string, string> = {
  good: "#27d7ad",
  fair: "#b8dd50",
  caution: "#f6b84b",
  poor: "#ff6b66",
};

const glossary = [
  ["GNSS", "GPS를 포함해 여러 위성항법 시스템으로 위치를 구하는 기술"],
  ["RTK", "인터넷 보정값을 실시간으로 받아 GNSS 위치 오차를 센티미터 수준까지 줄이는 방식"],
  ["PPK", "주행이 끝난 뒤 로버와 기준국 로그를 계산해 위치를 보정하는 방식"],
  ["NTRIP", "기준국의 GNSS 보정정보를 휴대전화 인터넷으로 로버에 전달하는 통신 방식"],
  ["로버", "자전거에 달고 움직이면서 위치를 측정하는 GNSS 수신기"],
  ["기준국", "정확한 위치를 알고 있어 로버의 위성 오차를 계산해 주는 고정 GNSS 장비"],
  ["FIX", "RTK의 모호정수가 풀려 가장 정밀한 위치해가 나온 상태"],
  ["IMU", "가속도계와 자이로를 묶어 흔들림과 회전을 측정하는 센서"],
  ["LiDAR", "레이저를 쏘고 돌아오는 시간을 재어 주변을 3차원 점으로 측정하는 센서"],
  ["포인트클라우드", "LiDAR가 만든 수많은 x·y·z 좌표점의 모음"],
  ["SLAM", "이동하면서 3D 지도를 만들고 센서 자신의 위치도 동시에 계산하는 기술"],
  ["Jetson", "LiDAR·카메라 데이터를 현장에서 기록하고 처리하는 소형 GPU 컴퓨터"],
  ["SHP", "GIS에서 선·점·면 공간데이터를 보관하는 여러 파일 묶음"],
  ["GeoJSON", "웹 지도에서 읽기 쉬운 점·선·면 공간데이터 파일"],
  ["WMS", "서버가 지도를 그림 타일로 보내 주는 서비스"],
  ["WFS", "서버가 지도 객체의 실제 좌표와 속성을 보내 주는 서비스"],
  ["좌표계·CRS", "지구의 위치를 지도상의 숫자로 표현하는 규칙"],
  ["EPSG:4326", "위도·경도를 도 단위로 표현하는 웹·GPS 공통 좌표계"],
  ["스냅", "측정점을 가장 가까운 공식 도로선 위로 옮기는 보정"],
  ["외부표정", "GNSS·IMU·LiDAR·카메라가 서로 얼마나 떨어져 있고 어느 방향을 보는지 나타내는 값"],
] as const;

function formatDuration(seconds: number) {
  const rounded = Math.round(seconds);
  const hours = Math.floor(rounded / 3600);
  const minutes = Math.floor((rounded % 3600) / 60);
  const secs = rounded % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
    : `${minutes}:${String(secs).padStart(2, "0")}`;
}

function scoreColor(score: number) {
  if (score >= 80) return gradeColor.good;
  if (score >= 65) return gradeColor.fair;
  if (score >= 50) return gradeColor.caution;
  return gradeColor.poor;
}

function latestEventVideoTime(eventDatum: LatestCaptureEvent) {
  return eventDatum.time + latestCapture.video.syncOffsetSec;
}

function useCanvasResize(draw: (canvas: HTMLCanvasElement) => void) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const redraw = () => draw(canvas);
    redraw();
    const observer = new ResizeObserver(redraw);
    observer.observe(canvas);
    return () => observer.disconnect();
  }, [draw]);
  return ref;
}

function RouteMap({
  selectedIndex,
  onSelect,
  selectedEvent,
  onEvent,
}: {
  selectedIndex: number;
  onSelect: (index: number) => void;
  selectedEvent: EventDatum;
  onEvent: (eventDatum: EventDatum) => void;
}) {
  const values = rideData.windows;
  const zoomLevels = [1, 2, 4, 8, 16];
  const [zoomLevel, setZoomLevel] = useState(1);
  const [viewCenter, setViewCenter] = useState(selectedIndex);
  const [mapReady, setMapReady] = useState(false);
  const mapNodeRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<import("leaflet").Map | null>(null);
  const mapLayerRef = useRef<import("leaflet").LayerGroup | null>(null);
  const leafletRef = useRef<typeof import("leaflet") | null>(null);
  const visibleCount = Math.max(20, Math.ceil(values.length / zoomLevel));
  const visibleStart = Math.max(
    0,
    Math.min(values.length - visibleCount, Math.round(viewCenter - visibleCount / 2)),
  );
  const visibleEnd = Math.min(values.length, visibleStart + visibleCount);
  const visibleValues = values.slice(visibleStart, visibleEnd);
  const rangeStart = visibleValues[0];
  const rangeEnd = visibleValues[visibleValues.length - 1];

  useEffect(() => {
    // The parent timeline and event list can change the selected map segment.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setViewCenter(selectedIndex);
  }, [selectedIndex]);

  useEffect(() => {
    let disposed = false;
    void import("leaflet").then((leaflet) => {
      if (disposed || !mapNodeRef.current || mapInstanceRef.current) return;
      leafletRef.current = leaflet;
      const bounds = leaflet.latLngBounds(
        [rideData.bounds.minLat, rideData.bounds.minLon],
        [rideData.bounds.maxLat, rideData.bounds.maxLon],
      );
      const map = leaflet.map(mapNodeRef.current, {
        zoomControl: true,
        scrollWheelZoom: true,
        preferCanvas: true,
      });
      const aerialLayer = leaflet.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        {
          attribution:
            "Tiles &copy; Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community",
          maxZoom: 19,
          updateWhenIdle: true,
        },
      );
      const streetLayer = leaflet.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution:
            '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
          maxZoom: 19,
          updateWhenIdle: true,
        });
      aerialLayer.addTo(map);
      leaflet.control.layers(
        { "항공사진": aerialLayer, "일반지도": streetLayer },
        undefined,
        { collapsed: false, position: "topright" },
      ).addTo(map);
      mapLayerRef.current = leaflet.layerGroup().addTo(map);
      mapInstanceRef.current = map;
      map.fitBounds(bounds, { padding: [24, 24], maxZoom: 15, animate: false });
      setMapReady(true);
    });

    return () => {
      disposed = true;
      mapInstanceRef.current?.remove();
      mapInstanceRef.current = null;
      mapLayerRef.current = null;
      leafletRef.current = null;
    };
  }, []);

  useEffect(() => {
    const leaflet = leafletRef.current;
    const map = mapInstanceRef.current;
    const layer = mapLayerRef.current;
    if (!mapReady || !leaflet || !map || !layer || visibleValues.length === 0) return;

    layer.clearLayers();
    const fullRoute = rideData.route.map((point) => [point.lat, point.lon] as [number, number]);
    leaflet.polyline(fullRoute, {
      color: "#5f7772",
      weight: 4,
      opacity: 0.5,
      interactive: false,
    }).addTo(layer);

    for (let index = visibleStart; index < visibleEnd - 1; index += 1) {
      const datum = values[index];
      const next = values[index + 1];
      const linePoints: [number, number][] = [
        [datum.latitude, datum.longitude],
        [next.latitude, next.longitude],
      ];
      if (index === selectedIndex) {
        leaflet.polyline(linePoints, {
          color: "#f4f7f6",
          weight: 11,
          opacity: 0.78,
          interactive: false,
        }).addTo(layer);
      }
      const segment = leaflet.polyline(linePoints, {
        color: scoreColor(datum.score),
        weight: 7,
        opacity: datum.confidence < 0.7 ? 0.45 : 0.92,
      }).addTo(layer);
      segment.bindTooltip(
        `${formatDuration(datum.time)} · ${datum.score}점 · ${gradeLabel[datum.grade]}`,
        { sticky: true },
      );
      segment.on("click", () => onSelect(index));
    }

    const start = rideData.route[0];
    const finish = rideData.route[rideData.route.length - 1];
    leaflet.circleMarker([start.lat, start.lon], {
      radius: 5,
      color: "#f4f7f6",
      fillColor: "#071716",
      fillOpacity: 1,
      weight: 2,
    }).bindTooltip("출발").addTo(layer);
    leaflet.circleMarker([finish.lat, finish.lon], {
      radius: 5,
      color: "#27d7ad",
      fillColor: "#071716",
      fillOpacity: 1,
      weight: 2,
    }).bindTooltip("도착").addTo(layer);

    rideData.events.forEach((eventDatum) => {
      const isSelected = selectedEvent.id === eventDatum.id;
      const marker = leaflet.circleMarker([eventDatum.latitude, eventDatum.longitude], {
        radius: isSelected ? 10 : 7,
        color: isSelected ? "#f4f7f6" : "#ff6b66",
        fillColor: "#ff6b66",
        fillOpacity: 0.96,
        weight: isSelected ? 3 : 2,
      }).addTo(layer);
      marker.bindTooltip(
        `충격 SPOT ${String(eventDatum.id).padStart(2, "0")} · ${eventDatum.peakAcceleration.toFixed(1)} m/s²`,
        { sticky: true },
      );
      marker.bindPopup(
        `<div class="impact-popup"><img src="${eventDatum.frame}" alt="충격 지점 실제 주행 영상 프레임"><strong>SPOT ${String(eventDatum.id).padStart(2, "0")}</strong><span>${formatDuration(eventDatum.time)} · ${eventDatum.peakAcceleration.toFixed(1)} m/s²</span></div>`,
        { maxWidth: 220, closeButton: false },
      );
      marker.on("click", () => onEvent(eventDatum));
      if (isSelected) marker.openPopup();
    });

    const focusPoints = zoomLevel === 1
      ? fullRoute
      : visibleValues.map((datum) => [datum.latitude, datum.longitude] as [number, number]);
    map.invalidateSize({ animate: false });
    map.fitBounds(leaflet.latLngBounds(focusPoints), {
      padding: [28, 28],
      maxZoom: zoomLevel === 1 ? 15 : 18,
      animate: false,
    });
  }, [mapReady, onEvent, onSelect, selectedEvent.id, selectedIndex, values, visibleEnd, visibleStart, visibleValues, zoomLevel]);

  const changeZoom = (nextZoom: number) => {
    setZoomLevel(nextZoom);
    setViewCenter(selectedIndex);
  };

  return (
    <div className="route-map-shell">
      <div className="map-zoom-bar">
        <div className="map-window-summary" aria-live="polite">
          <span>지도 표시 구간</span>
          <strong>{formatDuration(rangeStart.time)}—{formatDuration(rangeEnd.time + 4)}</strong>
          <small>{visibleValues.length}개 점수 구간</small>
        </div>
        <div className="map-zoom-actions" aria-label="지도 구간 확대">
          {zoomLevels.map((level) => (
            <button
              key={level}
              type="button"
              className={zoomLevel === level ? "active" : ""}
              aria-pressed={zoomLevel === level}
              onClick={() => changeZoom(level)}
            >
              {level === 1 ? "전체" : `${level}×`}
            </button>
          ))}
        </div>
      </div>
      <label className="map-pan-control">
        <span>확대 구간 이동 <strong>{formatDuration(values[viewCenter].time)}</strong></span>
        <input
          type="range"
          min="0"
          max={values.length - 1}
          value={viewCenter}
          disabled={zoomLevel === 1}
          onChange={(event) => setViewCenter(Number(event.target.value))}
          aria-label="지도 확대 구간 이동"
        />
      </label>
      <div
        ref={mapNodeRef}
        className="actual-map"
        role="region"
        aria-label="항공사진 위 GPS 주행 경로, IMU 점수 구간, 충격 감지 지점"
      />
      <div className="map-footnote">
        <span>항공사진 · Esri World Imagery / S-MAP 항공영상 연동 준비</span>
        <span>점수 선은 4초 구간, 붉은 SPOT은 실제 현장 프레임 선택</span>
      </div>
      <div className="spot-preview" aria-live="polite">
        <img
          src={selectedEvent.frame}
          alt={`충격 SPOT ${selectedEvent.id} 실제 주행 영상 프레임`}
        />
        <div className="spot-preview-copy">
          <div className="spot-preview-heading">
            <span>IMPACT SPOT {String(selectedEvent.id).padStart(2, "0")} · 실제 현장</span>
            <strong>{selectedEvent.peakAcceleration.toFixed(1)} m/s²</strong>
          </div>
          <p>충격이 감지된 순간의 원본 주행 영상 프레임입니다. 붉은 SPOT을 누르면 위치와 이 화면이 함께 바뀝니다.</p>
          <dl>
            <div><dt>주행 시각</dt><dd>{formatDuration(selectedEvent.time)}</dd></div>
            <div><dt>GPS</dt><dd>{selectedEvent.latitude.toFixed(6)}, {selectedEvent.longitude.toFixed(6)}</dd></div>
            <div><dt>위치 오차</dt><dd>약 ±{selectedEvent.accuracy.toFixed(1)} m</dd></div>
          </dl>
          <div className="spot-actions">
            <a href="#video-review">해당 영상·노면 그래프 보기</a>
            <a href="https://smap.seoul.go.kr/" target="_blank" rel="noreferrer">S-MAP 3D·거리뷰 열기</a>
          </div>
        </div>
      </div>
      <details className="smap-integration" open>
        <summary>S-MAP에서 추가 적용할 수 있는 데이터</summary>
        <div className="smap-grid">
          <div><strong>연도별 영상지도 · 3D 건물</strong><span>노면 주변 환경과 시설 변화 이력 비교</span></div>
          <div><strong>보행자 · 골목길 거리뷰</strong><span>충격 지점의 시설물·노면 상태 현장 확인</span></div>
          <div><strong>표고 · 거리 · 경사 분석</strong><span>경사로 인한 진동 증가를 점수 계산에서 보정</span></div>
          <div><strong>교통 · 사고 · 공사 · 안전시설</strong><span>CCTV·보행불편·공사 정보와 결합해 보수 우선순위 산정</span></div>
        </div>
        <div className="smap-api-note">
          <p><strong>직접 연동에는 S-MAP OpenAPI 키가 필요합니다.</strong> 승인 키를 받으면 현재 항공사진 레이어를 서울시 영상지도와 교체하고, 표고·안전 레이어를 같은 좌표에 겹칠 수 있습니다.</p>
          <a href="https://map.seoul.go.kr/smgis2/division/viewOpenApiReq" target="_blank" rel="noreferrer">OpenAPI 이용 신청</a>
        </div>
      </details>
    </div>
  );
}

function RoadTwin3D({
  dataset,
  selectedIndex,
  onSelect,
}: {
  dataset: RoadDataset;
  selectedIndex: number;
  onSelect: (index: number) => void;
}) {
  const [rotation, setRotation] = useState(348);
  const [viewTilt, setViewTilt] = useState(12);
  const [cameraZoom, setCameraZoom] = useState(1.35);
  const [heightScale, setHeightScale] = useState(3.2);
  const [zoomLevel, setZoomLevel] = useState(4);
  const [viewCenter, setViewCenter] = useState(selectedIndex);
  const projectedRef = useRef<Array<{ x: number; y: number; index: number }>>([]);
  const dragRef = useRef({
    active: false,
    startX: 0,
    startRotation: 0,
    moved: false,
  });
  const values = dataset.windows;
  const zoomLevels = [1, 2, 4, 8, 16];
  const visibleCount = Math.max(20, Math.ceil(values.length / zoomLevel));
  const visibleStart = Math.max(
    0,
    Math.min(values.length - visibleCount, Math.round(viewCenter - visibleCount / 2)),
  );
  const visibleEnd = Math.min(values.length - 1, visibleStart + visibleCount - 1);

  useEffect(() => {
    // Keep the 3D window aligned with selections made elsewhere in the dashboard.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setViewCenter(selectedIndex);
  }, [selectedIndex]);

  const draw = useMemo(
    () => (canvas: HTMLCanvasElement) => {
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const ratio = window.devicePixelRatio || 1;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.scale(ratio, ratio);
      ctx.clearRect(0, 0, width, height);

      const visibleValues = values.slice(visibleStart, visibleEnd + 1);
      const firstTime = values[visibleStart].time;
      const lastTime = values[visibleEnd].time + 4;
      const routeSlice = dataset.route.filter(
        (point) => point.time >= firstTime && point.time <= lastTime,
      );
      const roadSource = routeSlice.length >= 2
        ? routeSlice
        : visibleValues.map((point) => ({
            time: point.time,
            lat: point.latitude,
            lon: point.longitude,
            accuracy: point.accuracy,
          }));
      const centerLat = roadSource.reduce((sum, point) => sum + point.lat, 0) / roadSource.length;
      const centerLon = roadSource.reduce((sum, point) => sum + point.lon, 0) / roadSource.length;
      const lonMeters = 111_320 * Math.cos((centerLat * Math.PI) / 180);
      const toLocal = (latitude: number, longitude: number) => ({
        x: (longitude - centerLon) * lonMeters,
        y: (latitude - centerLat) * 111_320,
      });
      const windowLocal = values.map((point) => toLocal(point.latitude, point.longitude));
      const smoothedScore = values.map((_, index) => {
        const start = Math.max(0, index - 2);
        const end = Math.min(values.length - 1, index + 2);
        let total = 0;
        for (let current = start; current <= end; current += 1) total += values[current].score;
        return total / (end - start + 1);
      });
      const relativeSurface = values.map((_, index) => {
        const start = Math.max(0, index - 2);
        const end = Math.min(values.length - 1, index + 2);
        let total = 0;
        for (let current = start; current <= end; current += 1) {
          const datum = values[current];
          const scoreSignal = Math.max(0, Math.min(1, (100 - datum.score) / 55));
          const rmsSignal = Math.max(0, Math.min(1, datum.accelRms / 3));
          const peakSignal = Math.max(0, Math.min(1, datum.peak / 15));
          const frequencySignal = Math.max(0, Math.min(1, (datum.hfRatio ?? 0) / 0.6));
          total += scoreSignal * 0.48 + rmsSignal * 0.24 + peakSignal * 0.18 + frequencySignal * 0.1;
        }
        return total / (end - start + 1);
      });
      const roadSamples = roadSource.map((point) => {
        let nearest = visibleStart;
        for (let index = visibleStart + 1; index <= visibleEnd; index += 1) {
          if (Math.abs(values[index].time - point.time) < Math.abs(values[nearest].time - point.time)) {
            nearest = index;
          }
        }
        return {
          ...toLocal(point.lat, point.lon),
          score: smoothedScore[nearest],
          confidence: values[nearest].confidence,
          windowIndex: nearest,
        };
      });
      const sampleXs = roadSamples.map((point) => point.x);
      const sampleYs = roadSamples.map((point) => point.y);
      const routePlanSpan = Math.max(
        1,
        Math.max(...sampleXs) - Math.min(...sampleXs),
        Math.max(...sampleYs) - Math.min(...sampleYs),
      );
      const visibleSurface = relativeSurface.slice(visibleStart, visibleEnd + 1).sort((a, b) => a - b);
      const surfaceFloor = visibleSurface[Math.floor(visibleSurface.length * 0.18)] ?? 0;
      const relief = (index: number) =>
        Math.max(0, relativeSurface[index] - surfaceFloor) * routePlanSpan * 0.055 * heightScale;

      const angle = (rotation * Math.PI) / 180;
      const rotate = (point: { x: number; y: number }) => ({
        x: point.x * Math.cos(angle) - point.y * Math.sin(angle),
        depth: point.x * Math.sin(angle) + point.y * Math.cos(angle),
      });
      const scenePoint = (point: { x: number; y: number }, z: number) => {
        const rotated = rotate(point);
        const tilt = (viewTilt * Math.PI) / 180;
        return {
          x: rotated.x,
          y: rotated.depth * Math.sin(tilt) + z * Math.cos(tilt),
          depth: rotated.depth,
        };
      };

      const sceneBounds = [
        ...roadSamples.map((point) => scenePoint(point, 0)),
        ...roadSamples.map((point) => scenePoint(point, relief(point.windowIndex))),
      ];
      const minX = Math.min(...sceneBounds.map((point) => point.x));
      const maxX = Math.max(...sceneBounds.map((point) => point.x));
      const minY = Math.min(...sceneBounds.map((point) => point.y));
      const maxY = Math.max(...sceneBounds.map((point) => point.y));
      const pad = { left: 48, right: 34, top: 64, bottom: 48 };
      const fitScale = Math.min(
        (width - pad.left - pad.right) / Math.max(1, maxX - minX),
        (height - pad.top - pad.bottom) / Math.max(1, maxY - minY),
      );
      const scale = fitScale * cameraZoom;
      const sceneCenterX = (minX + maxX) / 2;
      const sceneCenterY = (minY + maxY) / 2;
      const projectScene = (point: { x: number; y: number }) => ({
        x: width / 2 + (point.x - sceneCenterX) * scale,
        y: height / 2 - (point.y - sceneCenterY) * scale,
      });
      const project = (point: { x: number; y: number }, z = 0) => projectScene(scenePoint(point, z));

      const xs = roadSamples.map((point) => point.x);
      const ys = roadSamples.map((point) => point.y);
      const worldMinX = Math.min(...xs);
      const worldMaxX = Math.max(...xs);
      const worldMinY = Math.min(...ys);
      const worldMaxY = Math.max(...ys);
      ctx.strokeStyle = "rgba(143, 167, 188, .14)";
      ctx.lineWidth = 1;
      for (let index = 0; index <= 6; index += 1) {
        const x = worldMinX + ((worldMaxX - worldMinX) * index) / 6;
        const a = project({ x, y: worldMinY });
        const b = project({ x, y: worldMaxY });
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      }
      for (let index = 0; index <= 4; index += 1) {
        const y = worldMinY + ((worldMaxY - worldMinY) * index) / 4;
        const a = project({ x: worldMinX, y });
        const b = project({ x: worldMaxX, y });
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      }

      const routeSpan = Math.max(worldMaxX - worldMinX, worldMaxY - worldMinY);
      const halfWidth = Math.max(2.2, Math.min(6, routeSpan * 0.004));
      const segments = roadSamples.slice(0, -1).map((point, localIndex) => {
        const next = roadSamples[localIndex + 1];
        const dx = next.x - point.x;
        const dy = next.y - point.y;
        const length = Math.max(0.001, Math.hypot(dx, dy));
        const offset = { x: (-dy / length) * halfWidth, y: (dx / length) * halfWidth };
        const signalOffset = { x: offset.x * 0.66, y: offset.y * 0.66 };
        const z0 = relief(point.windowIndex);
        const z1 = relief(next.windowIndex);
        const baseCorners = [
          project({ x: point.x + offset.x, y: point.y + offset.y }),
          project({ x: next.x + offset.x, y: next.y + offset.y }),
          project({ x: next.x - offset.x, y: next.y - offset.y }),
          project({ x: point.x - offset.x, y: point.y - offset.y }),
        ];
        const surfaceCorners = [
          project({ x: point.x + signalOffset.x, y: point.y + signalOffset.y }, z0),
          project({ x: next.x + signalOffset.x, y: next.y + signalOffset.y }, z1),
          project({ x: next.x - signalOffset.x, y: next.y - signalOffset.y }, z1),
          project({ x: point.x - signalOffset.x, y: point.y - signalOffset.y }, z0),
        ];
        const depth = (rotate(point).depth + rotate(next).depth) / 2;
        return {
          baseCorners,
          confidence: Math.min(point.confidence, next.confidence),
          depth,
          score: (point.score + next.score) / 2,
          surfaceCorners,
          windowIndex: point.windowIndex,
        };
      });

      const depthSorted = [...segments].sort((a, b) => b.depth - a.depth);
      depthSorted.forEach((segment) => {
        ctx.fillStyle = "#26322f";
        ctx.globalAlpha = 1;
        ctx.beginPath();
        segment.baseCorners.forEach((point, index) => {
          if (index === 0) ctx.moveTo(point.x, point.y);
          else ctx.lineTo(point.x, point.y);
        });
        ctx.closePath();
        ctx.fill();
        ctx.strokeStyle = "rgba(182, 198, 193, .2)";
        ctx.lineWidth = 1;
        ctx.stroke();
      });

      const drawRoadEdge = (points: Array<{ x: number; y: number }>) => {
        ctx.strokeStyle = "rgba(231, 237, 234, .62)";
        ctx.lineWidth = 1.15;
        ctx.beginPath();
        points.forEach((point, index) => {
          if (index === 0) ctx.moveTo(point.x, point.y);
          else ctx.lineTo(point.x, point.y);
        });
        ctx.stroke();
      };
      if (segments.length > 0) {
        drawRoadEdge([
          ...segments.map((segment) => segment.baseCorners[0]),
          segments[segments.length - 1].baseCorners[1],
        ]);
        drawRoadEdge([
          ...segments.map((segment) => segment.baseCorners[3]),
          segments[segments.length - 1].baseCorners[2],
        ]);
      }

      depthSorted.forEach((segment) => {
        const side = [
          segment.baseCorners[0],
          segment.baseCorners[1],
          segment.surfaceCorners[1],
          segment.surfaceCorners[0],
        ];
        ctx.fillStyle = "rgba(8, 20, 19, .82)";
        ctx.beginPath();
        side.forEach((point, index) => {
          if (index === 0) ctx.moveTo(point.x, point.y);
          else ctx.lineTo(point.x, point.y);
        });
        ctx.closePath();
        ctx.fill();

        const profileCurtain = [
          {
            x: (segment.baseCorners[0].x + segment.baseCorners[3].x) / 2,
            y: (segment.baseCorners[0].y + segment.baseCorners[3].y) / 2,
          },
          {
            x: (segment.baseCorners[1].x + segment.baseCorners[2].x) / 2,
            y: (segment.baseCorners[1].y + segment.baseCorners[2].y) / 2,
          },
          {
            x: (segment.surfaceCorners[1].x + segment.surfaceCorners[2].x) / 2,
            y: (segment.surfaceCorners[1].y + segment.surfaceCorners[2].y) / 2,
          },
          {
            x: (segment.surfaceCorners[0].x + segment.surfaceCorners[3].x) / 2,
            y: (segment.surfaceCorners[0].y + segment.surfaceCorners[3].y) / 2,
          },
        ];
        ctx.fillStyle = scoreColor(segment.score);
        ctx.globalAlpha = segment.confidence < 0.7 ? 0.14 : 0.28;
        ctx.beginPath();
        profileCurtain.forEach((point, index) => {
          if (index === 0) ctx.moveTo(point.x, point.y);
          else ctx.lineTo(point.x, point.y);
        });
        ctx.closePath();
        ctx.fill();
        ctx.globalAlpha = 1;

        ctx.fillStyle = scoreColor(segment.score);
        ctx.globalAlpha = segment.confidence < 0.7 ? 0.45 : 0.78;
        ctx.beginPath();
        segment.surfaceCorners.forEach((point, index) => {
          if (index === 0) ctx.moveTo(point.x, point.y);
          else ctx.lineTo(point.x, point.y);
        });
        ctx.closePath();
        ctx.fill();
        ctx.globalAlpha = 1;
        ctx.strokeStyle = segment.windowIndex === selectedIndex
          ? "rgba(244, 247, 246, .95)"
          : "rgba(226, 239, 235, .18)";
        ctx.lineWidth = segment.windowIndex === selectedIndex ? 2.4 : 0.8;
        ctx.stroke();
      });
      ctx.globalAlpha = 1;

      const visibleLocal = windowLocal.slice(visibleStart, visibleEnd + 1);
      projectedRef.current = visibleLocal.map((point, localIndex) => {
        const index = visibleStart + localIndex;
        return { ...project(point, relief(index)), index };
      });

      const surfaceCenter = roadSamples.map((point) => project(point, relief(point.windowIndex)));
      ctx.strokeStyle = "rgba(238, 244, 241, .76)";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      surfaceCenter.forEach((point, index) => {
        if (index === 0) ctx.moveTo(point.x, point.y);
        else ctx.lineTo(point.x, point.y);
      });
      ctx.stroke();

      dataset.events.forEach((eventDatum) => {
        let nearest = visibleStart;
        values.forEach((datum, index) => {
          if (Math.abs(datum.time - eventDatum.time) < Math.abs(values[nearest].time - eventDatum.time)) {
            nearest = index;
          }
        });
        if (nearest < visibleStart || nearest > visibleEnd) return;
        const top = projectedRef.current[nearest - visibleStart];
        const base = project(windowLocal[nearest], 0);
        ctx.strokeStyle = "rgba(255, 107, 102, .55)";
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(base.x, base.y);
        ctx.lineTo(top.x, top.y);
        ctx.stroke();
        ctx.fillStyle = gradeColor.poor;
        ctx.beginPath();
        ctx.arc(top.x, top.y, 2.8, 0, Math.PI * 2);
        ctx.fill();
      });

      ctx.fillStyle = "rgba(232, 244, 240, .9)";
      ctx.font = '600 12px "Noto Sans KR", Arial, sans-serif';
      ctx.fillText(`${zoomLevel}× 확대 · GPS 도로 형상 ${roadSamples.length}점`, pad.left, 26);
      ctx.fillStyle = "rgba(190, 209, 204, .9)";
      ctx.fillText("도로 선형: GPS 실측", pad.left, height - 14);
      ctx.textAlign = "right";
      ctx.fillText("표면 굴곡: IMU 상대 추정 · 실측 높이 아님", width - pad.right, height - 14);
      ctx.textAlign = "left";
    },
    [cameraZoom, dataset.events, dataset.route, heightScale, rotation, selectedIndex, values, viewTilt, visibleEnd, visibleStart, zoomLevel],
  );
  const canvasRef = useCanvasResize(draw);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const handleWheel = (event: WheelEvent) => {
      event.preventDefault();
      event.stopPropagation();
      const direction = event.deltaY > 0 ? -1 : 1;
      setCameraZoom((current) => Math.max(0.7, Math.min(3.5, current + direction * 0.12)));
    };
    canvas.addEventListener("wheel", handleWheel, { passive: false });
    return () => canvas.removeEventListener("wheel", handleWheel);
  }, [canvasRef]);

  function selectNearest(event: React.PointerEvent<HTMLCanvasElement>) {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    let nearest = projectedRef.current[0];
    projectedRef.current.forEach((point) => {
      const currentDistance = Math.hypot(point.x - x, point.y - y);
      const nearestDistance = Math.hypot(nearest.x - x, nearest.y - y);
      if (currentDistance < nearestDistance) nearest = point;
    });
    onSelect(nearest.index);
  }

  function pointerDown(event: React.PointerEvent<HTMLCanvasElement>) {
    dragRef.current = {
      active: true,
      startX: event.clientX,
      startRotation: rotation,
      moved: false,
    };
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function pointerMove(event: React.PointerEvent<HTMLCanvasElement>) {
    if (!dragRef.current.active) return;
    const deltaX = event.clientX - dragRef.current.startX;
    if (Math.abs(deltaX) > 4) dragRef.current.moved = true;
    setRotation((dragRef.current.startRotation + deltaX * 0.35 + 360) % 360);
  }

  function pointerUp(event: React.PointerEvent<HTMLCanvasElement>) {
    if (!dragRef.current.moved) selectNearest(event);
    dragRef.current.active = false;
    event.currentTarget.releasePointerCapture(event.pointerId);
  }

  return (
    <article className="card twin-card">
      <div className="card-topline twin-heading">
        <div>
          <span className="card-label">GPS-SHAPED 3D ROAD / IMU OVERLAY</span>
          <h3>GPS 기반 실제 경로 3D 도로 · {dataset.shortLabel}</h3>
        </div>
        <span className="provisional">GPS 선형 · IMU 추정 굴곡</span>
      </div>
      <div className="twin-zoom-bar">
        <div className="twin-window-summary">
          <span>현재 표시 구간</span>
          <strong>{formatDuration(values[visibleStart].time)} — {formatDuration(values[visibleEnd].time)}</strong>
          <small>{visibleEnd - visibleStart + 1}개 분석 창</small>
        </div>
        <div className="twin-zoom-actions" role="group" aria-label="3D 도로 구간 확대">
          {zoomLevels.map((level) => (
            <button
              key={level}
              type="button"
              className={zoomLevel === level ? "active" : ""}
              onClick={() => {
                setZoomLevel(level);
                setViewCenter(selectedIndex);
              }}
              aria-pressed={zoomLevel === level}
            >
              {level === 1 ? "전체" : `${level}×`}
            </button>
          ))}
        </div>
      </div>
      <RoadContext3DMap
        key={dataset.id}
        dataset={dataset}
        selectedIndex={selectedIndex}
        visibleStart={visibleStart}
        visibleEnd={visibleEnd}
        onSelect={onSelect}
      />
      <div className="twin-layout">
        <div className="twin-stage">
          <canvas
            ref={canvasRef}
            className="twin-canvas"
            onPointerDown={pointerDown}
            onPointerMove={pointerMove}
            onPointerUp={pointerUp}
            onPointerCancel={pointerUp}
            aria-label={`마우스 휠로 확대하고 좌우 드래그로 360도 회전하는 GPS 도로 선형과 IMU 상대 굴곡의 3차원 모델. ${zoomLevel}배 구간 확대, ${formatDuration(values[visibleStart].time)}부터 ${formatDuration(values[visibleEnd].time)}까지 표시`}
          />
          <div className="twin-surface-notice">
            <strong>IMU 추정 굴곡</strong>
            <span>실측 높이 아님</span>
          </div>
          <div className="twin-stage-hint">휠 확대·축소 · 좌우 드래그 360° 회전 · 시점 자동변경 없음</div>
        </div>
        <div className="twin-controls">
          <label>
            <span>360° 시점 회전 <strong>{Math.round(rotation) % 360}°</strong></span>
            <input
              type="range"
              min="0"
              max="359"
              step="1"
              value={rotation}
              onChange={(event) => setRotation(Number(event.target.value))}
              aria-label="3D 도로 360도 회전"
            />
          </label>
          <label>
            <span>카메라 기울기 <strong>{Math.round(viewTilt)}°</strong></span>
            <input
              type="range"
              min="4"
              max="65"
              step="1"
              value={viewTilt}
              onChange={(event) => setViewTilt(Number(event.target.value))}
              aria-label="3D 도로 카메라 기울기"
            />
          </label>
          <label>
            <span>화면 확대 <strong>{cameraZoom.toFixed(2)}×</strong></span>
            <input
              type="range"
              min="0.7"
              max="3.5"
              step="0.05"
              value={cameraZoom}
              onChange={(event) => setCameraZoom(Number(event.target.value))}
              aria-label="3D 도로 화면 확대"
            />
          </label>
          <div className="twin-view-actions">
            <button
              type="button"
              onClick={() => setCameraZoom((current) => Math.min(3.5, current + 0.25))}
              aria-label="3D 도로 확대"
            >
              ＋ 확대
            </button>
            <button
              type="button"
              onClick={() => setCameraZoom((current) => Math.max(0.7, current - 0.25))}
              aria-label="3D 도로 축소"
            >
              － 축소
            </button>
            <button
              type="button"
              className="profile-preset"
              onClick={() => {
                setRotation(348);
                setViewTilt(8);
                setCameraZoom(1.55);
                setHeightScale(3.8);
              }}
            >
              굴곡 측면 보기
            </button>
            <button
              type="button"
              onClick={() => {
                setRotation(348);
                setViewTilt(12);
                setCameraZoom(1.35);
                setHeightScale(3.2);
              }}
            >
              시점 초기화
            </button>
          </div>
          <label>
            <span>추정 굴곡 강조 <strong>{heightScale.toFixed(1)}×</strong></span>
            <input
              type="range"
              min="0"
              max="6"
              step="0.1"
              value={heightScale}
              onChange={(event) => setHeightScale(Number(event.target.value))}
              aria-label="IMU 추정 굴곡 강조"
            />
          </label>
          <label className="twin-pan-control">
            <span>확대 구간 이동 <strong>{formatDuration(values[Math.round(viewCenter)].time)}</strong></span>
            <input
              type="range"
              min="0"
              max={values.length - 1}
              step="1"
              value={viewCenter}
              disabled={zoomLevel === 1}
              onChange={(event) => setViewCenter(Number(event.target.value))}
              aria-label="확대 구간 중심 이동"
            />
          </label>
          <div className="twin-overview" aria-hidden="true">
            <i
              style={{
                left: `${(visibleStart / (values.length - 1)) * 100}%`,
                width: `${((visibleEnd - visibleStart) / (values.length - 1)) * 100}%`,
              }}
            />
            <b style={{ left: `${(selectedIndex / (values.length - 1)) * 100}%` }} />
          </div>
          <dl className="twin-readiness">
            <div><dt>도로 선형·위치</dt><dd>GPS 실측</dd></div>
            <div><dt>포장 표면</dt><dd>아스팔트 시각 모델</dd></div>
            <div><dt>색·표면 굴곡</dt><dd>IMU 상대 추정</dd></div>
            <div><dt>실제 높이·폭</dt><dd>스테레오·LiDAR 필요</dd></div>
          </dl>
          <p>실제 GPS 경로를 따라 도로를 구성하고 IMU의 점수·RMS·피크·고주파 진동을 결합해 상대 굴곡을 표시했습니다. 굴곡 방향과 높이는 실측값이 아니며 LiDAR·스테레오 데이터가 들어오면 실제 표면 모델로 교체할 수 있습니다.</p>
        </div>
      </div>
      <div className="legend twin-legend">
        <span><i className="legend-line full" /> GPS 실제 도로 선형</span>
        <span><i className="legend-dot good" /> 양호</span>
        <span><i className="legend-dot caution" /> 주의</span>
        <span><i className="legend-dot poor" /> 충격 이벤트</span>
      </div>
      <details className="twin-explainer" open>
        <summary>3D 도로 항목별 상세 설명</summary>
        <dl className="twin-explanation-grid">
          <div>
            <dt>현재 표시 구간</dt>
            <dd>주행 시작 시점을 0분으로 두었을 때 현재 3D 도로에 포함된 시간 범위입니다. 센서 점수는 4초 데이터를 하나의 창으로 묶고 2초씩 이동해 계산했기 때문에 인접 구간이 서로 2초 겹칩니다.</dd>
          </div>
          <div>
            <dt>전체·2×·4×·8×·16× 확대</dt>
            <dd>지도 축척이나 실제 도로 폭을 확대하는 기능이 아니라 화면에 포함되는 분석 시간을 줄이는 기능입니다. 배율이 높을수록 더 짧은 구간을 크게 보여 충격 위치와 점수 변화를 자세히 확인할 수 있습니다.</dd>
          </div>
          <div>
            <dt>GPS 실제 도로 선형</dt>
            <dd>휴대폰에서 기록된 위도·경도를 미터 단위 평면 좌표로 변환해 도로의 굴곡과 진행 방향을 만든 것입니다. 위치 형태는 실측 GPS를 따르지만 수신 환경에 따라 수 미터 이상의 오차가 포함될 수 있습니다.</dd>
          </div>
          <div>
            <dt>아스팔트 시각 모델</dt>
            <dd>어두운 바닥, 가장자리 선과 중앙선은 경로를 도로처럼 읽기 쉽게 만든 표현입니다. 영상으로 포장 재질이나 차선 폭을 복원한 결과가 아니며 실제 자전거도로 폭과 정확히 일치하지 않습니다.</dd>
          </div>
          <div>
            <dt>표면 색상</dt>
            <dd>4초간의 진동 상대점수를 나타냅니다. 80점 이상은 양호, 65~79.9점은 보통, 50~64.9점은 주의, 50점 미만은 강한 진동 감지·영상 확인 필요 구간입니다. 공인 IRI나 포장상태지수는 아닙니다.</dd>
          </div>
          <div>
            <dt>표면 높이와 신호 강조</dt>
            <dd>도로가 위로 솟아 보이는 정도는 IMU 점수·RMS·피크·고주파 진동을 묶어 시각적으로 강조한 상대 굴곡입니다. ‘추정 굴곡 강조’를 0×로 두면 평평해지고 2×로 높이면 차이가 커지지만 실제 포트홀 깊이나 단차 높이를 뜻하지는 않습니다.</dd>
          </div>
          <div>
            <dt>시점 회전</dt>
            <dd>좌우 드래그나 0~359° 슬라이더로 도로 둘레를 한 바퀴 회전할 수 있습니다. 시점은 자동으로 움직이지 않습니다. 마우스 휠로 화면을 확대·축소하고 ‘굴곡 측면 보기’를 누르면 낮은 각도에서 노면 변화가 더 잘 보입니다.</dd>
          </div>
          <div>
            <dt>선택 구간과 흰색 테두리</dt>
            <dd>도로를 누르면 가장 가까운 4초 분석 창이 선택되고 해당 표면에 흰색 테두리가 표시됩니다. 선택 결과는 위의 ‘SELECTED 4-SECOND WINDOW’ 점수와 아래 그래프에도 함께 연결됩니다.</dd>
          </div>
          <div>
            <dt>충격 이벤트 표시</dt>
            <dd>가속도 피크가 컸던 시점과 가까운 도로 위치를 붉은 점으로 표시합니다. 포트홀을 확정한 표시는 아니므로 같은 시점의 영상을 열어 이음부·요철·자전거 조작 여부를 함께 확인해야 합니다.</dd>
          </div>
          <div>
            <dt>실제 높이·폭</dt>
            <dd>현재 휴대폰 GPS와 IMU만으로는 균열 폭, 포트홀 깊이, 단차 높이를 센티미터 단위로 복원할 수 없습니다. 해당 값이 필요하면 카메라 보정이 된 스테레오 영상이나 LiDAR·RTK 측량 데이터가 추가로 필요합니다.</dd>
          </div>
        </dl>
      </details>
    </article>
  );
}

function ScoreTimeline({
  selectedIndex,
  onSelect,
}: {
  selectedIndex: number;
  onSelect: (index: number) => void;
}) {
  const draw = useMemo(
    () => (canvas: HTMLCanvasElement) => {
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const ratio = window.devicePixelRatio || 1;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.scale(ratio, ratio);
      ctx.clearRect(0, 0, width, height);
      const pad = { left: 38, right: 20, top: 20, bottom: 34 };
      const values = rideData.windows;
      const x = (index: number) =>
        pad.left + (index / (values.length - 1)) * (width - pad.left - pad.right);
      const y = (score: number) =>
        pad.top + ((100 - score) / 60) * (height - pad.top - pad.bottom);

      [50, 65, 80, 100].forEach((score) => {
        ctx.strokeStyle = "rgba(166, 191, 205, .15)";
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(pad.left, y(score));
        ctx.lineTo(width - pad.right, y(score));
        ctx.stroke();
        ctx.fillStyle = "rgba(226, 239, 235, .82)";
        ctx.font = "11px Arial";
        ctx.fillText(String(score), 7, y(score) + 3);
      });

      ctx.beginPath();
      values.forEach((datum, index) => {
        const px = x(index);
        const py = y(datum.score);
        if (index === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      });
      ctx.strokeStyle = "#4be1bd";
      ctx.lineWidth = 2.4;
      ctx.stroke();

      values.forEach((datum, index) => {
        if (datum.score >= 50 || index % 2) return;
        ctx.fillStyle = gradeColor.poor;
        ctx.beginPath();
        ctx.arc(x(index), y(datum.score), 3.2, 0, Math.PI * 2);
        ctx.fill();
      });

      const selected = values[selectedIndex];
      const selectedX = x(selectedIndex);
      ctx.strokeStyle = "rgba(255,255,255,.75)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(selectedX, pad.top);
      ctx.lineTo(selectedX, height - pad.bottom);
      ctx.stroke();
      ctx.fillStyle = scoreColor(selected.score);
      ctx.beginPath();
      ctx.arc(selectedX, y(selected.score), 6, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = "rgba(226, 239, 235, .82)";
      ctx.font = "11px Arial";
      ctx.fillText(formatDuration(values[0].time), pad.left, height - 9);
      ctx.textAlign = "right";
      ctx.fillText(formatDuration(values[values.length - 1].time), width - pad.right, height - 9);
      ctx.textAlign = "left";
    },
    [selectedIndex],
  );
  const canvasRef = useCanvasResize(draw);

  function handlePointer(event: React.PointerEvent<HTMLCanvasElement>) {
    const rect = event.currentTarget.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left - 38) / (rect.width - 58)));
    onSelect(Math.round(ratio * (rideData.windows.length - 1)));
  }

  return (
    <canvas
      ref={canvasRef}
      className="timeline-canvas"
      onPointerDown={handlePointer}
      aria-label="시간대별 노면 점수. 클릭하여 구간 선택"
    />
  );
}

function EventConditionGraph({
  eventDatum,
  playheadTime,
  onSelect,
}: {
  eventDatum: LatestCaptureEvent;
  playheadTime: number;
  onSelect: (index: number) => void;
}) {
  const values = latestCapture.windows;
  const rangeStart = eventDatum.time - 20;
  const rangeEnd = eventDatum.time + 20;
  const visible = values
    .map((datum, index) => ({ datum, index }))
    .filter(({ datum }) => datum.time >= rangeStart && datum.time <= rangeEnd);
  const currentIndex = values.reduce(
    (best, datum, index) =>
      Math.abs(datum.time - playheadTime) < Math.abs(values[best].time - playheadTime)
        ? index
        : best,
    0,
  );
  const current = values[currentIndex];
  const draw = useMemo(
    () => (canvas: HTMLCanvasElement) => {
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const ratio = window.devicePixelRatio || 1;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.scale(ratio, ratio);
      ctx.clearRect(0, 0, width, height);

      const pad = { left: 40, right: 18, top: 22, bottom: 34 };
      const plotWidth = width - pad.left - pad.right;
      const plotHeight = height - pad.top - pad.bottom;
      const x = (time: number) =>
        pad.left + ((time - rangeStart) / (rangeEnd - rangeStart)) * plotWidth;
      const y = (score: number) =>
        pad.top + ((100 - Math.max(40, Math.min(100, score))) / 60) * plotHeight;

      const bands = [
        { from: 80, to: 100, color: "rgba(39, 215, 173, .07)" },
        { from: 65, to: 80, color: "rgba(184, 221, 80, .06)" },
        { from: 50, to: 65, color: "rgba(246, 184, 75, .07)" },
        { from: 40, to: 50, color: "rgba(255, 107, 102, .08)" },
      ];
      bands.forEach((band) => {
        ctx.fillStyle = band.color;
        ctx.fillRect(pad.left, y(band.to), plotWidth, y(band.from) - y(band.to));
      });

      [50, 65, 80, 100].forEach((score) => {
        ctx.strokeStyle = "rgba(166, 191, 205, .16)";
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(pad.left, y(score));
        ctx.lineTo(width - pad.right, y(score));
        ctx.stroke();
        ctx.fillStyle = "rgba(226, 239, 235, .84)";
        ctx.font = "11px Arial";
        ctx.fillText(String(score), 7, y(score) + 3);
      });

      visible.slice(0, -1).forEach((item, localIndex) => {
        const next = visible[localIndex + 1];
        ctx.strokeStyle = scoreColor(item.datum.score);
        ctx.globalAlpha = item.datum.confidence < 0.7 ? 0.45 : 0.95;
        ctx.lineWidth = 2.6;
        ctx.beginPath();
        ctx.moveTo(x(item.datum.time), y(item.datum.score));
        ctx.lineTo(x(next.datum.time), y(next.datum.score));
        ctx.stroke();
      });
      ctx.globalAlpha = 1;

      const eventX = x(eventDatum.time);
      ctx.strokeStyle = gradeColor.poor;
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.moveTo(eventX, pad.top);
      ctx.lineTo(eventX, height - pad.bottom);
      ctx.stroke();
      ctx.fillStyle = gradeColor.poor;
      ctx.font = '600 11px "Noto Sans KR", Arial, sans-serif';
      ctx.textAlign = "center";
      ctx.fillText("충격", eventX, 13);

      if (playheadTime >= rangeStart && playheadTime <= rangeEnd) {
        const playheadX = x(playheadTime);
        ctx.strokeStyle = "rgba(244, 247, 246, .92)";
        ctx.lineWidth = 1.2;
        ctx.beginPath();
        ctx.moveTo(playheadX, pad.top);
        ctx.lineTo(playheadX, height - pad.bottom);
        ctx.stroke();
        ctx.fillStyle = scoreColor(current.score);
        ctx.beginPath();
        ctx.arc(x(current.time), y(current.score), 5.5, 0, Math.PI * 2);
        ctx.fill();
      }

      [-20, -10, 0, 10, 20].forEach((offset) => {
        const tickX = x(eventDatum.time + offset);
        ctx.fillStyle = "rgba(226, 239, 235, .84)";
        ctx.font = "11px Arial";
        ctx.textAlign = offset === -20 ? "left" : offset === 20 ? "right" : "center";
        ctx.fillText(offset === 0 ? "0초" : `${offset > 0 ? "+" : ""}${offset}초`, tickX, height - 9);
      });
      ctx.textAlign = "left";
    },
    [current.score, current.time, eventDatum.time, playheadTime, rangeEnd, rangeStart, visible],
  );
  const canvasRef = useCanvasResize(draw);

  function handlePointer(event: React.PointerEvent<HTMLCanvasElement>) {
    const rect = event.currentTarget.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left - 40) / (rect.width - 58)));
    const targetTime = rangeStart + ratio * (rangeEnd - rangeStart);
    const nearest = values.reduce(
      (best, datum, index) =>
        Math.abs(datum.time - targetTime) < Math.abs(values[best].time - targetTime)
          ? index
          : best,
      0,
    );
    onSelect(nearest);
  }

  return (
    <div className="video-condition-review">
      <div className="video-condition-head">
        <div>
          <span>영상과 동기화된 노면 상태</span>
          <strong>{current.score}점 · {gradeLabel[current.grade]}</strong>
        </div>
        <small>충격 전후 20초 · 흰 선은 영상 현재 시점</small>
      </div>
      <canvas
        ref={canvasRef}
        className="event-condition-canvas"
        onPointerDown={handlePointer}
        aria-label={`이벤트 ${eventDatum.id} 전후 20초의 노면 상태 점수. 현재 영상 시점 ${formatDuration(playheadTime)}, 점수 ${current.score}`}
      />
      <div className="legend event-condition-legend">
        <span><i className="legend-dot good" /> 80 이상 양호</span>
        <span><i className="legend-dot fair" /> 65–79 보통</span>
        <span><i className="legend-dot caution" /> 50–64 주의</span>
        <span><i className="legend-dot poor" /> 50 미만 영상 확인</span>
      </div>
    </div>
  );
}

function LatestSignalChart() {
  const draw = useMemo(
    () => (canvas: HTMLCanvasElement) => {
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const ratio = window.devicePixelRatio || 1;
      canvas.width = Math.max(1, Math.round(width * ratio));
      canvas.height = Math.max(1, Math.round(height * ratio));
      const ctx = canvas.getContext("2d");
      if (!ctx || latestCapture.signal.length < 2) return;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      ctx.clearRect(0, 0, width, height);

      const pad = { left: 42, right: 24, top: 28, bottom: 28 };
      const plotWidth = width - pad.left - pad.right;
      const plotHeight = height - pad.top - pad.bottom;
      const firstTime = latestCapture.signal[0].time;
      const lastTime = latestCapture.signal[latestCapture.signal.length - 1].time;
      const maxAccel = Math.max(...latestCapture.signal.map((point) => point.accel), 1);
      const maxGyro = Math.max(...latestCapture.signal.map((point) => point.gyro), 1);
      const x = (time: number) => pad.left + ((time - firstTime) / (lastTime - firstTime)) * plotWidth;
      const y = (value: number, max: number) => pad.top + plotHeight - (value / max) * plotHeight;

      ctx.fillStyle = "rgba(6, 27, 25, .86)";
      ctx.fillRect(pad.left, pad.top, plotWidth, plotHeight);
      ctx.strokeStyle = "rgba(143, 174, 166, .15)";
      ctx.lineWidth = 1;
      for (let index = 0; index <= 4; index += 1) {
        const gridY = pad.top + (plotHeight * index) / 4;
        ctx.beginPath();
        ctx.moveTo(pad.left, gridY);
        ctx.lineTo(width - pad.right, gridY);
        ctx.stroke();
      }

      const drawSeries = (key: "accel" | "gyro", max: number, color: string) => {
        ctx.beginPath();
        latestCapture.signal.forEach((point, index) => {
          const px = x(point.time);
          const py = y(point[key], max);
          if (index === 0) ctx.moveTo(px, py);
          else ctx.lineTo(px, py);
        });
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.stroke();
      };

      drawSeries("accel", maxAccel, "#27d7ad");
      drawSeries("gyro", maxGyro, "#f6b84b");

      latestCapture.events.forEach((event, index) => {
        const eventX = x(event.time);
        ctx.strokeStyle = event.visualStatus === "supported" ? "#ff6b66" : "#f6b84b";
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.moveTo(eventX, pad.top);
        ctx.lineTo(eventX, height - pad.bottom);
        ctx.stroke();
        ctx.setLineDash([]);
        if (index === 0) {
          ctx.fillStyle = "#ff918d";
          ctx.font = '650 11px "Noto Sans KR", Arial, sans-serif';
          ctx.fillText("영상 확인 후보 9곳", Math.min(eventX + 7, width - 112), 17);
        }
      });
      ctx.fillStyle = "rgba(226, 239, 235, .84)";
      ctx.font = "11px Arial";
      ctx.fillText("0초", pad.left, height - 8);
      ctx.textAlign = "right";
      ctx.fillText(`${lastTime.toFixed(1)}초`, width - pad.right, height - 8);
      ctx.textAlign = "left";
    },
    [],
  );
  const canvasRef = useCanvasResize(draw);

  return (
    <div className="latest-signal-wrap">
      <canvas
        ref={canvasRef}
        className="latest-signal-canvas"
        aria-label={`2026년 8월 9일 ${formatDuration(latestCapture.metadata.durationSec)} 전체 주행의 가속도와 회전 신호. 센서와 동기 영상으로 확인한 후보는 ${latestCapture.events.length}곳입니다.`}
      />
      <div className="latest-signal-legend">
        <span><i className="accel" /> 가속도 크기</span>
        <span><i className="gyro" /> 회전 속도</span>
        <span><i className="candidate" /> 센서+영상 검토 후보 {latestCapture.events.length}곳</span>
      </div>
    </div>
  );
}

function LatestCaptureMap() {
  const mapNodeRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<import("leaflet").Map | null>(null);
  const [selectedEvent, setSelectedEvent] = useState<LatestCaptureEvent>(latestCapture.events[0]);
  const validLocations = useMemo(
    () => latestCapture.location.filter((point) => point.seconds_elapsed >= 0),
    [],
  );

  useEffect(() => {
    let disposed = false;
    void import("leaflet").then((leaflet) => {
      if (disposed || !mapNodeRef.current || mapInstanceRef.current) return;

      const map = leaflet.map(mapNodeRef.current, {
        zoomControl: true,
        scrollWheelZoom: true,
        preferCanvas: true,
      });
      mapInstanceRef.current = map;

      const aerialLayer = leaflet.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        {
          attribution: "Tiles &copy; Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community",
          maxZoom: 20,
        },
      );
      const streetLayer = leaflet.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 20,
      });
      aerialLayer.addTo(map);
      leaflet.control.layers(
        { "항공사진": aerialLayer, "일반지도": streetLayer },
        undefined,
        { collapsed: false, position: "topright" },
      ).addTo(map);

      for (let index = 0; index < validLocations.length - 1; index += 1) {
        const point = validLocations[index];
        const next = validLocations[index + 1];
        const color = point.eligible ? scoreColor(point.score) : "#5f7772";
        leaflet.polyline(
          [[point.latitude, point.longitude], [next.latitude, next.longitude]],
          { color, weight: point.eligible ? 6 : 4, opacity: point.eligible ? 0.9 : 0.42 },
        )
          .bindTooltip(
            point.eligible
              ? `${formatDuration(point.seconds_elapsed)} · 상대 노면 점수 ${point.score}점`
              : `${formatDuration(point.seconds_elapsed)} · 저속·회전 구간 제외`,
            { sticky: true },
          )
          .addTo(map);
      }

      const start = validLocations[0];
      const finish = validLocations[validLocations.length - 1];
      [
        { point: start, label: "기록 시작", color: "#f4f7f6" },
        { point: finish, label: "기록 종료", color: "#27d7ad" },
      ].forEach(({ point, label, color }) => {
        leaflet.circleMarker([point.latitude, point.longitude], {
          radius: 6,
          color,
          fillColor: "#071716",
          fillOpacity: 1,
          weight: 2,
        })
          .bindTooltip(label, { sticky: true })
          .addTo(map);
      });

      latestCapture.events.forEach((event) => {
        leaflet.circle([event.latitude, event.longitude], {
          radius: event.accuracy,
          color: event.visualStatus === "supported" ? "#ff6b66" : "#f6b84b",
          weight: 1,
          dashArray: "4 5",
          fillOpacity: 0.025,
          interactive: false,
        }).addTo(map);
        const marker = leaflet.circleMarker([event.latitude, event.longitude], {
          radius: 8,
          color: "#f4f7f6",
          fillColor: event.visualStatus === "supported" ? "#ff6b66" : "#f6b84b",
          fillOpacity: 0.96,
          weight: 2,
        }).addTo(map);
        marker.bindTooltip(
          `SPOT ${String(event.id).padStart(2, "0")} · ${event.surfaceLabel} · ${event.peakAcceleration.toFixed(1)} m/s²`,
          { sticky: true },
        );
        marker.bindPopup(
          `<div class="impact-popup"><img src="${event.frame}" alt="동탄 이벤트 실제 동기 영상 프레임"><strong>${event.surfaceLabel}</strong><span>${formatDuration(event.time)} · ${event.decision}</span></div>`,
          { maxWidth: 220, closeButton: false },
        );
        marker.on("click", () => setSelectedEvent(event));
      });

      const routeBounds = leaflet.latLngBounds(validLocations.map((point) => [point.latitude, point.longitude]));
      map.fitBounds(routeBounds, { padding: [28, 28], maxZoom: 16, animate: false });
      window.setTimeout(() => map.invalidateSize({ animate: false }), 0);
    });

    return () => {
      disposed = true;
      mapInstanceRef.current?.remove();
      mapInstanceRef.current = null;
    };
  }, [validLocations]);

  return (
    <div className="latest-map-shell">
      <div
        ref={mapNodeRef}
        className="actual-map latest-actual-map"
        role="region"
        aria-label="동탄 24분 46초 전체 주행의 GPS 경로, 상대 노면 점수 구간, 센서와 영상으로 검토한 이벤트"
      />
      <div className="latest-map-legend" aria-label="동탄 센서 신호 범례">
        <span><i className="good" /> 80 이상 양호</span>
        <span><i className="fair" /> 65–79 보통</span>
        <span><i className="caution" /> 50–64 주의</span>
        <span><i className="candidate" /> 50 미만 집중 확인</span>
        <span><i className="excluded" /> 저속·회전 제외</span>
        <span><i className="accuracy" /> 점선 원은 이벤트 GPS 오차</span>
      </div>
      <div className="latest-selected-event" aria-live="polite">
        <video controls playsInline preload="metadata" poster={selectedEvent.frame} key={selectedEvent.id}>
          <source src={selectedEvent.clip} type="video/mp4" />
        </video>
        <div>
          <span>SELECTED SPOT {String(selectedEvent.id).padStart(2, "0")} · 센서+영상</span>
          <h4>{selectedEvent.surfaceLabel}</h4>
          <p>{selectedEvent.visualEvidence}</p>
          <dl>
            <div><dt>시간</dt><dd>{formatDuration(selectedEvent.time)}</dd></div>
            <div><dt>최대 가속도</dt><dd>{selectedEvent.peakAcceleration.toFixed(1)} m/s²</dd></div>
            <div><dt>속도</dt><dd>{selectedEvent.speedKmh.toFixed(1)} km/h</dd></div>
            <div><dt>GPS 오차</dt><dd>±{selectedEvent.accuracy.toFixed(1)}m</dd></div>
          </dl>
          <small>{selectedEvent.visualStatus === "supported" ? "영상에서 노면 유형·경계가 확인된 후보" : "영상상 손상이 불명확한 센서 단독 후보"}</small>
        </div>
      </div>
    </div>
  );
}

export default function Home() {
  const worstIndex = useMemo(() => {
    let index = 0;
    latestCapture.windows.forEach((datum, current) => {
      if (!datum.eligible) return;
      if (!latestCapture.windows[index].eligible || datum.score < latestCapture.windows[index].score) index = current;
    });
    return index;
  }, []);
  const [, setSelectedIndex] = useState(worstIndex);
  const [mergedDatasetId, setMergedDatasetId] = useState<RoadDataset["id"]>("dongtan-2");
  const [mergedSelectedIndex, setMergedSelectedIndex] = useState(() => getRoadDataset("dongtan-2").defaultIndex);
  const [operationsView, setOperationsView] = useState<"overview" | "surface3d">("overview");
  const [selectedEvent, setSelectedEvent] = useState<LatestCaptureEvent>(latestCapture.events[0]);
  const [videoOffset, setVideoOffset] = useState(0);
  const [videoUrl, setVideoUrl] = useState<string | null>(null);
  const [videoName, setVideoName] = useState("");
  const [videoPlayheadTime, setVideoPlayheadTime] = useState(latestCapture.events[0].time - 1.5);
  const [liveReports, setLiveReports] = useState<LiveReport[]>([]);
  const [reportLoadState, setReportLoadState] = useState<"loading" | "ready" | "error">("loading");
  const [municipalFeedState, setMunicipalFeedState] = useState<"not_configured" | "connected" | "error">("not_configured");
  const videoRef = useRef<HTMLVideoElement>(null);
  const selectedRoadDataset = useMemo(() => getRoadDataset(mergedDatasetId), [mergedDatasetId]);
  const selectedRoadWindow = selectedRoadDataset.windows[Math.min(mergedSelectedIndex, selectedRoadDataset.windows.length - 1)];
  const selectMergedSegment = useCallback((datasetId: RoadDataset["id"], index: number) => {
    const dataset = getRoadDataset(datasetId);
    setMergedDatasetId(datasetId);
    setMergedSelectedIndex(Math.max(0, Math.min(dataset.windows.length - 1, index)));
  }, []);
  const eventClipUrl = selectedEvent.clip;
  const paperMetrics = useMemo(() => {
    const eligible = rideData.windows
      .filter((datum) => datum.speed >= 2 && datum.confidence >= 0.7)
      .map((datum) => ({
        ...datum,
        normalizedRms: datum.accelRms * Math.pow(5 / datum.speed, 1.15),
      }));
    const sorted = eligible.map((datum) => datum.normalizedRms).sort((a, b) => a - b);
    return {
      eligibleCount: eligible.length,
      highSeverityWindows: eligible.filter((datum) => datum.normalizedRms > 8).length,
      medianNormalizedRms: sorted[Math.floor(sorted.length / 2)] ?? 0,
      maxNormalizedRms: sorted[sorted.length - 1] ?? 0,
    };
  }, []);

  useEffect(() => () => {
    if (videoUrl) URL.revokeObjectURL(videoUrl);
  }, [videoUrl]);

  const loadLiveReports = useCallback(async () => {
    try {
      const response = await fetch("/api/reports", { cache: "no-store" });
      if (!response.ok) throw new Error("report fetch failed");
      const payload = await response.json() as {
        reports?: LiveReport[];
        municipalFeed?: { status?: "not_configured" | "connected" | "error"; count?: number };
      };
      setLiveReports(Array.isArray(payload.reports) ? payload.reports : []);
      setMunicipalFeedState(payload.municipalFeed?.status ?? "not_configured");
      setReportLoadState("ready");
    } catch {
      setMunicipalFeedState("error");
      setReportLoadState("error");
    }
  }, []);

  useEffect(() => {
    const initial = window.setTimeout(() => void loadLiveReports(), 0);
    const timer = window.setInterval(() => void loadLiveReports(), 15_000);
    return () => {
      window.clearTimeout(initial);
      window.clearInterval(timer);
    };
  }, [loadLiveReports]);

  function attachVideo(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    if (videoUrl) URL.revokeObjectURL(videoUrl);
    const url = URL.createObjectURL(file);
    setVideoUrl(url);
    setVideoName(file.name);
  }

  const openEvent = useCallback((eventDatum: LatestCaptureEvent) => {
    setSelectedEvent(eventDatum);
    setVideoPlayheadTime(Math.max(0, eventDatum.time - 1.5));
    const nearest = latestCapture.windows.reduce(
      (best, datum, index) =>
        Math.abs(datum.time - eventDatum.time) < Math.abs(latestCapture.windows[best].time - eventDatum.time)
          ? index
          : best,
      0,
    );
    setSelectedIndex(nearest);
    selectMergedSegment("dongtan-2", nearest);
    window.setTimeout(() => {
      document.getElementById("video-review")?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 120);
  }, [selectMergedSegment]);

  const openMergedEvent = useCallback((datasetId: RoadDataset["id"], eventDatum: RoadDataset["events"][number]) => {
    if (datasetId !== "dongtan-2") return;
    const latestEvent = latestCapture.events.find((item) => item.id === eventDatum.id);
    if (latestEvent) openEvent(latestEvent);
  }, [openEvent]);

  const latestScoreStyle = { "--score-angle": `${latestCapture.metadata.overallScore * 3.6}deg` } as CSSProperties;
  const urgentReportCount = liveReports.filter((report) => report.severity === "urgent").length;
  const officialReportCount = liveReports.filter((report) => report.source !== "r2d_citizen").length;
  const jumpToSection = useCallback((event: ReactMouseEvent<HTMLAnchorElement>, sectionId: string) => {
    event.preventDefault();
    window.history.pushState(null, "", `#${sectionId}`);
    document.getElementById(sectionId)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, []);

  return (
    <main>
      <header className="topbar">
        <a className="brand" href="#top" aria-label="R2D 홈">
          <span className="brand-mark">R2</span>
          <span>R2D</span>
        </a>
      </header>

      <nav className="mobile-jump-nav" aria-label="모바일 빠른 이동">
        <a href="#top" onClick={(event) => jumpToSection(event, "top")}>요약</a>
        <a href="#merged-map" onClick={(event) => jumpToSection(event, "merged-map")}>관제</a>
        <a href="#latest-capture" onClick={(event) => jumpToSection(event, "latest-capture")}>센서</a>
        <a href="#live-reports" onClick={(event) => jumpToSection(event, "live-reports")}>제보</a>
      </nav>

      <section className="hero" id="top">
        <div className="eyebrow">MUNICIPAL ROAD OPERATIONS / LIVE CONDITION VIEW</div>
        <div className="hero-grid">
          <div className="hero-copy">
            <h1>도로 상태를 한눈에.<br />현장 대응을 빠르게.</h1>
            <p>센서 주행, 충격 이벤트와 현장 제보를 한 지도에서 확인하고 대응 우선순위를 정합니다.</p>
            <div className="hero-actions">
              <a className="button primary" href="#merged-map">통합 관제 지도 열기</a>
              <a className="button" href="#live-reports">민원·제보 현황</a>
            </div>
          </div>
          <div className="score-panel">
            <div className="score-ring latest-quality-ring" style={latestScoreStyle}>
              <div>
                <strong>{latestCapture.metadata.overallScore}</strong>
                <span>/ 100</span>
              </div>
            </div>
            <div className="score-copy">
              <span className="status-pill latest">공무원 관제용 위험 구간</span>
              <h2>최근 동탄 주행 노면 점수 {latestCapture.metadata.overallScore}점</h2>
              <p>이번 주행 안에서 4초 구간을 비교한 프로토타입 점수입니다. 공인 IRI·PCI는 아닙니다.</p>
            </div>
          </div>
        </div>
        <div className="kpi-strip">
          <div><span>GPS 주행거리</span><strong>{latestCapture.metadata.routeDistanceKm.toFixed(2)} km</strong></div>
          <div><span>전체 기록</span><strong>{formatDuration(latestCapture.metadata.durationSec)}</strong></div>
          <div><span>GPS 포인트</span><strong>{latestCapture.metadata.gpsPoints.toLocaleString()}점</strong></div>
          <div><span>IMU 표본</span><strong>{((latestCapture.metadata.accelSamples + latestCapture.metadata.gyroSamples) / 1000).toFixed(1)}k</strong></div>
        </div>
      </section>

      <section className="merged-rides-section" id="merged-map">
        <div className="section-heading">
          <div>
            <span className="eyebrow">01 / MUNICIPAL OPERATIONS MAP</span>
            <h2>노면 신호·충격·시민 제보를<br />한 지도에서 관제</h2>
          </div>
          <div className="merged-dataset-summary">
            <span>누적 기록 <strong>{roadDatasets.length}개</strong></span>
            <span>분석 구간 <strong>{roadDatasets.reduce((sum, dataset) => sum + dataset.windows.length, 0).toLocaleString()}개</strong></span>
          </div>
        </div>

        <div className="operations-kpis" aria-label="실시간 도로 관제 현황">
          <div><span>센서 실측 기록</span><strong>{roadDatasets.length}</strong><small>GPS·IMU 주행</small></div>
          <div><span>지도 제보</span><strong>{liveReports.length}</strong><small>15초 자동 갱신</small></div>
          <div><span>긴급 확인</span><strong>{urgentReportCount}</strong><small>현장 우선 배정</small></div>
          <div><span>기관 연계 민원</span><strong>{officialReportCount}</strong><small>{municipalFeedState === "connected" ? "공식 피드 연결" : municipalFeedState === "error" ? "연결 오류" : "API 권한 대기"}</small></div>
        </div>

        <div className="operations-view-panel">
          <div className="operations-view-header">
            <div>
              <span className="card-label">CUMULATIVE MAP + SELECTED ROAD 3D</span>
              <h3>통합 도로 관제</h3>
              <p>전체 경로를 확인하고, 색상 구간을 누르면 같은 화면에서 3D 노면 형상을 분석합니다.</p>
            </div>
            <div className="operations-view-tabs" role="tablist" aria-label="통합 도로 관제 보기 방식">
              <button
                type="button"
                role="tab"
                aria-selected={operationsView === "overview"}
                className={operationsView === "overview" ? "active" : ""}
                onClick={() => setOperationsView("overview")}
              >
                전체 관제 지도
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={operationsView === "surface3d"}
                className={operationsView === "surface3d" ? "active" : ""}
                onClick={() => setOperationsView("surface3d")}
              >
                선택 구간 3D
              </button>
            </div>
          </div>

          {operationsView === "overview" ? (
            <article className="card merged-map-card operations-view-content">
              <div className="card-topline">
                <div>
                  <span className="card-label">ALL RIDES / SCORES / EVENTS / REPORTS</span>
                  <h3>전체 경로와 현장 이슈</h3>
                </div>
                <span className="verified">새 데이터는 이 지도에 누적</span>
              </div>
              <p className="merged-map-intro">실측 경로, 노면 점수, 충격 이벤트 후보와 시민 제보를 한 지도에서 봅니다.</p>
              <UnifiedRideMap
                selectedDatasetId={mergedDatasetId}
                selectedIndex={mergedSelectedIndex}
                onSelect={selectMergedSegment}
                onOpen3D={() => setOperationsView("surface3d")}
                onEventSelect={openMergedEvent}
                liveReports={liveReports}
              />
            </article>
          ) : (
            <div className="operations-view-content">
              <RoadTwin3D
                key={selectedRoadDataset.id}
                dataset={selectedRoadDataset}
                selectedIndex={mergedSelectedIndex}
                onSelect={setMergedSelectedIndex}
              />
            </div>
          )}
        </div>
      </section>

      <section className="latest-capture-section" id="latest-capture">
        <div className="section-heading">
          <div>
            <span className="eyebrow">02 / LATEST SENSOR SIGNAL</span>
            <h2>최신 실측 요약과 센서 신호</h2>
          </div>
          <div className="download-group">
            <a href="/latest-capture/latest-capture-summary.csv" download>정제 신호 CSV</a>
            <a href="/latest-capture/dongtan-route-scores.csv" download>경로·점수 CSV</a>
            <a href="/latest-capture/dongtan-route.geojson" download>GeoJSON</a>
          </div>
        </div>

        {false && <article className="card dongtan-first-registry">
          <div className="card-topline">
            <div>
              <span className="card-label">{dongtanFirstCapture.metadata.id} / DONGTAN RIDE 01</span>
              <h3>동탄 1차 데이터 등록 완료 · {dongtanFirstCapture.metadata.device}</h3>
            </div>
            <span className="provisional">영상 없음 · 센서 단독 분석</span>
          </div>
          <div className="latest-map-metrics">
            <div><span>전체 기록</span><strong>{formatDuration(dongtanFirstCapture.metadata.durationSec)}</strong></div>
            <div><span>주행거리</span><strong>{dongtanFirstCapture.metadata.routeDistanceKm.toFixed(2)}km</strong></div>
            <div><span>GPS 포인트</span><strong>{dongtanFirstCapture.metadata.gpsPoints.toLocaleString()}점</strong></div>
            <div><span>점수 적용 구간</span><strong>{dongtanFirstCapture.metadata.eligibleWindows}개</strong></div>
          </div>
          <p className="dongtan-first-note">
            시작 시각이 2차 기록보다 약 16초 빠르고 경로가 겹쳐, 현재는 반복주행이 아니라 같은 시간대의 이중기기 센서 기록으로 관리합니다. 영상이 없어 이벤트는 모두 ‘센서 단독 후보’이며 현장 확정 판정에는 사용하지 않습니다.
          </p>
        </article>}

        <div className="latest-capture-grid">
          {false && <article className="card latest-map-card">
            <div className="card-topline">
              <div>
                <span className="card-label">MEASURED GPS + IMU + VIDEO / DONGTAN RIDE 02</span>
                <h3>동탄 2차 실측 위치와 센서 신호</h3>
              </div>
              <span className="verified">전체 경로 확인됨</span>
            </div>
            <div className="latest-map-metrics">
              <div><span>주행거리</span><strong>{latestCapture.metadata.routeDistanceKm.toFixed(2)}km</strong></div>
              <div><span>GPS 포인트</span><strong>{latestCapture.metadata.gpsPoints.toLocaleString()}점</strong></div>
              <div><span>점수 적용 구간</span><strong>{latestCapture.metadata.eligibleWindows}개</strong></div>
              <div><span>중앙 GPS 정확도</span><strong>±{latestCapture.metadata.medianHorizontalAccuracyM.toFixed(1)}m</strong></div>
            </div>
            <LatestCaptureMap />
            <p className="latest-map-warning">
              선 색은 속도·회전 조건을 통과한 4초 구간의 <strong>주행 내 상대 노면 점수</strong>입니다.
              붉은 SPOT은 센서와 동기 영상을 함께 검토한 후보이며, 균열·포트홀의 규격 실측값은 아닙니다.
            </p>
          </article>}

          <article className="card latest-summary-card">
            <div className="card-topline">
              <div>
                <span className="card-label">{latestCapture.metadata.id}</span>
                <h3>화성시 동탄구 여울동 부근 · {latestCapture.metadata.device}</h3>
              </div>
              <span className="verified">센서·영상 동기화</span>
            </div>
            <div className="latest-quality-score">
              <strong>{latestCapture.metadata.overallScore}</strong>
              <span>/ 100<br />상대 노면 점수</span>
            </div>
            <dl className="latest-metrics">
              <div><dt>전체 기록</dt><dd>{formatDuration(latestCapture.metadata.durationSec)}</dd></div>
              <div><dt>표본률</dt><dd>{latestCapture.metadata.sampleRateHz.toFixed(1)} Hz</dd></div>
              <div><dt>GPS</dt><dd>{latestCapture.metadata.gpsPoints.toLocaleString()}점 · {latestCapture.metadata.routeDistanceKm.toFixed(2)}km</dd></div>
              <div><dt>영상 동기</dt><dd>시작 차이 {latestCapture.video.syncOffsetSec.toFixed(2)}초</dd></div>
            </dl>
            <p className="latest-verdict">
              <b>{latestCapture.event.decision}</b><br />
              {latestCapture.event.reason}
            </p>
          </article>

          <article className="card latest-signal-card">
            <div className="card-topline">
              <div>
                <span className="card-label">FULL SENSOR DATA / {(latestCapture.metadata.accelSamples + latestCapture.metadata.gyroSamples).toLocaleString()} SAMPLES</span>
                <h3>가속도 {latestCapture.metadata.accelSamples.toLocaleString()} + 자이로 {latestCapture.metadata.gyroSamples.toLocaleString()}</h3>
              </div>
              <span className="provisional">취급 진동 가능성</span>
            </div>
            <LatestSignalChart />
            <div className="latest-event-strip">
              <div><span>영상 검토 후보</span><strong>{latestCapture.events.length}곳</strong></div>
              <div><span>점수 적용</span><strong>{latestCapture.metadata.eligibleWindows} / {latestCapture.metadata.totalWindows}</strong></div>
              <div><span>대표 유형</span><strong>포장·도색 경계</strong></div>
            </div>
          </article>

          {false && <aside className="latest-limitations">
            <div>
              <span>시간 동기화</span>
              <strong>센서·영상 직접 연결</strong>
              <p>{latestCapture.video.syncNote}</p>
            </div>
            <div>
              <span>GPS 경로</span>
              <strong>1,487점 · 2.44km</strong>
              <p>실제 이동 경로는 확인되지만 중앙 오차가 약 ±14.2m라 차로 폭 단위 정밀 위치는 아닙니다.</p>
            </div>
            <div>
              <span>분류 정확도</span>
              <strong>현장 정답 라벨 필요</strong>
              <p>영상으로 표면·경계를 확인했지만 실제 균열 폭·단차·포트홀 깊이 라벨이 없어 정확도 수치는 아직 산정하지 않습니다.</p>
            </div>
          </aside>}
        </div>
      </section>

      <section className="live-report-section" id="live-reports">
        <div className="section-heading">
          <div>
            <span className="eyebrow">03 / MUNICIPAL REPORT QUEUE</span>
            <h2>공무원용 민원·현장제보<br />통합 확인 대기열</h2>
          </div>
          <span className={`report-sync-status ${reportLoadState}`}>
            <i />
            {reportLoadState === "loading" && "처음 불러오는 중"}
            {reportLoadState === "ready" && `R2D 제보 15초 동기화 · 기관 ${municipalFeedState === "connected" ? "피드 연결" : "API 대기"}`}
            {reportLoadState === "error" && "연결 재시도 중"}
          </span>
        </div>

        <div className="live-report-grid">
          <MunicipalReportComposer
            datasetLabel={selectedRoadDataset.label}
            point={selectedRoadWindow}
            onSaved={() => void loadLiveReports()}
          />

          <article className="card report-feed">
            <div className="report-feed-head">
              <div>
                <span className="card-label">OPERATIONS QUEUE</span>
                <h3>지도 민원·제보 큐</h3>
              </div>
              <strong>{liveReports.length}</strong>
            </div>
            <div className="report-feed-list" aria-live="polite">
              {reportLoadState === "loading" && <p className="report-empty">제보를 불러오고 있습니다…</p>}
              {reportLoadState === "error" && <p className="report-empty">일시적으로 불러오지 못했습니다. 15초 후 자동 재시도합니다.</p>}
              {reportLoadState === "ready" && liveReports.length === 0 && (
                <p className="report-empty">아직 등록된 시민 제보가 없습니다. 첫 현장 제보를 남겨 주세요.</p>
              )}
              {liveReports.slice(0, 8).map((report) => (
                <article className="report-feed-item" key={report.id}>
                  <i className={report.severity} />
                  <div>
                    <span>
                      {reportSourceLabel(report.source)} · {reportCategoryLabel[report.category] ?? "기타"} · {report.severity === "urgent" ? "긴급 확인" : "주의"}
                    </span>
                    <strong>{report.locationLabel || "위치명 없음"}</strong>
                    <p>{report.description}</p>
                    <small>
                      {reportStatusLabel(report.status, report.officialStatus)} · {new Date(report.createdAt).toLocaleString("ko-KR")} · {report.latitude.toFixed(5)}, {report.longitude.toFixed(5)}
                    </small>
                  </div>
                </article>
              ))}
            </div>
          </article>
        </div>

        <div className="official-channel-bar">
          <strong>공식 민원 채널</strong>
          <a href="https://eungdapso.seoul.go.kr/main.do" target="_blank" rel="noreferrer">서울시 응답소</a>
          <a href="https://www.epeople.go.kr/" target="_blank" rel="noreferrer">국민신문고</a>
          <a href="https://www.safetyreport.go.kr/index.html" target="_blank" rel="noreferrer">안전신문고</a>
          <small>개별 민원 좌표·처리상태는 기관 API 승인 후 지도에 연결됩니다.</small>
        </div>
      </section>

      <section className="video-section" id="video-review">
        <div className="section-heading">
          <div>
            <span className="eyebrow">04 / VIDEO REVIEW</span>
            <h2>충격 신호와 영상을 함께 검토</h2>
          </div>
          <span className="clip-ready">동탄 2차 이벤트 클립 {latestCapture.events.length}개 포함</span>
        </div>

        <div className="video-grid">
          <article className="card video-stage">
            <div className="video-event-badge">
              <span>EVENT {String(selectedEvent.id).padStart(2, "0")}</span>
              <strong>{selectedEvent.peakAcceleration.toFixed(1)} m/s²</strong>
            </div>
            <video
              key={`${videoUrl ? "local" : "clip"}-${selectedEvent.id}`}
              ref={videoRef}
              src={videoUrl ?? eventClipUrl}
              poster={selectedEvent.frame}
              controls
              playsInline
              autoPlay
              preload="metadata"
              onTimeUpdate={(event) => {
                if (videoUrl) {
                  const eventAt = latestEventVideoTime(selectedEvent) + videoOffset;
                  setVideoPlayheadTime(selectedEvent.time + event.currentTarget.currentTime - eventAt);
                } else {
                  setVideoPlayheadTime(selectedEvent.time + event.currentTarget.currentTime - 3);
                }
              }}
              onLoadedMetadata={(event) => {
                event.currentTarget.currentTime = videoUrl
                  ? Math.max(0, latestEventVideoTime(selectedEvent) + videoOffset - 1.5)
                  : 1.5;
              }}
            />
            <div className="video-controls">
              <div>
                <span>원본 영상 기준 충격 시점</span>
                <strong>{formatDuration(latestEventVideoTime(selectedEvent) + videoOffset)}</strong>
              </div>
              <div className="video-source-actions">
                {videoUrl && (
                  <button
                    type="button"
                    className="embedded-button"
                    onClick={() => {
                      URL.revokeObjectURL(videoUrl);
                      setVideoUrl(null);
                      setVideoName("");
                    }}
                  >
                    내장 클립 보기
                  </button>
                )}
                <label className="file-button">
                  <input type="file" accept="video/*,.mov" onChange={attachVideo} />
                  {videoName || "원본 MOV로 확인"}
                </label>
              </div>
            </div>
            {videoUrl ? (
              <div className="offset-control">
                <label htmlFor="offset">영상 오프셋 보정 <strong>{videoOffset > 0 ? "+" : ""}{videoOffset}s</strong></label>
                <input
                  id="offset"
                  type="range"
                  min="-120"
                  max="120"
                  step="1"
                  value={videoOffset}
                  onChange={(event) => setVideoOffset(Number(event.target.value))}
                />
              </div>
            ) : (
              <div className="clip-context" aria-label="원본 기준 충격 전후 3초를 추출한 6초 영상">
                <span>충격 전 1.5초부터 재생</span>
                <i><b /></i>
                <span>충격 후 3초까지 확인</span>
              </div>
            )}
            <EventConditionGraph
              eventDatum={selectedEvent}
              playheadTime={videoPlayheadTime}
              onSelect={setSelectedIndex}
            />
            <p className="micro-note">
              {videoUrl
                ? "선택한 원본은 브라우저 안에서만 열리며 서버로 업로드되지 않습니다."
                : "동탄 2차 원본에서 이벤트 전후 약 3초를 추출한 클립입니다. 이벤트를 누르면 충격 1.5초 전부터 바로 재생됩니다."}
            </p>
          </article>

          <div className="event-list">
            {latestCapture.events.map((eventDatum) => (
              <button
                type="button"
                className={`event-card ${selectedEvent.id === eventDatum.id ? "selected" : ""}`}
                key={eventDatum.id}
                onClick={() => openEvent(eventDatum)}
                aria-pressed={selectedEvent.id === eventDatum.id}
              >
                <img src={eventDatum.frame} alt={`충격 이벤트 ${eventDatum.id} 영상 프레임`} />
                <span className="event-number">{String(eventDatum.id).padStart(2, "0")}</span>
                <span className="event-data">
                  <strong>{eventDatum.peakAcceleration.toFixed(1)} m/s²</strong>
                  <small>주행 {formatDuration(eventDatum.time)} · 영상 {formatDuration(latestEventVideoTime(eventDatum) + videoOffset)}</small>
                </span>
                <span className="event-arrow">▶</span>
              </button>
            ))}
          </div>
        </div>
        {false && <details className="smap-integration" open>
          <summary>현재 영상 프레임을 기준으로 한 카메라 장착 교정</summary>
          <div className="smap-grid">
            <div><strong>현재 문제</strong><span>카메라가 거의 수직 아래를 향하고 자전거 프레임이 화면 중앙을 크게 가려, 전방 균열과 이벤트 원인을 확인하기 어렵습니다.</span></div>
            <div><strong>권장 각도</strong><span>광축을 수평보다 아래 15–25°로 두고, 소실점은 화면 위쪽 20–30%, 노면은 화면의 70% 이상이 되게 맞춥니다.</span></div>
            <div><strong>권장 장착</strong><span>가로 방향·광각 1×, 노면에서 0.9–1.2 m 높이. 핸들 회전에 따라 움직이지 않는 헤드튜브·프레임 고정 브래킷이 좋습니다.</span></div>
            <div><strong>출발 전 확인</strong><span>정지 상태 10초 촬영 후 자전거 부품이 하단 10% 이내인지, 5–15 m 앞 노면과 차선 양쪽이 함께 보이는지 확인합니다.</span></div>
          </div>
        </details>}
      </section>

      {false && <><section className="quality-section" id="data-quality">
        <div className="section-heading">
          <div>
            <span className="eyebrow">04 / DATA CONFIDENCE</span>
            <h2>이번 결과에서 믿을 수 있는 것</h2>
          </div>
        </div>
        <div className="quality-grid">
          <article className="quality-card strong">
            <span>GPS</span>
            <strong>전체 경로 복원</strong>
            <div className="progress"><i style={{ width: "99%" }} /></div>
            <p>phyphox Location.csv 2,997개 포인트. 출발·복귀 지점이 일치합니다.</p>
          </article>
          <article className="quality-card partial">
            <span>IMU</span>
            <strong>전체 100.0%</strong>
            <div className="progress"><i style={{ width: "100%" }} /></div>
            <p>새 CSV로 선형가속도·자이로·자기장·자세 2,995.16초가 모두 복구됐습니다.</p>
          </article>
          <article className="quality-card caution">
            <span>VIDEO SYNC</span>
            <strong>± 보정 필요</strong>
            <div className="progress"><i style={{ width: "74%" }} /></div>
            <p>주행 시각과 영상 길이로 맞춘 잠정 정렬입니다. 프레임 확인 후 보정하세요.</p>
          </article>
        </div>
      </section>

      <section className="paper-method-section" id="paper-method">
        <div className="section-heading">
          <div>
            <span className="eyebrow">05 / RESEARCH TRANSFER</span>
            <h2>자전거·전동킥보드 노면 연구를<br />R2D 지표로 가져왔습니다.</h2>
          </div>
          <a
            className="paper-source-link"
            href="https://doi.org/10.1016/j.cscm.2022.e00889"
            target="_blank"
            rel="noreferrer"
          >
            Cafiso et al. (2022) 원문
          </a>
        </div>

        <div className="paper-metric-strip">
          <article>
            <span>분석 가능 창</span>
            <strong>{paperMetrics.eligibleCount.toLocaleString()}</strong>
            <small>속도 2 m/s 이상 · 신뢰도 70% 이상</small>
          </article>
          <article>
            <span>속도보정 RMS 중앙값</span>
            <strong>{paperMetrics.medianNormalizedRms.toFixed(2)}</strong>
            <small>m/s² · 자전거 기준속도 5 m/s</small>
          </article>
          <article className="research-alert">
            <span>8 m/s² 초과 창</span>
            <strong>{paperMetrics.highSeverityWindows}</strong>
            <small>겹치는 4초 창 · 고충격 후보</small>
          </article>
          <article>
            <span>보정 RMS 최댓값</span>
            <strong>{paperMetrics.maxNormalizedRms.toFixed(2)}</strong>
            <small>m/s² · 현장·영상 확인 필요</small>
          </article>
        </div>

        <div className="paper-transfer-grid">
          <article className="paper-transfer-card applied">
            <span>이번 버전에 적용</span>
            <h3>자전거 속도 보정 RMS</h3>
            <p>주행속도가 다르면 같은 노면도 진동 크기가 달라집니다. 논문에서 제시한 자전거 기준속도 5 m/s와 지수 1.15를 사용해 선택 구간마다 보정 RMS를 함께 표시합니다.</p>
            <code>RMSₙ = RMS × (5 / 현재속도)<sup>1.15</sup></code>
          </article>
          <article className="paper-transfer-card applied">
            <span>이번 버전에 적용</span>
            <h3>고충격 후보와 일반 거칠기 분리</h3>
            <p>논문은 반복적으로 나타나는 평균 RMS와 우발적인 이상치를 분리했습니다. R2D도 8 m/s² 초과값을 포트홀 확정이 아닌 ‘영상·현장 확인 후보’로만 표시합니다.</p>
            <code>보정 RMS &gt; 8 m/s² → 고충격 검토</code>
          </article>
          <article className="paper-transfer-card next">
            <span>원시 IMU 재처리 필요</span>
            <h3>ISO 2631 승차감 RMSw</h3>
            <p>0.5–20 Hz 구간을 1/3 옥타브 대역으로 나누고 사람의 승차감 민감도 가중치를 적용하는 방식입니다. 현재 100.5Hz 원시 데이터면 계산 가능하지만, 기존 고주파 비율과는 다른 별도 지표로 산출해야 합니다.</p>
            <code>RMSw = √Σ(Wᵢaᵢ)²</code>
          </article>
          <article className="paper-transfer-card next">
            <span>다음 반복주행부터</span>
            <h3>4초 창 + 10m 도로구간 이중 표기</h3>
            <p>현재 4초 창은 영상 동기화에 유리하고, 논문의 10m 구간은 유지보수 지도에 유리합니다. 다음 분석에서는 두 단위를 함께 저장해 이벤트 검토와 도로 관리 결과를 연결합니다.</p>
            <code>영상 검토: 4초 · 유지관리: 10m</code>
          </article>
        </div>

        <p className="paper-caution">
          논문의 8 m/s² 기준은 통제된 반복주행과 실제 파손 측량으로 검증된 연구 참고값입니다. 현재 R2D 값은 4초 창과 단일 주행에 적용한 잠정 비교이므로, 14개 초과 창을 14개 포트홀로 해석하면 안 됩니다.
        </p>

        <div className="research-bibliography">
          <div className="research-bibliography-heading">
            <span>REFERENCES USED IN THIS DASHBOARD</span>
            <h3>현재 분석에 실제로 반영한 참고 논문 전체</h3>
            <p>제목·연구진·발표연도를 원문 기준으로 적고, R2D에 적용한 범위를 함께 구분했습니다.</p>
          </div>
          <div className="research-reference-list">
            <article>
              <span className="reference-year">2022</span>
              <div>
                <h4>Urban road pavements monitoring and assessment using bike and e-scooter as probe vehicles</h4>
                <p><b>연구진</b> Salvatore Cafiso · Alessandro Di Graziano · Valeria Marchetta · Giuseppina Pappalardo</p>
                <small>적용: 자전거 기준속도 보정 RMS, 이상치 분리, ISO 2631-1 가중 진동, 10m 관리구간 원칙</small>
              </div>
              <a href="https://doi.org/10.1016/j.cscm.2022.e00889" target="_blank" rel="noreferrer">원문</a>
            </article>
            <article>
              <span className="reference-year">2025</span>
              <div>
                <h4>차량 모션 센서를 활용한 CNN-BiLSTM 기반의 도로 노면 상태 분류 연구</h4>
                <p><b>연구진</b> 윤태진 · 김정구 · 임선빈 · 정슬</p>
                <small>적용: 저속 주행 신호를 4초 시계열 창으로 구성하는 원칙. CNN-BiLSTM 분류 결과 자체는 현재 데이터에 적용하지 않음</small>
              </div>
              <a href="https://www.dbpia.co.kr/journal/articleDetail?nodeId=NODE12245033" target="_blank" rel="noreferrer">서지정보</a>
            </article>
            <article>
              <span className="reference-year">2024</span>
              <div>
                <h4>도로 노면 표시를 이용한 정밀지도 제작에 대한 연구</h4>
                <p><b>연구진</b> 정준석 · 김원균</p>
                <small>적용: 3D LiDAR 반사강도에서 도로 노면표시를 추출하고 주행 궤적에 누적하는 정밀지도 데이터 구조</small>
              </div>
              <a href="https://www.dbpia.co.kr/journal/articleDetail?nodeId=NODE11798427" target="_blank" rel="noreferrer">서지정보</a>
            </article>
          </div>
          <p className="research-reference-note">위 목록은 첨부된 논문 전체가 아니라, 현재 대시보드의 계산식·분석 창·정밀지도 설계에 실제로 사용한 논문 전체입니다.</p>
        </div>
      </section>

      <section className="method-section">
        <div className="method-intro">
          <span className="eyebrow">06 / METHOD</span>
          <h2>논문은 모델이 아니라<br />검증 가능한 원칙으로 적용했습니다.</h2>
          <p>레이블이 없는 한 번의 주행을 딥러닝 결과처럼 포장하지 않고, 재현 가능한 특징 추출과 신뢰도 판정만 가져왔습니다.</p>
        </div>
        <div className="method-list">
          <div><span>01</span><strong>4초 시계열 창</strong><p>CNN-BiLSTM 연구의 저속 주행 시퀀스 길이를 적용하고 2초씩 이동했습니다.</p></div>
          <div><span>02</span><strong>시간 + 주파수 특징</strong><p>RMS·피크·저크와 8-25Hz 에너지 비율을 함께 사용했습니다.</p></div>
          <div><span>03</span><strong>센서 융합 신뢰도</strong><p>속도·GPS 정확도·자이로 회전량으로 손에 든 휴대폰의 잡음을 표시했습니다.</p></div>
          <div><span>04</span><strong>보수적 이벤트 판정</strong><p>상위 충격은 ‘검토 필요’로만 제시하며 포트홀이나 과속방지턱으로 확정하지 않습니다.</p></div>
        </div>
      </section>

      <section className="precision-map-section">
        <div className="section-heading">
          <div>
            <span className="eyebrow">07 / PRECISION MAP READINESS</span>
            <h2>논문의 정밀지도 원칙을<br />자전거도로 데이터 구조로 적용</h2>
          </div>
          <span className="prototype-flag">정확도 검증 준비도 46 / 100</span>
        </div>
        <div className="precision-map-grid">
          <article className="precision-map-card applied">
            <span>논문에서 적용</span>
            <h3>노면표시를 위치 기준점으로 사용</h3>
            <p>3D LiDAR 포인트의 반사강도와 높이·형상을 함께 사용해 자전거도로 경계선, 중앙선, 문자와 방향표시를 추출하고 주행 궤적에 누적합니다.</p>
            <ul>
              <li>원시 필드: x, y, z, intensity, timestamp</li>
              <li>자세 필드: pose xyz, roll, pitch, yaw</li>
              <li>결과: PCD·PLY·LAZ + 노면표시 분류 레이어</li>
            </ul>
          </article>
          <article className="precision-map-card missing">
            <span>이번 주행에 부족</span>
            <h3>반사강도·정밀 자세·기준점</h3>
            <p>현재 GPS와 단안 영상만으로는 포인트클라우드 기반 정밀지도를 만들 수 없습니다. 특히 LiDAR intensity, 센서 간 외부표정, RTK 기준궤적이 필요합니다.</p>
            <ul>
              <li>RTK GNSS 원시 로그와 보정정보</li>
              <li>LiDAR 원본 포인트와 시간정보</li>
              <li>카메라·LiDAR·IMU 시간동기 및 장착변환</li>
            </ul>
          </article>
          <article className="precision-map-card next">
            <span>다음 수집 권장</span>
            <h3>정지 스캔 + 저속 반복주행</h3>
            <p>도로표시가 많은 기준구간을 먼저 정지 또는 보행 속도로 스캔하고, 같은 구간을 3회 이상 왕복해 지도 정합 오차와 점수 재현성을 따로 검증합니다.</p>
            <ul>
              <li>검증 기준점 5–10개와 실측 좌표</li>
              <li>균열·패치·맨홀·턱 수동 라벨</li>
              <li>비·조도·타이어압·속도·장착자세 기록</li>
            </ul>
          </article>
        </div>
        <details className="smap-integration" open>
          <summary>공공 공간데이터와 정밀계측 레이어 연결 상태</summary>
          <div className="smap-grid">
            <div><strong>카카오맵·로드뷰</strong><span>이벤트 좌표 외부 연결 적용. 사이트 내부 실사·자전거 레이어는 JavaScript 키 발급 후 전환합니다.</span></div>
            <div><strong>스마트서울맵</strong><span>도시생활지도 자전거도로 GeoJSON은 OpenAPI 키 승인 후 경로 위 벡터로 겹칩니다.</span></div>
            <div><strong>VWorld</strong><span>위성·WMS는 배경, WFS는 실제 선·면 객체로 사용하며 인증키와 레이어 ID가 필요합니다.</span></div>
            <div><strong>RTK 중심궤적</strong><span>현재 휴대폰 GPS 선을 대체할 최우선 레이어입니다. FIX 상태·보정 age·원시 로그를 함께 저장해야 합니다.</span></div>
            <div><strong>LiDAR·정사영상</strong><span>PCD·LAZ 및 GeoTIFF를 받으면 노면 높이·반사강도·균열 영상 레이어로 추가합니다.</span></div>
            <div><strong>46점의 의미</strong><span>데이터 완성도와 검증 준비도를 합친 공학적 진단값이며, 정답 라벨로 계산한 통계적 정확도가 아닙니다.</span></div>
          </div>
        </details>
        <p className="paper-limit">참고 논문은 2024년 학술대회 1쪽 초록이므로, 세부 임계값과 정량 정확도는 확인할 수 없습니다. 대시보드에는 재현 가능한 데이터 구조와 검증 절차만 반영했습니다.</p>
      </section>

      <section className="glossary-section" id="glossary">
        <div className="section-heading">
          <div>
            <span className="eyebrow">08 / PLAIN-LANGUAGE GLOSSARY</span>
            <h2>처음 듣는 계측·지도 용어를<br />쉬운 말로 풀었습니다.</h2>
          </div>
        </div>
        <div className="glossary-grid">
          {glossary.map(([term, explanation]) => (
            <article key={term}>
              <strong>{term}</strong>
              <p>{explanation}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="gps-help">
        <div>
          <span className="eyebrow">GPS FOUND</span>
          <h2>지도 앱에 없던 경로,<br />phyphox CSV 안에 있었습니다.</h2>
        </div>
        <div className="gps-help-copy">
          <p>
            파일의 <strong>Location.csv</strong>에 위도·경도·속도·정확도가 저장되어 있습니다.
            카카오맵·Google 지도는 센서 CSV를 자동으로 읽지 않으므로, 아래 KML·GPX를 GIS 또는 My Maps에 가져오면 경로를 볼 수 있습니다.
          </p>
          <div className="hero-actions">
            <a className="button primary" href="/jamwon-ride-route.kml" download>KML 다운로드</a>
            <a className="button" href="/jamwon-ride-route.gpx" download>GPX 다운로드</a>
          </div>
        </div>
      </section></>}

      <footer>
        <div className="brand"><span className="brand-mark">R2</span><span>R2D</span></div>
        <p>Prototype road intelligence report · Sensor-derived, not a certified pavement index.</p>
        <span>2026</span>
      </footer>
    </main>
  );
}
