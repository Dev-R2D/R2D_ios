#!/usr/bin/env python3
import csv
import json
import math
import statistics
from bisect import bisect_left
from pathlib import Path


BASE = Path("/Users/seulbinlee/Downloads/_-2026-08-09_12-34-51")
VIDEO_PATH = Path("/Users/seulbinlee/Downloads/1786278944600.mp4")
OUT = Path("processed/sensor-2026-08-09")
RAW_OUT = Path("raw/sensor-2026-08-09-capture.json")


def read_xyz(name):
    rows = []
    with (BASE / name).open(newline="") as f:
        for row in csv.DictReader(f):
            t = float(row["seconds_elapsed"])
            x = float(row["x"])
            y = float(row["y"])
            z = float(row["z"])
            mag = math.sqrt(x * x + y * y + z * z)
            rows.append((t, x, y, z, mag))
    return rows


def read_location():
    rows = []
    with (BASE / "Location.csv").open(newline="") as f:
        for row in csv.DictReader(f):
            rows.append(
                {
                    "time": float(row["seconds_elapsed"]),
                    "latitude": float(row["latitude"]),
                    "longitude": float(row["longitude"]),
                    "horizontalAccuracy": float(row["horizontalAccuracy"]),
                    "speed": max(0.0, float(row["speed"])),
                }
            )
    return rows


def read_metadata():
    with (BASE / "Metadata.csv").open(newline="") as f:
        return next(csv.DictReader(f))


def slice_by_time(rows, times, start, end):
    left = bisect_left(times, start)
    right = bisect_left(times, end)
    return rows[left:right]


def nearest_location(locations, loc_times, t):
    i = bisect_left(loc_times, t)
    if i <= 0:
        return locations[0]
    if i >= len(locations):
        return locations[-1]
    before = locations[i - 1]
    after = locations[i]
    return before if abs(before["time"] - t) <= abs(after["time"] - t) else after


def percentile_ranks(values):
    ordered = sorted(values)
    n = len(ordered)
    ranks = {}
    for value in ordered:
        ranks[value] = (bisect_left(ordered, value) + 0.5) / n
    return ranks


def rms(values):
    if not values:
        return 0.0
    return math.sqrt(sum(v * v for v in values) / len(values))


def mean(values):
    return sum(values) / len(values) if values else 0.0


def median(values):
    return statistics.median(values) if values else 0.0


def haversine_km(a, b):
    lat1 = math.radians(a["latitude"])
    lat2 = math.radians(b["latitude"])
    dlat = lat2 - lat1
    dlon = math.radians(b["longitude"] - a["longitude"])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371.0 * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))


