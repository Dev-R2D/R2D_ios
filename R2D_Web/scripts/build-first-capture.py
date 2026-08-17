from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def main() -> None:
    input_dir = Path(sys.argv[1])
    project_dir = Path(sys.argv[2])
    accel = pd.read_csv(input_dir / "Accelerometer.csv")
    gyro = pd.read_csv(input_dir / "Gyroscope.csv")
    location = pd.read_csv(input_dir / "Location.csv")
    metadata = pd.read_csv(input_dir / "Metadata.csv").iloc[0]

    accel_time = accel.seconds_elapsed.to_numpy()
    gyro_time = gyro.seconds_elapsed.to_numpy()
    accel_magnitude = np.linalg.norm(accel[["x", "y", "z"]].to_numpy(), axis=1)
    gyro_magnitude = np.linalg.norm(gyro[["x", "y", "z"]].to_numpy(), axis=1)
    duration = float(min(accel_time.max(), gyro_time.max()))
    peak_index = int(np.argmax(accel_magnitude))

    sample_times = np.linspace(0, duration, 101)
    signal = []
    for start, end in zip(sample_times[:-1], sample_times[1:]):
        accel_mask = (accel_time >= start) & (accel_time < end)
        gyro_mask = (gyro_time >= start) & (gyro_time < end)
        if not accel_mask.any() or not gyro_mask.any():
            continue
        signal.append(
            {
                "time": round(float((start + end) / 2), 3),
                "accel": round(float(np.sqrt(np.mean(accel_magnitude[accel_mask] ** 2))), 3),
                "gyro": round(float(np.sqrt(np.mean(gyro_magnitude[gyro_mask] ** 2))), 3),
            }
        )

    in_session = location[location.seconds_elapsed >= 0]
    output = {
        "metadata": {
            "id": "R2D-260809-111519",
            "role": "ride_1",
            "recordingTime": str(metadata["recording time"]),
            "timezone": str(metadata["recording timezone"]),
            "device": str(metadata["device name"]),
            "durationSec": round(duration, 3),
            "sampleRateHz": round(float(1 / np.median(np.diff(accel_time))), 2),
            "accelSamples": int(len(accel)),
            "gyroSamples": int(len(gyro)),
            "gpsPoints": int(len(location)),
            "inSessionGpsPoints": int(len(in_session)),
            "gpsCoverageSec": round(float(in_session.seconds_elapsed.max() - in_session.seconds_elapsed.min()), 3),
            "medianHorizontalAccuracyM": round(float(location.horizontalAccuracy.median()), 2),
            "latitude": round(float(location.latitude.median()), 7),
            "longitude": round(float(location.longitude.median()), 7),
            "routeAvailable": False,
            "videoAvailable": False,
            "includedInRoadScore": False,
        },
        "event": {
            "time": round(float(accel_time[peak_index]), 3),
            "peakAcceleration": round(float(accel_magnitude[peak_index]), 2),
            "accelRms": round(float(np.sqrt(np.mean(accel_magnitude ** 2))), 2),
            "peakRotation": round(float(gyro_magnitude.max()), 2),
            "gyroRms": round(float(np.sqrt(np.mean(gyro_magnitude ** 2))), 2),
            "decision": "노면 점수 제외",
            "reason": "5초 기록 중 큰 회전이 함께 나타나 출발 전 휴대전화 취급·거치 과정일 가능성이 큽니다.",
        },
        "signal": signal,
        "location": [
            {
                "seconds_elapsed": round(float(row.seconds_elapsed), 3),
                "latitude": round(float(row.latitude), 7),
                "longitude": round(float(row.longitude), 7),
                "horizontalAccuracy": round(float(row.horizontalAccuracy), 2),
            }
            for row in location.itertuples(index=False)
        ],
        "limitations": [
            "전체 기록이 5.0초뿐입니다.",
            "주행 시작 후 GPS가 약 0.1초까지만 기록되어 이동 경로가 없습니다.",
            "Camera 폴더가 비어 있어 센서 이벤트를 영상으로 검증할 수 없습니다.",
            "2차 주행과 같은 구간 반복성 분석에 포함할 수 없습니다.",
        ],
    }

    (project_dir / "app" / "data" / "first-capture.json").write_text(
        json.dumps(output, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    public_dir = project_dir / "public" / "first-capture"
    public_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(signal).to_csv(public_dir / "first-capture-signal.csv", index=False, encoding="utf-8-sig")
    print(json.dumps(output["metadata"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
