# iOS production adapters

`AppContainer.production()`은 iOS에서 `CoreLocationTracker`와 `CoreMotionSensorCollector`를 한 번 생성해 Coordinator에 주입한다. View 전환은 이 인스턴스에 영향을 주지 않는다.

Location 기본값은 정확도 10m, distance filter 3m, 최대 표본 나이 10초, 허용 수평 정확도 50m, 현실적 최고 속도 30m/s다. 음수 정확도와 오래된/중복 표본은 제외하며 음수 speed/course는 값 없음으로 정규화한다. 최고 속도를 넘는 표본은 `implausibleJump`로 분류해 거리에서 제외한다.

Motion 기본값은 가속도계 100Hz, 자이로/DeviceMotion 50Hz, 5초 청크, 최대 버퍼 목표 30초다. Apple API 요청 주기는 목표값이며 실제 `effectiveHz`를 별도로 계산한다. 프레임워크 객체는 `Sendable`이 아니므로 adapter의 lock으로 mutable state를 직렬화하고 immutable `SensorChunk`만 Port 밖으로 보낸다.

Always 위치 권한과 장시간 백그라운드 센서 수집은 이 단계에서 활성화하지 않는다.

CoreMotion raw sample은 adapter 내부 직렬 buffer에서 JSON payload로 묶인 뒤 5초 `SensorChunk`로만 전달된다. Production Container는 Keychain AES-GCM Queue와 단일 Upload Worker를 생성하므로 Navigator/Game 전환으로 재생성되지 않는다.

MapKit은 `R2DUI/MapRenderers.swift`에서만 사용한다. 서버 Road Cell은 Core의 `MapRiskOverlay`로 변환된 뒤 renderer에 전달되며 Route, Turn, Destination, Current Location layer는 Risk 갱신 시 유지된다. Production은 Application Support의 `R2D/RiskLayer` cache를 사용하고 Preview/Test는 deterministic in-memory cache를 사용한다.
