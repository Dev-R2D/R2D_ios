import rideData from "./data/ride-data.json";
import dongtanFirstCapture from "./data/dongtan-first-capture.json";
import latestCapture from "./data/latest-capture.json";

export type RoadWindow = {
  time: number;
  latitude: number;
  longitude: number;
  speed: number;
  accuracy: number;
  accelRms: number;
  peak: number;
  hfRatio: number;
  score: number;
  confidence: number;
  grade: string;
  eligible: boolean;
};

export type RoadRoutePoint = {
  time: number;
  lat: number;
  lon: number;
  accuracy: number;
};

export type RoadEvent = {
  id: number;
  time: number;
  videoTime?: number;
  latitude: number;
  longitude: number;
  accuracy?: number;
  peakAcceleration?: number;
  decision?: string;
  frame?: string;
  clip?: string;
  surfaceLabel?: string;
  visualEvidence?: string;
  evidence: "video" | "sensor";
};

export type RoadDataset = {
  id: "jamwon" | "dongtan-1" | "dongtan-2";
  label: string;
  shortLabel: string;
  date: string;
  accent: string;
  windows: RoadWindow[];
  route: RoadRoutePoint[];
  events: RoadEvent[];
  defaultIndex: number;
};

function lowestScoredIndex(windows: RoadWindow[]) {
  let selected = 0;
  windows.forEach((window, index) => {
    if (!window.eligible) return;
    if (!windows[selected].eligible || window.score < windows[selected].score) selected = index;
  });
  return selected;
}

function normalizeWindows(
  windows: Array<{
    time: number;
    latitude: number;
    longitude: number;
    speed: number;
    accuracy: number;
    accelRms: number;
    peak: number;
    score: number;
    confidence: number;
    grade: string;
    eligible: boolean;
  }>,
): RoadWindow[] {
  return windows.map((window) => ({
    time: window.time,
    latitude: window.latitude,
    longitude: window.longitude,
    speed: window.speed,
    accuracy: window.accuracy,
    accelRms: window.accelRms,
    peak: window.peak,
    hfRatio: 0,
    score: window.score,
    confidence: window.confidence,
    grade: window.grade,
    eligible: window.eligible,
  }));
}

function normalizeRoute(
  location: Array<{
    seconds_elapsed: number;
    latitude: number;
    longitude: number;
    horizontalAccuracy: number;
  }>,
): RoadRoutePoint[] {
  return location
    .filter((point) => point.seconds_elapsed >= 0)
    .map((point) => ({
      time: point.seconds_elapsed,
      lat: point.latitude,
      lon: point.longitude,
      accuracy: point.horizontalAccuracy,
    }));
}

const jamwonWindows: RoadWindow[] = rideData.windows.map((window) => ({
  ...window,
  eligible: window.confidence >= 0.7,
}));
const dongtanFirstWindows = normalizeWindows(dongtanFirstCapture.windows);
const dongtanSecondWindows = normalizeWindows(latestCapture.windows);

export const roadDatasets: RoadDataset[] = [
  {
    id: "jamwon",
    label: "잠원한강공원 실측 기록",
    shortLabel: "잠원",
    date: "2026.07.17",
    accent: "#58a6ff",
    windows: jamwonWindows,
    route: rideData.route,
    events: rideData.events.map(({ id, time, latitude, longitude, peakAcceleration, label }) => ({
      id, time, latitude, longitude, peakAcceleration, decision: label, evidence: "video",
    })),
    defaultIndex: lowestScoredIndex(jamwonWindows),
  },
  {
    id: "dongtan-1",
    label: "동탄 1차 실측 기록",
    shortLabel: "동탄 1차",
    date: "2026.08.09",
    accent: "#f6b84b",
    windows: dongtanFirstWindows,
    route: normalizeRoute(dongtanFirstCapture.location),
    events: dongtanFirstCapture.events.map(({ id, time, latitude, longitude, peakAcceleration, decision }) => ({
      id, time, latitude, longitude, peakAcceleration, decision, evidence: "sensor",
    })),
    defaultIndex: lowestScoredIndex(dongtanFirstWindows),
  },
  {
    id: "dongtan-2",
    label: "동탄 2차 실측 기록",
    shortLabel: "동탄 2차",
    date: "2026.08.09",
    accent: "#b37cff",
    windows: dongtanSecondWindows,
    route: normalizeRoute(latestCapture.location),
    events: latestCapture.events.map(({ id, time, latitude, longitude, accuracy, peakAcceleration, decision, visualStatus, frame, clip, surfaceLabel, visualEvidence }) => ({
      id,
      time,
      videoTime: time + latestCapture.video.syncOffsetSec,
      latitude,
      longitude,
      accuracy,
      peakAcceleration,
      decision,
      frame,
      clip,
      surfaceLabel,
      visualEvidence,
      evidence: visualStatus === "supported" ? "video" : "sensor",
    })),
    defaultIndex: lowestScoredIndex(dongtanSecondWindows),
  },
];

export function getRoadDataset(id: RoadDataset["id"]) {
  return roadDatasets.find((dataset) => dataset.id === id) ?? roadDatasets[0];
}
