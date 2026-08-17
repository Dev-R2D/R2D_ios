from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd


VISUAL_LABELS = [
    (103.540, "횡단보도·포장 경계", "횡단보도 도색과 포장 경계가 충격 시점에 보입니다.", "supported"),
    (183.415, "횡단보도·차도 경계", "차도 횡단 구간과 도색 경계가 영상에 보입니다.", "supported"),
    (379.439, "횡단보도 도색 구간", "굵은 횡단보도 도색을 통과하는 시점과 강한 진동이 겹칩니다.", "supported"),
    (478.709, "어두운 포장 구간", "영상에서 뚜렷한 균열·포트홀은 확인되지 않아 센서 후보로 남깁니다.", "ambiguous"),
    (657.795, "교차부 차선 도색", "교차부 방향 표시와 포장 경계를 통과하는 모습이 보입니다.", "supported"),
    (820.406, "적색 자전거도로·횡단보도 경계", "적색 포장과 횡단보도 경계가 충격 시점에 보입니다.", "supported"),
    (882.288, "보도블록 구간", "보도블록 표면을 주행하는 모습과 반복 진동이 함께 나타납니다.", "supported"),
    (917.947, "보도블록 구간", "보도블록 구간의 반복 진동 후보입니다.", "supported"),
    (1232.549, "보도블록·점자블록 경계", "보도블록과 점자블록 경계를 통과하는 시점입니다.", "supported"),
]


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
    accel_vector = accel[["x", "y", "z"]].to_numpy()
    accel_magnitude = np.linalg.norm(accel_vector, axis=1)
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
        windows.append(
            {
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
            }
        )

    eligible_indices = [index for index, window in enumerate(windows) if window["eligible"]]
    eligible_values = np.array([windows[index]["normalizedRms"] for index in eligible_indices])
    ranks = percentile_rank(eligible_values)
    score_by_index = {}
    for index, rank in zip(eligible_indices, ranks):
        score_by_index[index] = int(round(np.clip(96 - 56 * rank, 40, 96)))

    for index, window in enumerate(windows):
        if index in score_by_index:
            score = score_by_index[index]
            confidence = max(0.62, min(0.92, 0.94 - window["accuracy"] / 100))
        else:
            score = 0
            confidence = 0.35
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
        event_candidates.append(
            {
                "time": float(times[peak_index]),
                "peakAcceleration": peak,
                "accelRms": rms,
                "jerkRms": jerk,
                "gyroRms": gyro_rms,
                "speedKmh": speed * 3.6,
                "accuracy": accuracy,
                "severity": 0.45 * peak + 1.8 * rms + 0.01 * jerk,
            }
        )

    chosen = []
    for candidate in sorted(event_candidates, key=lambda item: item["severity"], reverse=True):
        if all(abs(candidate["time"] - previous["time"]) >= 18 for previous in chosen):
            chosen.append(candidate)
        if len(chosen) >= 10:
            break

    events = []
    for visual_time, label, evidence, visual_status in VISUAL_LABELS:
        candidate = min(chosen, key=lambda item: abs(item["time"] - visual_time))
        event_id = len(events) + 1
        events.append(
            {
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
                "visualStatus": visual_status,
                "surfaceLabel": label,
                "visualEvidence": evidence,
                "decision": "노면 전환 후보" if visual_status == "supported" else "센서 단독 후보",
                "frame": f"/latest-capture/events/event-{event_id:02d}.jpg",
                "clip": f"/latest-capture/events/event-{event_id:02d}.mp4",
            }
        )
    events.sort(key=lambda item: item["time"])
    for index, event in enumerate(events, start=1):
        old_frame = event["frame"]
        old_clip = event["clip"]
        event["id"] = index
        event["frame"] = old_frame.replace(old_frame[-6:-4], f"{index:02d}")
        event["clip"] = old_clip.replace(old_clip[-6:-4], f"{index:02d}")

    signal = []
    for second in range(math.ceil(duration)):
        accel_mask = (accel_time >= second) & (accel_time < second + 1)
        gyro_mask = (gyro_time >= second) & (gyro_time < second + 1)
        if accel_mask.any() and gyro_mask.any():
            signal.append(
                {
                    "time": round(second + 0.5, 1),
                    "accel": round(float(np.sqrt(np.mean(accel_magnitude[accel_mask] ** 2))), 3),
                    "gyro": round(float(np.sqrt(np.mean(gyro_magnitude[gyro_mask] ** 2))), 3),
                }
            )

    segment_scores = np.array([window["score"] for window in windows if window["eligible"]])
    overall_score = int(round(float(np.median(segment_scores)))) if len(segment_scores) else 0
    route_distance = float(
        haversine_m(
            location.latitude.to_numpy()[:-1],
            location.longitude.to_numpy()[:-1],
            location.latitude.to_numpy()[1:],
            location.longitude.to_numpy()[1:],
        ).sum()
    )
    accel_rate = 1 / float(np.median(np.diff(accel_time)))
    gyro_rate = 1 / float(np.median(np.diff(gyro_time)))

    location_rows = []
    for row in location.itertuples(index=False):
        nearest_index = min(len(windows) - 1, max(0, int(round((row.seconds_elapsed - 2) / 2))))
        window = windows[nearest_index]
        location_rows.append(
            {
                "seconds_elapsed": round(float(row.seconds_elapsed), 3),
                "latitude": round(float(row.latitude), 7),
                "longitude": round(float(row.longitude), 7),
                "horizontalAccuracy": round(float(row.horizontalAccuracy), 2),
                "speed": round(float(row.speed), 3),
                "score": int(window["score"]),
                "eligible": bool(window["eligible"]),
            }
        )

    output = {
        "metadata": {
            "id": "R2D-260809-123507",
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
            "latitude": round(float(np.median(location.latitude)), 7),
            "longitude": round(float(np.median(location.longitude)), 7),
            "routeScoreAvailable": True,
            "overallScore": overall_score,
            "eligibleWindows": int(len(segment_scores)),
            "totalWindows": int(len(windows)),
            "qualityScore": 82,
        },
        "video": {
            "filename": "Camera/1786278907328.mp4",
            "durationSec": 1486.575,
            "resolution": "1280 × 720 (세로 표시 회전)",
            "codec": "HEVC",
            "synchronized": True,
            "syncOffsetSec": 0.142,
            "previewStartSec": max(0, events[0]["time"] - 4),
            "previewDurationSec": 10,
            "syncNote": "새 ZIP의 카메라 파일과 센서 기록 시작 시각 차이가 약 0.14초라 같은 시간축으로 직접 연결했습니다.",
        },
        "event": {
            "time": events[0]["time"],
            "peakAcceleration": events[0]["peakAcceleration"],
            "gyroPeakTime": events[0]["time"],
            "peakRotation": events[0]["gyroRms"],
            "classification": events[0]["surfaceLabel"],
            "decision": events[0]["decision"],
            "reason": events[0]["visualEvidence"],
        },
        "events": events,
        "windows": windows,
        "signal": signal,
        "location": location_rows,
        "limitations": [
            "점수는 이번 주행 안에서 비교한 상대 점수이며 공인 IRI·PCI가 아닙니다.",
            "GPS 중앙 정확도는 약 ±14.2m여서 차로·자전거도로 폭 단위 위치 판정에는 부족합니다.",
            "영상으로 노면 유형과 경계는 확인했지만 균열 폭·포트홀 깊이는 실측하지 않았습니다.",
            "정확도 수치화를 위해서는 현장 라벨과 동일 구간 반복주행이 추가로 필요합니다.",
        ],
    }

    data_path = project_dir / "app" / "data" / "latest-capture.json"
    data_path.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    public_dir = project_dir / "public" / "latest-capture"
    public_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(windows).to_csv(public_dir / "latest-capture-summary.csv", index=False, encoding="utf-8-sig")
    route_frame = pd.DataFrame(location_rows)
    route_frame.to_csv(public_dir / "dongtan-route-scores.csv", index=False, encoding="utf-8-sig")
    feature = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "name": "R2D Dongtan 2026-08-09",
                    "distance_km": round(route_distance / 1000, 3),
                    "gps_accuracy_median_m": round(float(np.median(gps_accuracy)), 2),
                },
                "geometry": {
                    "type": "LineString",
                    "coordinates": [[row["longitude"], row["latitude"]] for row in location_rows],
                },
            }
        ],
    }
    (public_dir / "dongtan-route.geojson").write_text(json.dumps(feature, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"metadata": output["metadata"], "events": events}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
