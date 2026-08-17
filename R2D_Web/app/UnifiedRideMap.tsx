"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getRoadDataset, roadDatasets, type RoadDataset } from "./road-datasets";

type CivicReport = {
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

const gradeColor: Record<string, string> = {
  good: "#27d7ad",
  fair: "#b8dd50",
  caution: "#f6b84b",
  poor: "#ff6b66",
};

const gradeLabel: Record<string, string> = {
  good: "양호",
  fair: "보통",
  caution: "주의",
  poor: "집중 확인",
};

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

export default function UnifiedRideMap({
  selectedDatasetId,
  selectedIndex,
  onSelect,
  onOpen3D,
  onEventSelect,
  liveReports,
}: {
  selectedDatasetId: RoadDataset["id"];
  selectedIndex: number;
  onSelect: (datasetId: RoadDataset["id"], index: number) => void;
  onOpen3D: () => void;
  onEventSelect?: (datasetId: RoadDataset["id"], event: RoadDataset["events"][number]) => void;
  liveReports: CivicReport[];
}) {
  const mapNodeRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<import("leaflet").Map | null>(null);
  const layerRef = useRef<import("leaflet").LayerGroup | null>(null);
  const leafletRef = useRef<typeof import("leaflet") | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const selectedDataset = useMemo(() => getRoadDataset(selectedDatasetId), [selectedDatasetId]);
  const selectedWindow = selectedDataset.windows[Math.min(selectedIndex, selectedDataset.windows.length - 1)];

  const fitDataset = useCallback((datasetId: RoadDataset["id"] | "all") => {
    const map = mapRef.current;
    const leaflet = leafletRef.current;
    if (!map || !leaflet) return;
    const datasets = datasetId === "all"
      ? roadDatasets
      : [getRoadDataset(datasetId)];
    const points = datasets.flatMap((dataset) => dataset.route.map((point) => [point.lat, point.lon] as [number, number]));
    map.fitBounds(leaflet.latLngBounds(points), {
      padding: [32, 32],
      maxZoom: datasetId === "all" ? 11 : 16,
      animate: false,
    });
  }, []);

  useEffect(() => {
    let disposed = false;
    void import("leaflet").then((leaflet) => {
      if (disposed || !mapNodeRef.current || mapRef.current) return;
      leafletRef.current = leaflet;
      const map = leaflet.map(mapNodeRef.current, {
        zoomControl: true,
        scrollWheelZoom: true,
        preferCanvas: true,
      });
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
      mapRef.current = map;
      layerRef.current = leaflet.layerGroup().addTo(map);
      setMapReady(true);
      window.setTimeout(() => fitDataset("all"), 0);
    });

    return () => {
      disposed = true;
      mapRef.current?.remove();
      mapRef.current = null;
      layerRef.current = null;
      leafletRef.current = null;
    };
  }, [fitDataset]);

  useEffect(() => {
    const leaflet = leafletRef.current;
    const layer = layerRef.current;
    if (!mapReady || !leaflet || !layer) return;
    layer.clearLayers();

    roadDatasets.forEach((dataset) => {
      const isActiveDataset = dataset.id === selectedDatasetId;
      leaflet.polyline(
        dataset.route.map((point) => [point.lat, point.lon] as [number, number]),
        {
          color: dataset.accent,
          weight: isActiveDataset ? 6 : 4,
          opacity: isActiveDataset ? 0.78 : 0.42,
          interactive: false,
        },
      ).addTo(layer);

      dataset.windows.slice(0, -1).forEach((window, index) => {
        const next = dataset.windows[index + 1];
        const points: [number, number][] = [
          [window.latitude, window.longitude],
          [next.latitude, next.longitude],
        ];
        if (isActiveDataset && index === selectedIndex) {
          leaflet.polyline(points, {
            color: "#f4f7f6",
            weight: 12,
            opacity: 0.92,
            interactive: false,
          }).addTo(layer);
        }
        const segment = leaflet.polyline(points, {
          color: window.eligible ? scoreColor(window.score) : "#5f7772",
          weight: isActiveDataset ? 7 : 5,
          opacity: window.eligible ? (isActiveDataset ? 0.92 : 0.68) : 0.34,
        }).addTo(layer);
        segment.bindTooltip(
          `${dataset.shortLabel} · ${formatDuration(window.time)} · ${window.eligible ? `${window.score}점 ${gradeLabel[window.grade]}` : "점수 제외"}`,
          { sticky: true },
        );
        segment.on("click", () => {
          onSelect(dataset.id, index);
          onOpen3D();
        });
      });

      dataset.events.forEach((event) => {
        const isVideoSupported = event.evidence === "video";
        const marker = leaflet.circleMarker([event.latitude, event.longitude], {
          radius: isActiveDataset ? 8 : 6,
          color: "#f4f7f6",
          fillColor: isVideoSupported ? "#ff6b66" : "#f6b84b",
          fillOpacity: isActiveDataset ? 0.98 : 0.72,
          weight: 2,
        }).addTo(layer);
        const popup = document.createElement("div");
        popup.className = "road-event-popup";
        const source = document.createElement("span");
        source.textContent = `${dataset.shortLabel} · ${isVideoSupported ? "영상 확인 후보" : "센서 단독 후보"}`;
        const title = document.createElement("strong");
        title.textContent = event.decision || "충격 이벤트 후보";
        const detail = document.createElement("p");
        detail.textContent = `${formatDuration(event.time)}${event.peakAcceleration ? ` · 피크 ${event.peakAcceleration.toFixed(1)} m/s²` : ""}`;
        const coordinate = document.createElement("small");
        coordinate.textContent = `${event.latitude.toFixed(5)}, ${event.longitude.toFixed(5)}`;
        popup.append(source, title, detail, coordinate);
        marker.bindPopup(popup, { maxWidth: 280 });
        marker.bindTooltip(`${dataset.shortLabel} · ${isVideoSupported ? "영상 확인" : "센서 후보"} · ${formatDuration(event.time)}`, { sticky: true });
        marker.on("click", () => {
          const nearestIndex = dataset.windows.reduce(
            (best, window, index) => Math.abs(window.time - event.time) < Math.abs(dataset.windows[best].time - event.time) ? index : best,
            0,
          );
          onSelect(dataset.id, nearestIndex);
          onEventSelect?.(dataset.id, event);
        });
      });

      const start = dataset.route[0];
      const finish = dataset.route[dataset.route.length - 1];
      [
        { point: start, label: `${dataset.shortLabel} 출발`, color: "#f4f7f6" },
        { point: finish, label: `${dataset.shortLabel} 도착`, color: dataset.accent },
      ].forEach(({ point, label, color }) => {
        leaflet.circleMarker([point.lat, point.lon], {
          radius: isActiveDataset ? 7 : 5,
          color,
          fillColor: "#071716",
          fillOpacity: 1,
          weight: 2,
        }).bindTooltip(label, { sticky: true }).addTo(layer);
      });
    });

    liveReports.forEach((report) => {
      const isOfficial = report.source !== "r2d_citizen";
      const color = report.severity === "urgent" ? "#ff6b66" : isOfficial ? "#58a6ff" : "#f6b84b";
      const marker = leaflet.circleMarker([report.latitude, report.longitude], {
        radius: report.severity === "urgent" ? 10 : 8,
        color: "#f4f7f6",
        fillColor: color,
        fillOpacity: 0.96,
        weight: 2,
      }).addTo(layer);
      const popup = document.createElement("div");
      popup.className = "civic-report-popup";
      const source = document.createElement("span");
      source.textContent = `${reportSourceLabel(report.source)} · ${reportStatusLabel(report.status, report.officialStatus)}`;
      const title = document.createElement("strong");
      title.textContent = report.locationLabel || "위치명 없음";
      const category = document.createElement("b");
      category.textContent = `${reportCategoryLabel[report.category] ?? "기타"} · ${report.severity === "urgent" ? "긴급 확인" : "주의"}`;
      const description = document.createElement("p");
      description.textContent = report.description;
      const coordinate = document.createElement("small");
      coordinate.textContent = `${report.latitude.toFixed(5)}, ${report.longitude.toFixed(5)}`;
      popup.append(source, title, category, description, coordinate);
      marker.bindPopup(popup, { maxWidth: 300 });
      marker.bindTooltip(`${reportSourceLabel(report.source)} · ${reportCategoryLabel[report.category] ?? "기타"}`, { sticky: true });
    });
  }, [liveReports, mapReady, onEventSelect, onOpen3D, onSelect, selectedDatasetId, selectedIndex]);

  return (
    <div className="merged-map-shell">
      <div className="merged-map-toolbar" aria-label="누적 실측 기록 지도 선택">
        <button type="button" onClick={() => fitDataset("all")}>전체 누적 보기</button>
        {roadDatasets.map((dataset) => (
          <button
            key={dataset.id}
            type="button"
            className={dataset.id === selectedDatasetId ? "active" : ""}
            onClick={() => {
              onSelect(dataset.id, dataset.defaultIndex);
              fitDataset(dataset.id);
            }}
          >
            <i style={{ background: dataset.accent }} />
            {dataset.shortLabel} 확대
          </button>
        ))}
      </div>
      <div
        ref={mapNodeRef}
        className="actual-map merged-actual-map"
        role="region"
        aria-label="잠원한강공원과 동탄 실측 경로를 병합한 누적 지도. 점수 구간을 선택하면 아래 3D 도로가 갱신됩니다."
      />
      <div className="merged-map-legend">
        {roadDatasets.map((dataset) => (
          <span key={dataset.id}><i style={{ background: dataset.accent }} /> {dataset.label}</span>
        ))}
        <span><i className="score-good" /> 양호</span>
        <span><i className="score-caution" /> 주의</span>
        <span><i className="score-poor" /> 집중 확인</span>
        <span><i className="event-video" /> 영상 확인 이벤트 후보</span>
        <span><i className="event-sensor" /> 센서 단독 이벤트 후보</span>
        <span><i className="report-r2d" /> R2D 시민 제보</span>
        <span><i className="report-official" /> 기관 연계 민원</span>
      </div>
      <div className="merged-selection" aria-live="polite">
        <div>
          <span>선택한 누적 기록</span>
          <strong>{selectedDataset.label} · {selectedDataset.date}</strong>
        </div>
        <div>
          <span>선택 구간</span>
          <strong>{formatDuration(selectedWindow.time)} · {selectedWindow.eligible ? `${selectedWindow.score}점 ${gradeLabel[selectedWindow.grade]}` : "점수 제외"}</strong>
        </div>
        <div>
          <span>GPS 위치</span>
          <strong>{selectedWindow.latitude.toFixed(5)}, {selectedWindow.longitude.toFixed(5)}</strong>
        </div>
        <p>지도에서 색상 구간을 누르면 이 관제 패널이 같은 기록·같은 구간의 3D 노면 보기로 전환됩니다.</p>
      </div>
    </div>
  );
}
