"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import rideData from "./data/ride-data.json";
import KakaoRoadview from "./KakaoRoadview";
import { useMapConfig } from "./useMapConfig";

type EventDatum = (typeof rideData.events)[number];
type LiveReport = {
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

function kakaoRoadViewUrl(latitude: number, longitude: number) {
  return `https://map.kakao.com/link/roadview/${latitude},${longitude}`;
}

function kakaoMapUrl(latitude: number, longitude: number) {
  return `https://map.kakao.com/link/map/R2D%20Event,${latitude},${longitude}`;
}

function bearingBetween(
  start: { latitude: number; longitude: number },
  end: { latitude: number; longitude: number },
) {
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

function routeBearingAtTime(time: number) {
  let nearestIndex = 0;
  for (let index = 1; index < rideData.windows.length; index += 1) {
    if (Math.abs(rideData.windows[index].time - time)
      < Math.abs(rideData.windows[nearestIndex].time - time)) nearestIndex = index;
  }
  const start = rideData.windows[Math.max(0, nearestIndex - 3)];
  const end = rideData.windows[Math.min(rideData.windows.length - 1, nearestIndex + 3)];
  return bearingBetween(start, end);
}

export default function ImmersiveRouteMap({
  selectedIndex,
  onSelect,
  selectedEvent,
  onEvent,
  liveReports,
}: {
  selectedIndex: number;
  onSelect: (index: number) => void;
  selectedEvent: EventDatum;
  onEvent: (eventDatum: EventDatum) => void;
  liveReports: LiveReport[];
}) {
  const mapConfig = useMapConfig();
  const values = rideData.windows;
  const windowZoomLevels = [1, 2, 4, 8, 16];
  const [windowZoom, setWindowZoom] = useState(1);
  const [viewCenter, setViewCenter] = useState(selectedIndex);
  const [mapReady, setMapReady] = useState(false);
  const [is3D, setIs3D] = useState(true);
  const [cameraPitch, setCameraPitch] = useState(52);
  const [cameraBearing, setCameraBearing] = useState(-24);
  const [activeView, setActiveView] = useState("oblique");
  const [buildingsVisible, setBuildingsVisible] = useState(true);
  const mapNodeRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<import("maplibre-gl").Map | null>(null);
  const maplibreRef = useRef<typeof import("maplibre-gl") | null>(null);
  const popupRef = useRef<import("maplibre-gl").Popup | null>(null);
  const hoverPopupRef = useRef<import("maplibre-gl").Popup | null>(null);
  const lastFocusedEventIdRef = useRef<number | null>(null);
  const onSelectRef = useRef(onSelect);
  const onEventRef = useRef(onEvent);

  const visibleCount = Math.max(20, Math.ceil(values.length / windowZoom));
  const visibleStart = Math.max(
    0,
    Math.min(values.length - visibleCount, Math.round(viewCenter - visibleCount / 2)),
  );
  const visibleEnd = Math.min(values.length, visibleStart + visibleCount);
  const visibleValues = useMemo(
    () => values.slice(visibleStart, visibleEnd),
    [values, visibleEnd, visibleStart],
  );
  const rangeStart = visibleValues[0];
  const rangeEnd = visibleValues[visibleValues.length - 1];

  useEffect(() => {
    onSelectRef.current = onSelect;
    onEventRef.current = onEvent;
  }, [onEvent, onSelect]);

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => setViewCenter(selectedIndex));
    return () => window.cancelAnimationFrame(frame);
  }, [selectedIndex]);

  useEffect(() => {
    if (!mapConfig.loaded) return;
    let disposed = false;

    void import("maplibre-gl").then((maplibre) => {
      if (disposed || !mapNodeRef.current || mapRef.current) return;
      maplibreRef.current = maplibre;

      const satelliteTiles = mapConfig.vworldApiKey
        ? [`https://api.vworld.kr/req/wmts/1.0.0/${mapConfig.vworldApiKey}/Satellite/{z}/{y}/{x}.jpeg`]
        : ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"];
      const satelliteAttribution = mapConfig.vworldApiKey
        ? "영상지도 © VWorld · 국토교통부"
        : "Imagery © Esri, Maxar, Earthstar Geographics";

      const map = new maplibre.Map({
        container: mapNodeRef.current,
        center: [
          (rideData.bounds.minLon + rideData.bounds.maxLon) / 2,
          (rideData.bounds.minLat + rideData.bounds.maxLat) / 2,
        ],
        zoom: 13.7,
        pitch: 52,
        bearing: -24,
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
              attribution: satelliteAttribution,
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
          layers: [
            {
              id: "satellite",
              type: "raster",
              source: "satellite",
              paint: {
                "raster-saturation": -0.12,
                "raster-contrast": 0.06,
                "raster-brightness-max": 0.92,
              },
            },
          ],
          terrain: { source: "terrain", exaggeration: 1.35 },
        },
      });

      mapRef.current = map;
      map.addControl(new maplibre.NavigationControl({ visualizePitch: true }), "top-right");

      map.on("load", () => {
        if (disposed) return;

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
              "#cfd6d2",
              60,
              "#e2ded3",
              180,
              "#c7d8d5",
            ],
            "fill-extrusion-height": [
              "interpolate",
              ["linear"],
              ["zoom"],
              13.5,
              0,
              15.5,
              ["coalesce", ["get", "render_height"], 12],
            ],
            "fill-extrusion-base": ["coalesce", ["get", "render_min_height"], 0],
            "fill-extrusion-opacity": 0.86,
          },
        });

        map.addSource("full-route", {
          type: "geojson",
          data: {
            type: "Feature",
            properties: {},
            geometry: {
              type: "LineString",
              coordinates: rideData.route.map((point) => [point.lon, point.lat]),
            },
          },
        });
        map.addLayer({
          id: "full-route-line",
          type: "line",
          source: "full-route",
          paint: { "line-color": "#839b95", "line-width": 4, "line-opacity": 0.64 },
        });

        const arrowCanvas = document.createElement("canvas");
        arrowCanvas.width = 48;
        arrowCanvas.height = 48;
        const arrowContext = arrowCanvas.getContext("2d");
        if (arrowContext) {
          arrowContext.clearRect(0, 0, 48, 48);
          arrowContext.beginPath();
          arrowContext.moveTo(24, 4);
          arrowContext.lineTo(41, 38);
          arrowContext.lineTo(24, 31);
          arrowContext.lineTo(7, 38);
          arrowContext.closePath();
          arrowContext.fillStyle = "#f4f7f6";
          arrowContext.strokeStyle = "#071716";
          arrowContext.lineWidth = 4;
          arrowContext.lineJoin = "round";
          arrowContext.fill();
          arrowContext.stroke();
          map.addImage("route-direction-arrow", arrowContext.getImageData(0, 0, 48, 48), { pixelRatio: 2 });
          map.addLayer({
            id: "route-direction-arrows",
            type: "symbol",
            source: "full-route",
            layout: {
              "symbol-placement": "line",
              "symbol-spacing": 105,
              "icon-image": "route-direction-arrow",
              "icon-size": 0.64,
              "icon-allow-overlap": true,
              "icon-ignore-placement": true,
              "icon-rotation-alignment": "map",
              "icon-pitch-alignment": "map",
            },
          });
        }

        map.addSource("selected-segment", {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
        });
        map.addLayer({
          id: "selected-segment-halo",
          type: "line",
          source: "selected-segment",
          paint: { "line-color": "#ffffff", "line-width": 15, "line-opacity": 0.82 },
        });

        map.addSource("score-segments", {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
        });
        map.addLayer({
          id: "score-segments-line",
          type: "line",
          source: "score-segments",
          paint: {
            "line-color": ["get", "color"],
            "line-width": ["interpolate", ["linear"], ["zoom"], 13, 5, 18, 11],
            "line-opacity": ["get", "opacity"],
          },
        });

        map.addSource("route-points", {
          type: "geojson",
          data: {
            type: "FeatureCollection",
            features: [
              {
                type: "Feature",
                properties: { kind: "start" },
                geometry: {
                  type: "Point",
                  coordinates: [rideData.route[0].lon, rideData.route[0].lat],
                },
              },
              {
                type: "Feature",
                properties: { kind: "finish" },
                geometry: {
                  type: "Point",
                  coordinates: [
                    rideData.route[rideData.route.length - 1].lon,
                    rideData.route[rideData.route.length - 1].lat,
                  ],
                },
              },
            ],
          },
        });
        map.addLayer({
          id: "route-points-circle",
          type: "circle",
          source: "route-points",
          paint: {
            "circle-radius": 6,
            "circle-color": ["match", ["get", "kind"], "start", "#071716", "#27d7ad"],
            "circle-stroke-color": "#f4f7f6",
            "circle-stroke-width": 2,
          },
        });

        map.addSource("impact-events", {
          type: "geojson",
          data: {
            type: "FeatureCollection",
            features: rideData.events.map((eventDatum) => ({
              type: "Feature",
              properties: {
                id: eventDatum.id,
                peak: eventDatum.peakAcceleration,
                time: eventDatum.time,
              },
              geometry: {
                type: "Point",
                coordinates: [eventDatum.longitude, eventDatum.latitude],
              },
            })),
          },
        });
        map.addLayer({
          id: "impact-events-circle",
          type: "circle",
          source: "impact-events",
          paint: {
            "circle-radius": 8,
            "circle-color": "#ff6b66",
            "circle-opacity": 0.96,
            "circle-stroke-color": "#f4f7f6",
            "circle-stroke-width": 1.5,
          },
        });

        map.addSource("live-civic-reports", {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
        });
        map.addLayer({
          id: "live-civic-reports-halo",
          type: "circle",
          source: "live-civic-reports",
          paint: {
            "circle-radius": 14,
            "circle-color": "#f6b84b",
            "circle-opacity": 0.18,
          },
        });
        map.addLayer({
          id: "live-civic-reports-circle",
          type: "circle",
          source: "live-civic-reports",
          paint: {
            "circle-radius": 7,
            "circle-color": [
              "match",
              ["get", "severity"],
              "urgent",
              "#ff6b66",
              "#f6b84b",
            ],
            "circle-stroke-color": "#f4f7f6",
            "circle-stroke-width": 2,
          },
        });
        map.on("click", "score-segments-line", (event) => {
          const index = Number(event.features?.[0]?.properties?.index);
          if (Number.isFinite(index)) onSelectRef.current(index);
        });
        map.on("click", "impact-events-circle", (event) => {
          const id = Number(event.features?.[0]?.properties?.id);
          const eventDatum = rideData.events.find((item) => item.id === id);
          if (eventDatum) {
            const routeBearing = routeBearingAtTime(eventDatum.time);
            onEventRef.current(eventDatum);
            map.flyTo({
              center: [eventDatum.longitude, eventDatum.latitude],
              zoom: Math.max(map.getZoom(), 17),
              pitch: 64,
              bearing: routeBearing,
              speed: 1.15,
              essential: true,
            });
            setIs3D(true);
            setActiveView("route");
          }
        });
        map.on("click", "live-civic-reports-circle", (event) => {
          const properties = event.features?.[0]?.properties;
          if (!properties || !event.lngLat) return;
          const popupNode = document.createElement("div");
          popupNode.className = "civic-report-popup";
          const label = document.createElement("span");
          label.textContent = `${reportSourceLabel(String(properties.source))} · ${properties.severity === "urgent" ? "긴급 확인" : "주의"}`;
          const title = document.createElement("strong");
          title.textContent = properties.locationLabel || "위치명 없음";
          const description = document.createElement("p");
          description.textContent = properties.description;
          const status = document.createElement("small");
          status.textContent = reportStatusLabel(String(properties.status), String(properties.officialStatus));
          popupNode.append(label, title, description, status);
          new maplibre.Popup({ offset: 12, maxWidth: "280px" })
            .setLngLat(event.lngLat)
            .setDOMContent(popupNode)
            .addTo(map);
        });
        map.on("mousemove", "score-segments-line", (event) => {
          map.getCanvas().style.cursor = "pointer";
          const properties = event.features?.[0]?.properties;
          if (!properties || !event.lngLat) return;
          hoverPopupRef.current ??= new maplibre.Popup({
            closeButton: false,
            closeOnClick: false,
            offset: 10,
            className: "score-hover-popup",
          });
          hoverPopupRef.current
            .setLngLat(event.lngLat)
            .setHTML(
              `<strong>${Number(properties.score).toFixed(1)}점</strong><span>${formatDuration(Number(properties.time))} · ${gradeLabel[String(properties.grade)] ?? "분석 구간"}</span>`,
            )
            .addTo(map);
        });
        map.on("mouseleave", "score-segments-line", () => {
          map.getCanvas().style.cursor = "grab";
          hoverPopupRef.current?.remove();
        });
        map.on("mouseenter", "impact-events-circle", () => {
          map.getCanvas().style.cursor = "pointer";
        });
        map.on("mouseleave", "impact-events-circle", () => {
          map.getCanvas().style.cursor = "grab";
        });
        map.on("mouseenter", "live-civic-reports-circle", () => {
          map.getCanvas().style.cursor = "pointer";
        });
        map.on("mouseleave", "live-civic-reports-circle", () => {
          map.getCanvas().style.cursor = "grab";
        });

        map.fitBounds(
          [
            [rideData.bounds.minLon, rideData.bounds.minLat],
            [rideData.bounds.maxLon, rideData.bounds.maxLat],
          ],
          { padding: 30, maxZoom: 14, duration: 0, pitch: 52, bearing: -24 },
        );
        setMapReady(true);
      });

      map.on("moveend", () => {
        setCameraPitch(Math.round(map.getPitch()));
        setCameraBearing(Math.round(map.getBearing()));
        setIs3D(map.getPitch() > 10);
      });
    });

    return () => {
      disposed = true;
      popupRef.current?.remove();
      hoverPopupRef.current?.remove();
      mapRef.current?.remove();
      mapRef.current = null;
      maplibreRef.current = null;
    };
  }, [mapConfig.loaded, mapConfig.vworldApiKey]);

  useEffect(() => {
    const map = mapRef.current;
    if (!mapReady || !map) return;
    const source = map.getSource("live-civic-reports") as import("maplibre-gl").GeoJSONSource | undefined;
    source?.setData({
      type: "FeatureCollection",
      features: liveReports.map((report) => ({
        type: "Feature" as const,
        properties: {
          id: report.id,
          category: report.category,
          severity: report.severity,
          description: report.description,
          locationLabel: report.locationLabel,
          createdAt: report.createdAt,
          source: report.source,
          status: report.status,
          officialStatus: report.officialStatus,
        },
        geometry: {
          type: "Point" as const,
          coordinates: [report.longitude, report.latitude],
        },
      })),
    });
  }, [liveReports, mapReady]);

  useEffect(() => {
    const map = mapRef.current;
    const maplibre = maplibreRef.current;
    if (!mapReady || !map || !maplibre || visibleValues.length === 0) return;

    const features = [];
    for (let index = visibleStart; index < visibleEnd - 1; index += 1) {
      const datum = values[index];
      const next = values[index + 1];
      features.push({
        type: "Feature" as const,
        properties: {
          index,
          color: scoreColor(datum.score),
          opacity: datum.confidence < 0.7 ? 0.46 : 0.94,
          score: datum.score,
          time: datum.time,
          grade: datum.grade,
        },
        geometry: {
          type: "LineString" as const,
          coordinates: [
            [datum.longitude, datum.latitude],
            [next.longitude, next.latitude],
          ],
        },
      });
    }

    const scoreSource = map.getSource("score-segments") as import("maplibre-gl").GeoJSONSource;
    const selectedSource = map.getSource("selected-segment") as import("maplibre-gl").GeoJSONSource;
    scoreSource?.setData({ type: "FeatureCollection", features });
    const selectedFeature = features.find((feature) => feature.properties.index === selectedIndex);
    selectedSource?.setData({
      type: "FeatureCollection",
      features: selectedFeature ? [selectedFeature] : [],
    });

    if (map.getLayer("impact-events-circle")) {
      map.setPaintProperty(
        "impact-events-circle",
        "circle-radius",
        ["case", ["==", ["get", "id"], selectedEvent.id], 11, 8],
      );
      map.setPaintProperty(
        "impact-events-circle",
        "circle-stroke-width",
        ["case", ["==", ["get", "id"], selectedEvent.id], 3, 1.5],
      );
    }

    const focusPoints = windowZoom === 1
      ? rideData.route.map((point) => [point.lon, point.lat] as [number, number])
      : visibleValues.map((datum) => [datum.longitude, datum.latitude] as [number, number]);
    const bounds = focusPoints.reduce(
      (current, point) => current.extend(point),
      new maplibre.LngLatBounds(focusPoints[0], focusPoints[0]),
    );
    map.resize();
    map.fitBounds(bounds, {
      padding: 32,
      maxZoom: windowZoom === 1 ? 14 : 17.8,
      duration: 700,
      pitch: Math.max(map.getPitch(), 46),
      bearing: map.getBearing(),
    });
  }, [mapReady, selectedEvent.id, selectedIndex, values, visibleEnd, visibleStart, visibleValues, windowZoom]);

  useEffect(() => {
    const map = mapRef.current;
    const maplibre = maplibreRef.current;
    if (!mapReady || !map || !maplibre) return;

    popupRef.current?.remove();
    popupRef.current = new maplibre.Popup({
      closeButton: false,
      closeOnClick: false,
      offset: 16,
      maxWidth: "230px",
    })
      .setLngLat([selectedEvent.longitude, selectedEvent.latitude])
      .setHTML(
        `<div class="impact-popup"><img src="${selectedEvent.frame}" alt="충격 지점 실제 주행 영상 프레임"><strong>SPOT ${String(selectedEvent.id).padStart(2, "0")}</strong><span>${formatDuration(selectedEvent.time)} · ${selectedEvent.peakAcceleration.toFixed(1)} m/s²</span></div>`,
      )
      .addTo(map);
    const shouldFly = lastFocusedEventIdRef.current !== null
      && lastFocusedEventIdRef.current !== selectedEvent.id;
    lastFocusedEventIdRef.current = selectedEvent.id;
    if (shouldFly) {
      const routeBearing = routeBearingAtTime(selectedEvent.time);
      map.flyTo({
        center: [selectedEvent.longitude, selectedEvent.latitude],
        zoom: Math.max(map.getZoom(), 17),
        pitch: 64,
        bearing: routeBearing,
        speed: 1.15,
        essential: true,
      });
      setIs3D(true);
      setActiveView("route");
    }
  }, [mapReady, selectedEvent]);

  const changeWindowZoom = useCallback((nextZoom: number) => {
    setWindowZoom(nextZoom);
    setViewCenter(selectedIndex);
  }, [selectedIndex]);

  const applyView = useCallback((view: "top" | "north" | "oblique" | "route" | "low") => {
    const map = mapRef.current;
    if (!map) return;
    const centerIndex = Math.max(
      0,
      Math.min(values.length - 1, Math.round((visibleStart + visibleEnd - 1) / 2)),
    );
    const routeBearing = routeBearingAtTime(values[centerIndex].time);
    const settings = {
      top: { pitch: 0, bearing: 0 },
      north: { pitch: 48, bearing: 0 },
      oblique: { pitch: 52, bearing: -24 },
      route: { pitch: 62, bearing: routeBearing },
      low: { pitch: 72, bearing: routeBearing },
    }[view];
    setActiveView(view);
    setCameraPitch(settings.pitch);
    setCameraBearing(Math.round(settings.bearing));
    setIs3D(settings.pitch > 10);
    map.easeTo({
      zoom: view === "low" ? Math.max(map.getZoom(), 17) : map.getZoom(),
      pitch: settings.pitch,
      bearing: settings.bearing,
      duration: 850,
      essential: true,
    });
  }, [values, visibleEnd, visibleStart]);

  const changePitch = useCallback((nextPitch: number) => {
    const map = mapRef.current;
    if (!map) return;
    setActiveView("custom");
    setCameraPitch(nextPitch);
    setIs3D(nextPitch > 10);
    map.setPitch(nextPitch);
  }, []);

  const changeBearing = useCallback((nextBearing: number) => {
    const map = mapRef.current;
    if (!map) return;
    setActiveView("custom");
    setCameraBearing(nextBearing);
    map.setBearing(nextBearing);
  }, []);

  const toggleBuildings = useCallback(() => {
    const map = mapRef.current;
    if (!map || !map.getLayer("3d-buildings")) return;
    const nextVisible = !buildingsVisible;
    setBuildingsVisible(nextVisible);
    map.setLayoutProperty("3d-buildings", "visibility", nextVisible ? "visible" : "none");
  }, [buildingsVisible]);

  const fitCurrentSection = useCallback(() => {
    const map = mapRef.current;
    const maplibre = maplibreRef.current;
    if (!map || !maplibre || visibleValues.length === 0) return;
    const points = visibleValues.map(
      (datum) => [datum.longitude, datum.latitude] as [number, number],
    );
    const bounds = points.reduce(
      (current, point) => current.extend(point),
      new maplibre.LngLatBounds(points[0], points[0]),
    );
    map.fitBounds(bounds, {
      padding: 42,
      maxZoom: 17.8,
      pitch: Math.max(map.getPitch(), 46),
      bearing: map.getBearing(),
      duration: 750,
    });
  }, [visibleValues]);

  return (
    <div className="route-map-shell immersive-route-map">
      <div className="map-zoom-bar">
        <div className="map-window-summary" aria-live="polite">
          <span>지도 표시 구간</span>
          <strong>{formatDuration(rangeStart.time)}–{formatDuration(rangeEnd.time + 4)}</strong>
          <small>{visibleValues.length}개 점수 구간</small>
        </div>
        <div className="map-zoom-actions" aria-label="지도 구간 확대">
          {windowZoomLevels.map((level) => (
            <button
              key={level}
              type="button"
              className={windowZoom === level ? "active" : ""}
              aria-pressed={windowZoom === level}
              onClick={() => changeWindowZoom(level)}
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
          disabled={windowZoom === 1}
          onChange={(event) => setViewCenter(Number(event.target.value))}
          aria-label="지도 확대 구간 이동"
        />
      </label>

      <div className="map-camera-toolbar">
        <div className="camera-presets" aria-label="3D 지도 시점 선택">
          <span>시점</span>
          <button type="button" className={activeView === "top" ? "active" : ""} onClick={() => applyView("top")}>상공</button>
          <button type="button" className={activeView === "north" ? "active" : ""} onClick={() => applyView("north")}>정북 3D</button>
          <button type="button" className={activeView === "oblique" ? "active" : ""} onClick={() => applyView("oblique")}>도시 사선</button>
          <button type="button" className={activeView === "route" ? "active" : ""} onClick={() => applyView("route")}>진행방향</button>
          <button type="button" className={activeView === "low" ? "active" : ""} onClick={() => applyView("low")}>저각도</button>
        </div>
        <div className="camera-sliders">
          <label>
            <span>기울기 <strong>{cameraPitch}°</strong></span>
            <input type="range" min="0" max="75" value={cameraPitch} onChange={(event) => changePitch(Number(event.target.value))} aria-label="3D 지도 기울기" />
          </label>
          <label>
            <span>방향 <strong>{cameraBearing}°</strong></span>
            <input type="range" min="-180" max="180" value={cameraBearing} onChange={(event) => changeBearing(Number(event.target.value))} aria-label="3D 지도 회전 방향" />
          </label>
        </div>
      </div>

      <div className="actual-map-frame">
        <div
          ref={mapNodeRef}
          className="actual-map"
          role="region"
          aria-label="실제 항공사진, 3D 건물과 지형 위에 표시한 GPS 주행 경로"
        />
        <div className={`map-3d-status ${is3D ? "active" : ""}`} aria-live="polite">
          <span>{is3D ? "S-MAP STYLE · LIVE 3D" : "SATELLITE · TOP VIEW"}</span>
          <small>{is3D ? `기울기 ${cameraPitch}° · 방향 ${cameraBearing}°` : "실사 항공영상 상공 시점"}</small>
        </div>
        <div className="map-dimension-actions" aria-label="지도 차원 보기">
          <button type="button" className={buildingsVisible ? "active" : ""} onClick={toggleBuildings}>3D 건물 {buildingsVisible ? "ON" : "OFF"}</button>
          <button type="button" onClick={fitCurrentSection}>현재 구간 맞춤</button>
          <button type="button" onClick={() => applyView(is3D ? "top" : "oblique")}>{is3D ? "2D 상공" : "실사 3D"}</button>
        </div>
      </div>

      <div className="map-footnote">
        <span>실사 항공사진 · {mapConfig.vworldApiKey ? "VWorld" : "Esri"} / 건물 · OpenStreetMap·OpenFreeMap / 지형 · MapLibre DEM</span>
        <span>왼쪽 드래그 이동 · 휠 확대 · 오른쪽 드래그 회전·시점 변화</span>
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
          <p>충격 지점을 누르면 실제 좌표로 이동하고 건물·지형이 보이는 3D 시점으로 자동 확대됩니다.</p>
          <dl>
            <div><dt>주행 시각</dt><dd>{formatDuration(selectedEvent.time)}</dd></div>
            <div><dt>GPS</dt><dd>{selectedEvent.latitude.toFixed(6)}, {selectedEvent.longitude.toFixed(6)}</dd></div>
            <div><dt>위치 오차</dt><dd>약 ±{selectedEvent.accuracy.toFixed(1)} m</dd></div>
          </dl>
          <div className="spot-actions">
            <a href="#video-review">해당 영상·노면 그래프 보기</a>
            <a href={kakaoRoadViewUrl(selectedEvent.latitude, selectedEvent.longitude)} target="_blank" rel="noreferrer">카카오 실사 로드뷰</a>
            <a href={kakaoMapUrl(selectedEvent.latitude, selectedEvent.longitude)} target="_blank" rel="noreferrer">카카오 좌표 지도</a>
            <a href="https://smap.seoul.go.kr/" target="_blank" rel="noreferrer">S-MAP 3D 열기</a>
          </div>
        </div>
      </div>

      <KakaoRoadview
        latitude={selectedEvent.latitude}
        longitude={selectedEvent.longitude}
        spotId={selectedEvent.id}
      />

      <details className="smap-integration">
        <summary>실사형 3D 지도의 데이터와 한계</summary>
        <div className="smap-grid">
          <div><strong>항공사진</strong><span>실제 촬영 영상을 지형 표면에 표시합니다.</span></div>
          <div><strong>3D 건물</strong><span>OpenStreetMap의 실제 건물 형상과 등록 높이를 사용합니다.</span></div>
          <div><strong>3D 지형</strong><span>DEM 고도자료로 강변과 주변 지형의 높낮이를 표현합니다.</span></div>
          <div><strong>노면 측정 한계</strong><span>포트홀 깊이와 균열 폭은 현재 GPS·단안 영상만으로 실측할 수 없습니다.</span></div>
          <div><strong>자전거도로 선형</strong><span>항공사진만으로 가려지는 구간은 서울시 자전거도로 공간데이터 또는 현장 RTK 궤적을 별도 벡터 레이어로 겹쳐야 합니다.</span></div>
          <div><strong>로드뷰 범위</strong><span>버튼은 정확한 GPS 좌표를 넘기지만 강변 전용도로에 촬영 파노라마가 없으면 인접 일반도로 화면이 열릴 수 있습니다.</span></div>
        </div>
      </details>
    </div>
  );
}
