from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def haversine_m(lat1, lon1, lat2, lon2):
    radius = 6_371_000.0
    phi1 = np.radians(lat1)
    phi2 = np.radians(lat2)
    delta_phi = phi2 - phi1
    delta_lambda = np.radians(lon2 - lon1)
    value = np.sin(delta_phi / 2) ** 2 + np.cos(phi1) * np.cos(phi2) * np.sin(delta_lambda / 2) ** 2
    return 2 * radius * np.arcsin(np.sqrt(value))


def percentile_rank(values: np.ndarray) -> np.ndarray:
    order = np.argsort(values)
    ranks = np.empty_like(order, dtype=float)
    ranks[order] = np.linspace(0, 1, len(values), endpoint=True)
    return ranks


def main() -> None:
    input_dir = Path(sys.argv[1])
    project_dir = Path(sys.argv[2])
    accel = pd.read_csv(input_dir / "Accelerometer.csv")
    gyro = pd.read_csv(input_dir / "Gyroscope.csv")
    location = pd.read_csv(input_dir / "Location.csv")
    metadata = pd.read_csv(input_dir / "Metadata.csv").iloc[0]

    accel_time = accel.seconds_elapsed.to_numpy()
    accel_magnitude = np.linalg.norm(accel[["x", "y", "z"]].to_numpy(), axis=1)
    gyro_time = gyro.seconds_elapsed.to_numpy()
    gyro_magnitude = np.linalg.norm(gyro[["x", "y", "z"]].to_numpy(), axis=1)
    gps_time = location.seconds_elapsed.to_numpy()
    gps_speed = location.speed.to_numpy()
    gps_accuracy = location.horizontalAccuracy.to_numpy()
    duration = float(min(accel_time.max(), gyro_time.max(), gps_time.max()))
    moving_speed = gps_speed[gps_speed > 0.5]
    reference_speed = float(np.median(moving_speed)) if len(moving_speed) else 2.5

    windows = []
    for start in np.arange(0, duration - 4, 2):
        end = start + 4
        center = start + 2
        accel_mask = (accel_time >= start) & (accel_time < end)
        gyro_mask = (gyro_time >= start) & (gyro_time < end)
        if accel_mask.sum() < 250 or gyro_mask.sum() < 250:
            continue
        values = accel_magnitude[accel_mask]
        times = accel_time[accel_mask]
        gyro_values = gyro_magnitude[gyro_mask]
        rms = float(np.sqrt(np.mean(values ** 2)))
        peak = float(values.max())
        jerk = float(np.sqrt(np.mean((np.diff(values) / np.diff(times)) ** 2)))
        gyro_rms = float(np.sqrt(np.mean(gyro_values ** 2)))
        speed = float(np.interp(center, gps_time, gps_speed))
        accuracy = float(np.interp(center, gps_time, gps_accuracy))
        normalized_rms = rms * (reference_speed / max(speed, 1.5)) ** 0.8
        eligible = speed >= 1.5 and gyro_rms < 1.0 and accuracy <= 30
        windows.append({
            "start": round(float(start), 3),
            "end": round(float(end), 3),
            "time": round(float(center), 3),
            "latitude": round(float(np.interp(center, gps_time, location.latitude)), 7),
            "longitude": round(float(np.interp(center, gps_time, location.longitude)), 7),
            "speed": round(speed, 3),
            "accuracy": round(accuracy, 2),
            "accelRms": round(rms, 3),
            "peak": round(peak, 3),
            "jerkRms": round(jerk, 3),
            "gyroRms": round(gyro_rms, 3),
            "normalizedRms": round(normalized_rms, 3),
            "eligible": eligible,
        })

    eligible_indices = [index for index, window in enumerate(windows) if window["eligible"]]
    eligible_values = np.array([windows[index]["normalizedRms"] for index in eligible_indices])
    ranks = percentile_rank(eligible_values)
    score_by_index = {
        index: int(round(np.clip(96 - 56 * rank, 40, 96)))
        for index, rank in zip(eligible_indices, ranks)
    }
    for index, window in enumerate(windows):
        score = score_by_index.get(index, 0)
        confidence = max(0.62, min(0.92, 0.94 - window["accuracy"] / 100)) if score else 0.35
        window["score"] = score
        window["confidence"] = round(confidence, 2)
        window["grade"] = "good" if score >= 80 else "fair" if score >= 65 else "caution" if score >= 50 else "poor"

    event_candidates = []
    for center in np.arange(0.5, duration - 0.5, 0.5):
        accel_mask = (accel_time >= center - 0.75) & (accel_time <= center + 0.75)
        gyro_mask = (gyro_time >= center - 0.75) & (gyro_time <= center + 0.75)
        if accel_mask.sum() < 100 or gyro_mask.sum() < 100:
            continue
        values = accel_magnitude[accel_mask]
        times = accel_time[accel_mask]
        peak_index = int(np.argmax(values))
        rms = float(np.sqrt(np.mean(values ** 2)))
        peak = float(values[peak_index])
        jerk = float(np.sqrt(np.mean((np.diff(values) / np.diff(times)) ** 2)))
        gyro_rms = float(np.sqrt(np.mean(gyro_magnitude[gyro_mask] ** 2)))
        speed = float(np.interp(center, gps_time, gps_speed))
        accuracy = float(np.interp(center, gps_time, gps_accuracy))
        if speed < 1.5 or gyro_rms > 1.0 or accuracy > 30:
            continue
        event_candidates.append({
            "time": float(times[peak_index]),
            "peakAcceleration": peak,
            "accelRms": rms,
            "jerkRms": jerk,
            "gyroRms": gyro_rms,
            "speedKmh": speed * 3.6,
            "accuracy": accuracy,
            "severity": 0.45 * peak + 1.8 * rms + 0.01 * jerk,
        })

    chosen = []
    for candidate in sorted(event_candidates, key=lambda item: item["severity"], reverse=True):
        if all(abs(candidate["time"] - previous["time"]) >= 18 for previous in chosen):
            chosen.append(candidate)
        if len(chosen) >= 9:
            break
    chosen.sort(key=lambda item: item["time"])
    events = []
    for event_id, candidate in enumerate(chosen, start=1):
        events.append({
            "id": event_id,
            "time": round(candidate["time"], 3),
            "latitude": round(float(np.interp(candidate["time"], gps_time, location.latitude)), 7),
            "longitude": round(float(np.interp(candidate["time"], gps_time, location.longitude)), 7),
            "accuracy": round(candidate["accuracy"], 2),
            "speedKmh": round(candidate["speedKmh"], 1),
            "peakAcceleration": round(candidate["peakAcceleration"], 2),
            "accelRms": round(candidate["accelRms"], 2),
            "jerkRms": round(candidate["jerkRms"], 1),
            "gyroRms": round(candidate["gyroRms"], 2),
            "surfaceLabel": "센서 고충격 후보",
            "decision": "센서 단독 후보",
        })

    signal = []
    for second in range(math.ceil(duration)):
        accel_mask = (accel_time >= second) & (accel_time < second + 1)
        gyro_mask = (gyro_time >= second) & (gyro_time < second + 1)
        if accel_mask.any() and gyro_mask.any():
            signal.append({
                "time": round(second + 0.5, 1),
                "accel": round(float(np.sqrt(np.mean(accel_magnitude[accel_mask] ** 2))), 3),
                "gyro": round(float(np.sqrt(np.mean(gyro_magnitude[gyro_mask] ** 2))), 3),
            })

    segment_scores = np.array([window["score"] for window in windows if window["eligible"]])
    route_distance = float(haversine_m(
        location.latitude.to_numpy()[:-1], location.longitude.to_numpy()[:-1],
        location.latitude.to_numpy()[1:], location.longitude.to_numpy()[1:],
    ).sum())
    location_rows = []
    for row in location.itertuples(index=False):
        nearest_index = min(len(windows) - 1, max(0, int(round((row.seconds_elapsed - 2) / 2))))
        window = windows[nearest_index]
        location_rows.append({
            "seconds_elapsed": round(float(row.seconds_elapsed), 3),
            "latitude": round(float(row.latitude), 7),
            "longitude": round(float(row.longitude), 7),
            "horizontalAccuracy": round(float(row.horizontalAccuracy), 2),
            "speed": round(float(row.speed), 3),
            "score": int(window["score"]),
            "eligible": bool(window["eligible"]),
        })

    accel_rate = 1 / float(np.median(np.diff(accel_time)))
    gyro_rate = 1 / float(np.median(np.diff(gyro_time)))
    output = {
        "metadata": {
            "id": "R2D-260809-123451-D1",
            "recordingTime": str(metadata["recording time"]),
            "timezone": str(metadata["recording timezone"]),
            "device": str(metadata["device name"]),
            "platform": str(metadata["platform"]),
            "appVersion": str(metadata["appVersion"]),
            "durationSec": round(duration, 3),
            "sampleRateHz": round((accel_rate + gyro_rate) / 2, 2),
            "accelSamples": int(len(accel)),
            "gyroSamples": int(len(gyro)),
            "gpsPoints": int(len(location)),
            "medianHorizontalAccuracyM": round(float(np.median(gps_accuracy)), 2),
            "medianSpeedKmh": round(float(np.median(moving_speed) * 3.6), 2),
            "routeDistanceKm": round(route_distance / 1000, 3),
            "overallScore": int(round(float(np.median(segment_scores)))) if len(segment_scores) else 0,
            "eligibleWindows": int(len(segment_scores)),
            "totalWindows": int(len(windows)),
            "qualityScore": 76,
            "videoAvailable": False,
        },
        "events": events,
        "windows": windows,
        "signal": signal,
        "location": location_rows,
        "limitations": [
            "영상이 없어 센서 고충격 후보의 실제 노면 유형은 확인하지 않았습니다.",
            "점수는 이 기록 내부의 상대 점수이며 공인 IRI·PCI가 아닙니다.",
            "두 동탄 데이터는 시작 시각이 약 16초 차이여서 동일 주행 중 서로 다른 기기 기록일 가능성이 높습니다.",
        ],
    }

    data_path = project_dir / "app" / "data" / "dongtan-first-capture.json"
    data_path.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    public_dir = project_dir / "public" / "dongtan-first"
    public_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(windows).to_csv(public_dir / "dongtan-first-summary.csv", index=False, encoding="utf-8-sig")
    pd.DataFrame(location_rows).to_csv(public_dir / "dongtan-first-route-scores.csv", index=False, encoding="utf-8-sig")
    feature = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "properties": {
                "name": "R2D Dongtan first dataset 2026-08-09",
                "distance_km": round(route_distance / 1000, 3),
                "gps_accuracy_median_m": round(float(np.median(gps_accuracy)), 2),
            },
            "geometry": {
                "type": "LineString",
                "coordinates": [[row["longitude"], row["latitude"]] for row in location_rows],
            },
        }],
    }
    (public_dir / "dongtan-first-route.geojson").write_text(json.dumps(feature, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"metadata": output["metadata"], "events": events}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