def grade(score):
    if score >= 82:
        return "good"
    if score >= 68:
        return "fair"
    if score >= 54:
        return "caution"
    return "inspect"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    accel = read_xyz("Accelerometer.csv")
    gyro = read_xyz("Gyroscope.csv")
    locations = read_location()
    metadata = read_metadata()

    accel_times = [r[0] for r in accel]
    gyro_times = [r[0] for r in gyro]
    loc_times = [r["time"] for r in locations]
    duration = min(accel[-1][0], gyro[-1][0], locations[-1]["time"])
    median_speed = median([p["speed"] for p in locations if p["speed"] >= 1.5]) or median(
        [p["speed"] for p in locations]
    )

    windows = []
    start = 0.0
    while start + 4.0 <= duration:
        end = start + 4.0
        mid = start + 2.0
        acc_slice = slice_by_time(accel, accel_times, start, end)
        gyro_slice = slice_by_time(gyro, gyro_times, start, end)
        loc_slice = [p for p in locations[bisect_left(loc_times, start) : bisect_left(loc_times, end)]]
        loc = nearest_location(locations, loc_times, mid)

        acc_mags = [r[4] for r in acc_slice]
        gyro_mags = [r[4] for r in gyro_slice]
        speed = mean([p["speed"] for p in loc_slice]) if loc_slice else loc["speed"]
        accuracy = median([p["horizontalAccuracy"] for p in loc_slice]) if loc_slice else loc["horizontalAccuracy"]
        accel_rms = rms(acc_mags)
        gyro_rms = rms(gyro_mags)
        peak = max(acc_mags) if acc_mags else 0.0

        jerk_values = []
        for prev, cur in zip(acc_slice, acc_slice[1:]):
            dt = cur[0] - prev[0]
            if dt > 0:
                jerk_values.append(abs(cur[4] - prev[4]) / dt)

        normalized = accel_rms * ((median_speed / speed) ** 0.8) if speed > 0 else 0.0
        eligible = (
            speed >= 1.5
            and gyro_rms < 1.0
            and accuracy <= 30.0
            and len(acc_slice) >= 250
            and len(gyro_slice) >= 250
        )

        windows.append(
            {
                "start": round(start, 3),
                "end": round(end, 3),
                "time": round(mid, 3),
                "latitude": round(loc["latitude"], 7),
                "longitude": round(loc["longitude"], 7),
                "speed": round(speed, 3),
                "accuracy": round(accuracy, 2),
                "accelRms": round(accel_rms, 3),
                "peak": round(peak, 3),
                "jerkRms": round(rms(jerk_values), 3),
                "gyroRms": round(gyro_rms, 3),
                "normalizedRms": round(normalized, 3),
                "eligible": eligible,
                "score": 0,
                "confidence": 0.35 if not eligible else 1.0,
                "grade": "excluded",
                "accelSamples": len(acc_slice),
                "gyroSamples": len(gyro_slice),
            }
        )
        start += 2.0

    eligible_values = [w["normalizedRms"] for w in windows if w["eligible"]]
    ranks = percentile_ranks(eligible_values)
    for w in windows:
        if w["eligible"]:
            score = max(40, min(96, 96 - 56 * ranks[w["normalizedRms"]]))
            w["score"] = round(score, 1)
            w["grade"] = grade(score)

    route_scores = []
    for loc in locations:
        closest = min(windows, key=lambda w: abs(w["time"] - loc["time"]))
        route_scores.append(
            {
                "seconds_elapsed": round(loc["time"], 3),
                "latitude": round(loc["latitude"], 7),
                "longitude": round(loc["longitude"], 7),
                "horizontalAccuracy": round(loc["horizontalAccuracy"], 2),
                "speed": round(loc["speed"], 3),
                "score": closest["score"],
                "eligible": closest["eligible"],
            }
        )

    eligible_windows = [w for w in windows if w["eligible"]]
    event_candidates = sorted(eligible_windows, key=lambda w: (w["score"], -w["normalizedRms"]))
    events = []
    for candidate in event_candidates:
        if all(abs(candidate["time"] - picked["time"]) >= 20.0 for picked in events):
            events.append(candidate)
        if len(events) == 10:
            break
    events = sorted(events, key=lambda w: w["time"])
    event_payload = []
    for i, w in enumerate(events, 1):
        event_payload.append(
            {
                "id": i,
                "time": w["time"],
                "videoTime": w["time"],
                "latitude": w["latitude"],
                "longitude": w["longitude"],
                "accuracy": w["accuracy"],
                "speedKmh": round(w["speed"] * 3.6, 1),
                "peakAcceleration": w["peak"],
                "accelRms": w["accelRms"],
                "jerkRms": w["jerkRms"],
                "gyroRms": w["gyroRms"],
                "score": w["score"],
                "visualStatus": "video-linked",
                "decision": "영상 확인 후보",
                "surfaceLabel": "상대적 고진동 구간",
                "videoSource": str(VIDEO_PATH),
            }
        )

    def write_csv(path, rows, fields):
        with path.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)

    write_csv(
        OUT / "sensor-2026-08-09-summary.csv",
        windows,
        [
            "start",
            "end",
            "time",
            "latitude",
            "longitude",
            "speed",
            "accuracy",
            "accelRms",
            "peak",
            "jerkRms",
            "gyroRms",
            "normalizedRms",
            "eligible",
            "score",
            "confidence",
            "grade",
            "accelSamples",
            "gyroSamples",
        ],
    )
    write_csv(
        OUT / "sensor-2026-08-09-route-scores.csv",
        route_scores,
        ["seconds_elapsed", "latitude", "longitude", "horizontalAccuracy", "speed", "score", "eligible"],
    )
    write_csv(
        OUT / "sensor-2026-08-09-events.csv",
        event_payload,
        [
            "id",
            "time",
            "videoTime",
            "latitude",
            "longitude",
            "accuracy",
            "speedKmh",
            "peakAcceleration",
            "accelRms",
            "jerkRms",
            "gyroRms",
            "score",
            "visualStatus",
            "decision",
            "surfaceLabel",
            "videoSource",
        ],
    )

    coords = [[p["longitude"], p["latitude"]] for p in locations]
    distance = sum(haversine_km(a, b) for a, b in zip(locations, locations[1:]))
    geojson = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "name": "sensor-2026-08-09",
                    "distance_km": round(distance, 2),
                    "gps_accuracy_median_m": round(median([p["horizontalAccuracy"] for p in locations]), 2),
                },
                "geometry": {"type": "LineString", "coordinates": coords},
            }
        ],
    }
    (OUT / "sensor-2026-08-09-route.geojson").write_text(json.dumps(geojson, ensure_ascii=False, indent=2))

    overall = median([w["score"] for w in eligible_windows])
    raw_payload = {
        "metadata": {
            "id": "R2D-260809-123451",
            "recordingTime": metadata["recording time"],
            "timezone": metadata["recording timezone"],
            "device": metadata["device name"],
            "platform": metadata["platform"],
            "appVersion": metadata["appVersion"],
            "durationSec": round(duration, 3),
            "sampleRateHz": round(len(accel) / duration, 2),
            "accelSamples": len(accel),
            "gyroSamples": len(gyro),
            "gpsPoints": len(locations),
            "medianHorizontalAccuracyM": round(median([p["horizontalAccuracy"] for p in locations]), 2),
            "medianSpeedKmh": round(median([p["speed"] for p in locations]) * 3.6, 2),
            "routeDistanceKm": round(distance, 2),
            "routeScoreAvailable": True,
            "overallScore": round(overall, 1),
            "eligibleWindows": len(eligible_windows),
            "totalWindows": len(windows),
            "scoreBasis": "4초 창 · 2초 간격 · 주행 내 상대평가",
            "videoSource": str(VIDEO_PATH),
        },
        "location": locations,
        "windows": windows,
        "events": event_payload,
        "limitations": [
            "빨간 구간은 파손 확정이 아니라 영상 검토 또는 현장 점검이 필요한 상대적 고진동 후보입니다.",
            "본 점수는 공인 IRI·PCI 또는 정밀 노면 측량값이 아닙니다.",
            "주행마다 백분위 순위를 다시 계산하므로 서로 다른 주행의 점수를 절대 비교하지 않습니다.",
        ],
    }
    RAW_OUT.write_text(json.dumps(raw_payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
