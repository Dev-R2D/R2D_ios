# Sensor Logger 연동

R2D는 외부 Sensor Logger 기록을 곧바로 노면 확정 판정으로 사용하지 않는다. CSV를 표준 `RoadSurfaceSensorSample`로 변환하고, `SensorLogReplayCollector`가 기존 `Telemetry Queue → Upload → Server Observation` 경로로 전달한다. 재생 데이터는 항상 `isSimulated=true`다.

## 권장 연동 방식

1. Sensor Logger 앱에서 CSV를 내보낸다.
2. R2D의 파일 가져오기 또는 Share Extension으로 파일을 전달한다.
3. `SensorLoggerCSVDecoder`가 타임스탬프, 가속도, 자이로, 진동, 위치를 표준화한다.
4. QA에서는 `SensorLogReplayCollector`로 같은 기록을 반복 재생한다.
5. 운영에서는 `CoreMotionSensorCollector`가 동일한 표준 payload를 생성한다.

앱의 Navigator Home에서 **Sensor Logger 기록 가져오기**를 누르면 단일 JSON 또는 압축을 푼 `Accelerometer.csv`, `Gyroscope.csv`, `Gravity.csv`, `Location.csv`를 여러 개 선택할 수 있다. 선택한 현장 기록은 5초 단위 Telemetry chunk로 변환되고 `isSimulated=false`로 Queue 및 Upload Worker에 전달된다. Sensor Logger ZIP은 Files 앱에서 먼저 압축을 풀거나 Sensor Logger에서 JSON 형식으로 내보낸다.

iOS 샌드박스 때문에 서로 다른 개발사의 앱이 상대 앱 센서나 저장소를 실시간으로 직접 읽을 수는 없다. 같은 개발팀이 두 앱을 관리한다면 App Group, Share Extension 또는 명시적인 파일 내보내기를 사용할 수 있다. 일반적인 경우에는 CSV/JSON 내보내기 방식이 가장 안전하다.

## Sensor Logger 실제 형식

- 기본 `Accelerometer.csv`: `time`, `seconds_elapsed`, `x`, `y`, `z`
- `time`은 UTC epoch nanoseconds, `seconds_elapsed`는 기록 시작 후 초다.
- 보정된 가속도와 중력은 m/s², 자이로는 rad/s로 정규화한다.
- 필수: `seconds_elapsed` 또는 `time`, 그리고 `x`, `y`, `z`
- 선택: `gyro_x/y/z`, `vibration_rms`, `jerk`, `latitude`, `longitude`, `speed_mps`
- `time`, `ax/ay/az`, `gx/gy/gz`, `lat/lon` 등의 별칭도 지원한다.

Sensor Logger 설정의 **Standardise Units & Frames**를 켜는 것을 권장한다. 기본 설정에서는 iOS와 Android 가속도·중력 축의 부호가 반대이며, 미보정 iOS 가속도는 g 단위일 수 있다. 기록과 함께 `metadata.csv`의 schema version, platform, 앱 버전을 보관한다.

## 실시간 수집

Sensor Logger는 기록 중 HTTP Push와 MQTT Publish를 지원한다. R2D 운영 권장 경로는 `Sensor Logger → 인증된 서버 수집 endpoint → Observation 처리`다. HTTP payload의 `messageId`는 순서가 뒤바뀔 수 있으므로 중복 제거·정렬 키로 사용하고, `sessionId`, `deviceId`, UTC epoch nanoseconds를 함께 보존한다. Sensor Logger가 R2D 모바일 앱의 로컬 HTTP 서버로 직접 전송하는 방식은 백그라운드·네트워크·인증 제약 때문에 운영 구조로 사용하지 않는다.

현재 백엔드 수집 주소는 `/v1/sensor-logger/push?key=...`다. 서버는 원본 batch와 표준화된 motion/location 값을 저장하고 `PENDING` 상태로 둔다. 수집 ACK는 저장 성공만 의미하며 노면 위험 확정이 아니다. 운영 수집 키는 `R2D_SENSOR_LOGGER_INGEST_KEY` 환경변수로 주입하고 Git에 커밋하지 않는다.

실제 Sensor Logger 샘플 파일을 확보하면 단위(g 또는 m/s²), 시간 기준, 축 방향, 장착 방향을 확정해야 한다. 이 네 항목이 확정되기 전 임계값 기반 노면 등급을 운영 판정에 사용하면 안 된다.

## 에뮬레이터

`SensorLogEmulator`는 `smooth`, `rough`, `impact` 프로필을 제공한다. 이는 UI·Queue·Upload 파이프라인 검증 전용이며 실제 위험 셀 생성이나 확정 판정의 근거가 아니다.

## 화성시 데이터

`hwaseong-bike-roads.csv`는 2026-06-01 기준 화성시 자전거도로 공공데이터다. 357개 레코드 중 유효하고 서로 다른 기점·종점 좌표를 가진 121개를 읽는다. 전체 선형 좌표가 없어 데모 지도는 `ENDPOINTS_ONLY` 품질로 표시하며, 정식 경로 탐색에는 별도의 도로 중심선/라우팅 데이터가 필요하다.
