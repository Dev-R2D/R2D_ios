"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { RoadDataset } from "./road-datasets";
import { useMapConfig } from "./useMapConfig";

function scoreColor(score: number) {
  if (score >= 80) return "#27d7ad";
  if (score >= 65) return "#b8dd50";
  if (score >= 50) return "#f6b84b";
  return "#ff6b66";
}

type Coordinate = [number, number];

function clamp(value: number, minimum = 0, maximum = 1) {
  return Math.min(maximum, Math.max(minimum, value));
}

function smoothCoordinate(windows: RoadDataset["windows"], index: number): Coordinate {
  const start = Math.max(0, index - 2);
  const end = Math.min(windows.length - 1, index + 2);
  let longitude = 0;
  let latitude = 0;
  let count = 0;
  for (let cursor = start; cursor <= end; cursor += 1) {
    longitude += windows[cursor].longitude;
    latitude += windows[cursor].latitude;
    count += 1;
  }
  return [longitude / count, latitude / count];
}

function relativeSurfaceSignal(window: RoadDataset["windows"][number]) {
  const scoreSignal = clamp((100 - window.score) / 58);
  const rmsSignal = clamp(window.accelRms / 8);
  const peakSignal = clamp(window.peak / 45);
  const frequencySignal = clamp(window.hfRatio / 0.6);
  return scoreSignal * 0.48 + rmsSignal * 0.27 + peakSignal * 0.18 + frequencySignal * 0.07;
}

function roadSegmentPolygon(start: Coordinate, end: Coordinate, widthMeters: number): Coordinate[] {
  const centerLatitude = ((start[1] + end[1]) / 2) * Math.PI / 180;
  const metersPerLongitudeDegree = Math.max(1, 111_320 * Math.cos(centerLatitude));
  const metersPerLatitudeDegree = 110_540;
  const deltaX = (end[0] - start[0]) * metersPerLongitudeDegree;
  const deltaY = (end[1] - start[1]) * metersPerLatitudeDegree;
  const length = Math.hypot(deltaX, deltaY);
  const halfWidth = widthMeters / 2;
  const normalX = length > 0.05 ? (-deltaY / length) * halfWidth : 0;
  const normalY = length > 0.05 ? (deltaX / length) * halfWidth : halfWidth;
  const offsetLongitude = normalX / metersPerLongitudeDegree;
  const offsetLatitude = normalY / metersPerLatitudeDegree;
  return [
    [start[0] + offsetLongitude, start[1] + offsetLatitude],
    [end[0] + offsetLongitude, end[1] + offsetLatitude],
    [end[0] - offsetLongitude, end[1] - offsetLatitude],
    [start[0] - offsetLongitude, start[1] - offsetLatitude],
    [start[0] + offsetLongitude, start[1] + offsetLatitude],
  ];
}

function routeBearing(dataset: RoadDataset, index: number) {
  const start = dataset.windows[Math.max(0, index - 3)];
  const end = dataset.windows[Math.min(dataset.windows.length - 1, index + 3)];
  const toRadians = (value: number) => (value * Math.PI) / 180;
  const toDegrees = (value: number) => (value * 180) / Math.PI;
  const startLat = toRadians(start.latitude);
  const endLat = toRadians(end.latitude);
  const longitudeDelta = toRadians(end.longitude - start.longitude);
  const y = Math.sin(longitudeDelta) * Math.cos(endLat);
  const x = Math.cos(startLat) * Math.sin(endLat)
    - Math.sin(startLat) * Math.cos(endLat) * Math.cos(longitudeDelta);
  return ((toDegrees(Math.atan2(y, x)) + 540) % 360) - 180;
}

export default function RoadContext3DMap({
  dataset,
  selectedIndex,
  visibleStart,
  visibleEnd,
  onSelect,
}: {
  dataset: RoadDataset;
  selectedIndex: number;
  visibleStart: number;
  visibleEnd: number;
  onSelect: (index: number) => void;
}) {
  const mapConfig = useMapConfig();
  const mapNodeRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<import("maplibre-gl").Map | null>(null);
  const maplibreRef = useRef<typeof import("maplibre-gl") | null>(null);
  const onSelectRef = useRef(onSelect);
  const [mapReady, setMapReady] = useState(false);
  const [pitch, setPitch] = useState(58);
  const [bearing, setBearing] = useState(() => Math.round(routeBearing(dataset, selectedIndex)));
  const [buildingsVisible, setBuildingsVisible] = useState(true);
  const [greenVisible, setGreenVisible] = useState(true);
  const [roadWidth, setRoadWidth] = useState(4);
  const [reliefScale, setReliefScale] = useState(9);

  const visibleWindows = useMemo(
    () => dataset.windows.slice(visibleStart, visibleEnd + 1),
    [dataset.windows, visibleEnd, visibleStart],
  );

  useEffect(() => {
    onSelectRef.current = onSelect;
  }, [onSelect]);

  useEffect(() => {
    if (!mapConfig.loaded) return;
    let disposed = false;

    void import("maplibre-gl").then((maplibre) => {
      if (disposed || !mapNodeRef.current) return;
      maplibreRef.current = maplibre;
      const satelliteTiles = mapConfig.vworldApiKey
        ? [`https://api.vworld.kr/req/wmts/1.0.0/${mapConfig.vworldApiKey}/Satellite/{z}/{y}/{x}.jpeg`]
        : ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"];

      const map = new maplibre.Map({
        container: mapNodeRef.current,
        center: [dataset.windows[dataset.defaultIndex].longitude, dataset.windows[dataset.defaultIndex].latitude],
        zoom: 16.2,
        pitch: 58,
        bearing: routeBearing(dataset, dataset.defaultIndex),
        maxPitch: 75,
        canvasContextAttributes: { antialias: true },
        style: {
          version: 8,
          sources: {
            satellite: {
              type: "raster",
              tiles: satelliteTiles,
              tileSize: 256,
              maxzoom: 19,
              attribution: mapConfig.vworldApiKey
                ? "영상지도 © VWorld · 국토교통부"
                : "Imagery © Esri, Maxar, Earthstar Geographics",
            },
            terrain: {
              type: "raster-dem",
              url: "https://demotiles.maplibre.org/terrain-tiles/tiles.json",
              tileSize: 256,
            },
            openfreemap: {
              type: "vector",
              url: "https://tiles.openfreemap.org/planet",
              attribution: "© OpenStreetMap contributors · OpenFreeMap",
            },
          },
          layers: [{
            id: "satellite",
            type: "raster",
            source: "satellite",
            paint: {
              "raster-saturation": -0.04,
              "raster-contrast": 0.08,
              "raster-brightness-max": 0.94,
            },
          }],
          terrain: { source: "terrain", exaggeration: 1.22 },
        },
      });

      mapRef.current = map;
      map.addControl(new maplibre.NavigationControl({ visualizePitch: true }), "top-right");
      map.on("load", () => {
        if (disposed) return;

        map.addLayer({
          id: "mapped-green-areas",
          type: "fill-extrusion",
          source: "openfreemap",
          "source-layer": "landcover",
          filter: [
            "match",
            ["get", "class"],
            ["wood", "forest", "grass", "park", "scrub", "farmland"],
            true,
            false,
          ],
          paint: {
            "fill-extrusion-color": [
              "match",
              ["get", "class"],
              ["wood", "forest"],
              "#477d59",
              ["grass", "park"],
              "#76a866",
              "#648b5d",
            ],
            "fill-extrusion-height": [
              "match",
              ["get", "class"],
              ["wood", "forest"],
              3.2,
              0.8,
            ],
            "fill-extrusion-opacity": 0.42,
          },
        });

        map.addLayer({
          id: "3d-buildings",
          type: "fill-extrusion",
          source: "openfreemap",
          "source-layer": "building",
          minzoom: 13.5,
          filter: ["!=", ["get", "hide_3d"], true],
          paint: {
            "fill-extrusion-color": [
              "interpolate",
              ["linear"],
              ["coalesce", ["get", "render_height"], 12],
              0,
              "#d8d7d0",
              60,
              "#e5ded0",
              180,
              "#bcd4d1",
            ],
            "fill-extrusion-height": ["coalesce", ["get", "render_height"], 12],
            "fill-extrusion-base": ["coalesce", ["get", "render_min_height"], 0],
            "fill-extrusion-opacity": 0.88,
          },
        });

        map.addSource("context-full-route", {
          type: "geojson",
          data: {
            type: "Feature",
            properties: {},
            geometry: {
              type: "LineString",
              coordinates: dataset.route.map((point) => [point.lon, point.lat]),
            },
          },
        });
        map.addLayer({
          id: "context-full-route-line",
          type: "line",
          source: "context-full-route",
          paint: { "line-color": "#e6efed", "line-width": 4, "line-opacity": 0.72 },
        });

        map.addSource("context-selected-route", {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
        });

        map.addSource("context-road-surface", {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
        });
        map.addLayer({
          id: "context-road-surface-extrusion",
          type: "fill-extrusion",
          source: "context-road-surface",
          paint: {
            "fill-extrusion-color": ["get", "color"],
            "fill-extrusion-base": 0.25,
            "fill-extrusion-height": ["get", "height"],
            "fill-extrusion-opacity": ["get", "opacity"],
            "fill-extrusion-vertical-gradient": true,
          },
        });
        map.addLayer({
          id: "context-selected-halo",
          type: "line",
          source: "context-selected-route",
          paint: { "line-color": "#ffffff", "line-width": 15, "line-opacity": 0.76 },
        });

        map.addSource("context-score-segments", {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
        });
        map.addLayer({
          id: "context-score-segments-line",
          type: "line",
          source: "context-score-segments",
          paint: {
            "line-color": ["get", "color"],
            "line-width": ["interpolate", ["linear"], ["zoom"], 13, 5, 18, 12],
            "line-opacity": ["get", "opacity"],
          },
        });

        map.addSource("context-events", {
          type: "geojson",
          data: {
            type: "FeatureCollection",
            features: dataset.events.map((event) => ({
              type: "Feature" as const,
              properties: { id: event.id },
              geometry: { type: "Point" as const, coordinates: [event.longitude, event.latitude] },
            })),
          },
        });
        map.addLayer({
          id: "context-event-points",
          type: "circle",
          source: "context-events",
          paint: {
            "circle-color": "#ff6b66",
            "circle-radius": 6,
            "circle-stroke-color": "#ffffff",
            "circle-stroke-width": 1.5,
          },
        });

        map.on("click", "context-score-segments-line", (event) => {
          const index = Number(event.features?.[0]?.properties?.index);
          if (Number.isFinite(index)) onSelectRef.current(index);
        });
        map.on("mouseenter", "context-score-segments-line", () => {
          map.getCanvas().style.cursor = "pointer";
        });
        map.on("mouseleave", "context-score-segments-line", () => {
          map.getCanvas().style.cursor = "";
        });
        map.on("click", "context-road-surface-extrusion", (event) => {
          const index = Number(event.features?.[0]?.properties?.index);
          if (Number.isFinite(index)) onSelectRef.current(index);
        });
        map.on("mouseenter", "context-road-surface-extrusion", () => {
          map.getCanvas().style.cursor = "pointer";
        });
        map.on("mouseleave", "context-road-surface-extrusion", () => {
          map.getCanvas().style.cursor = "";
        });
        setMapReady(true);
      });
    });

    return () => {
      disposed = true;
      setMapReady(false);
      mapRef.current?.remove();
      mapRef.current = null;
      maplibreRef.current = null;
    };
  }, [dataset, mapConfig.loaded, mapConfig.vworldApiKey]);

  useEffect(() => {
    const map = mapRef.current;
    const maplibre = maplibreRef.current;
    if (!mapReady || !map || !maplibre || visibleWindows.length < 2) return;
    const features = visibleWindows.slice(0, -1).map((window, localIndex) => {
      const next = visibleWindows[localIndex + 1];
      const index = visibleStart + localIndex;
      return {
        type: "Feature" as const,
        properties: {
          index,
          color: scoreColor(window.score),
          opacity: window.confidence < 0.7 ? 0.5 : 0.94,
        },
        geometry: {
          type: "LineString" as const,
          coordinates: [
            [window.longitude, window.latitude],
            [next.longitude, next.latitude],
          ],
        },
      };
    });
    const scoreSource = map.getSource("context-score-segments") as import("maplibre-gl").GeoJSONSource;
    const selectedSource = map.getSource("context-selected-route") as import("maplibre-gl").GeoJSONSource;
    const surfaceSource = map.getSource("context-road-surface") as import("maplibre-gl").GeoJSONSource;
    scoreSource?.setData({ type: "FeatureCollection", features });
    const selected = features.find((feature) => feature.properties.index === selectedIndex);
    selectedSource?.setData({
      type: "FeatureCollection",
      features: selected ? [selected] : [],
    });

    const smoothedPoints = visibleWindows.map((_, index) => smoothCoordinate(visibleWindows, index));
    const signals = visibleWindows.map(relativeSurfaceSignal);
    const sortedSignals = [...signals].sort((left, right) => left - right);
    const surfaceFloor = sortedSignals[Math.floor((sortedSignals.length - 1) * 0.2)] ?? 0;
    const surfaceFeatures = visibleWindows.slice(0, -1).map((window, localIndex) => {
      const index = visibleStart + localIndex;
      const signal = (signals[localIndex] + signals[localIndex + 1]) / 2;
      const relativeRelief = clamp((signal - surfaceFloor) / Math.max(0.16, 1 - surfaceFloor));
      return {
        type: "Feature" as const,
        properties: {
          index,
          color: scoreColor(window.score),
          height: 0.45 + relativeRelief * reliefScale,
          opacity: window.confidence < 0.7 ? 0.5 : 0.82,
          score: window.score,
          relativeRelief,
        },
        geometry: {
          type: "Polygon" as const,
          coordinates: [roadSegmentPolygon(smoothedPoints[localIndex], smoothedPoints[localIndex + 1], roadWidth)],
        },
      };
    });
    surfaceSource?.setData({ type: "FeatureCollection", features: surfaceFeatures });

    const points = visibleWindows.map(
      (window) => [window.longitude, window.latitude] as [number, number],
    );
    const bounds = points.reduce(
      (current, point) => current.extend(point),
      new maplibre.LngLatBounds(points[0], points[0]),
    );
    map.resize();
    map.fitBounds(bounds, {
      padding: 54,
      maxZoom: 18,
      pitch,
      bearing,
      duration: 650,
    });
  }, [bearing, mapReady, pitch, reliefScale, roadWidth, selectedIndex, visibleStart, visibleWindows]);

  const applyRouteView = useCallback(() => {
    const nextBearing = Math.round(routeBearing(dataset, selectedIndex));
    setPitch(66);
    setBearing(nextBearing);
    mapRef.current?.easeTo({ pitch: 66, bearing: nextBearing, duration: 650 });
  }, [dataset, selectedIndex]);

  const toggleLayer = useCallback((layer: "3d-buildings" | "mapped-green-areas") => {
    const map = mapRef.current;
    if (!map?.getLayer(layer)) return;
    const isBuilding = layer === "3d-buildings";
    const nextVisible = isBuilding ? !buildingsVisible : !greenVisible;
    map.setLayoutProperty(layer, "visibility", nextVisible ? "visible" : "none");
    if (isBuilding) setBuildingsVisible(nextVisible);
    else setGreenVisible(nextVisible);
  }, [buildingsVisible, greenVisible]);

  return (
    <section className="road-context-map immersive-route-map" aria-label={`${dataset.shortLabel} 실제 공간 3D 지도`}>
      <div className="road-context-heading">
        <div>
          <span>GPS ROAD CORRIDOR / IMU RELIEF</span>
          <strong>실사 도로 위 3D 노면 리본</strong>
        </div>
        <p>GPS 중심선을 도로 폭으로 펼치고, IMU 상대 진동을 수직 굴곡으로 강조했습니다.</p>
      </div>
      <div className="road-surface-controls" aria-label="3D 노면 형상 표시 설정">
        <div>
          <span>표시 도로폭</span>
          {[3, 4, 5].map((width) => (
            <button key={width} type="button" className={roadWidth === width ? "active" : ""} onClick={() => setRoadWidth(width)}>{width}m</button>
          ))}
        </div>
        <div>
          <span>IMU 굴곡 강조</span>
          {[
            { label: "낮게", value: 5 },
            { label: "표준", value: 9 },
            { label: "강하게", value: 14 },
          ].map((option) => (
            <button key={option.value} type="button" className={reliefScale === option.value ? "active" : ""} onClick={() => setReliefScale(option.value)}>굴곡 {option.label}</button>
          ))}
        </div>
        <small>도로폭은 GPS 중심선 기반 시각화 폭 · 굴곡은 수직 과장</small>
      </div>
      <div className="actual-map-frame">
        <div
          ref={mapNodeRef}
          className="actual-map road-context-canvas"
          role="region"
          aria-label={`${dataset.shortLabel}의 실제 항공사진, 3D 건물, 지형, 녹지와 GPS 노면 점수 경로`}
        />
        <div className="map-3d-status active">
          <span>GPS ROAD SURFACE · 3D</span>
          <small>실사 배경 + 도로폭 리본 + IMU 상대 굴곡</small>
        </div>
        <div className="map-dimension-actions">
          <button type="button" className={buildingsVisible ? "active" : ""} onClick={() => toggleLayer("3d-buildings")}>3D 건물 {buildingsVisible ? "ON" : "OFF"}</button>
          <button type="button" className={greenVisible ? "active" : ""} onClick={() => toggleLayer("mapped-green-areas")}>녹지 {greenVisible ? "ON" : "OFF"}</button>
          <button type="button" onClick={applyRouteView}>진행방향 시점</button>
          <button type="button" onClick={() => {
            setPitch(0);
            setBearing(0);
            mapRef.current?.easeTo({ pitch: 0, bearing: 0, duration: 650 });
          }}>상공 시점</button>
        </div>
      </div>
      <div className="map-footnote road-context-footnote">
        <span>도로·수목·시설물 실사: {mapConfig.vworldApiKey ? "VWorld" : "Esri"} 항공영상 / 건물·녹지: OpenStreetMap·OpenFreeMap / 지형: MapLibre DEM</span>
        <span>노면 리본 높이 = IMU 상대 진동 시각화(수직 과장) · LiDAR·수준측량 실측 형상 아님</span>
      </div>
    </section>
  );
}
