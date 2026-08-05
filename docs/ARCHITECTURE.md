# R2D P0 architecture

```text
Navigator UI ─┐
Game UI ──────┼─ subscribe ─> ActiveRideCoordinator ─> Ride Domain
Safety UI ────┘                         │
                           Location / Sensor / Route ports
                                      │
                              Queue / Progress server
```

## Risk layer

```text
Road Cell API -> IRiskLayerRepository -> RiskLayerSyncWorker (actor)
              -> IRiskLayerCache -> immutable RiskLayerSnapshot
              -> RoadWarningEngine -> ActiveRideCoordinator
              -> MapRiskOverlay / shared SafetyOverlay
```

`DataState`는 정보의 검증·최신성이고 `RiskState`는 도로 상태다. 따라서 `UNKNOWN`은 위험이 아니며, `VERIFIED + CONFIRMED_DAMAGE`와 `STALE + CONFIRMED_DAMAGE` 모두 유효한 조합이다. Route 응답의 `RiskCell`은 preview 힌트일 뿐 지도와 경고의 authoritative source로 사용하지 않는다.

Progress의 `riskLayerVersion`이 현재 snapshot과 다를 때만 route corridor를 다시 조회한다. Risk API 실패는 Progress 적용이나 Ride Session을 중단하지 않으며 마지막 cache를 유지한다. Core와 NavigationEngine은 MapKit을 import하지 않는다.

`ActiveRideView`는 세션과 별개의 UI 상태다. 화면 전환은 tracker의 `start`, `stop`, `pause`를 호출하지 않는다. 확정 피해는 `RideProgressSync` 응답에서만 갱신되고, 로컬 거리와 센서 청크는 pending 연출에만 사용된다.

## Production adapter extension points

- `LocationTracker`: CoreLocation 기반 구현
- `SensorCollector`: CoreMotion 기반 구현
- `RouteProvider`: 외부 지도/경로 SDK 구현
- `TelemetryQueue`: 암호화된 파일 또는 SQLite 구현
- `RideProgressSync`: OpenAPI 기반 HTTP 구현

현재 P0 composition은 결정론적 테스트가 가능한 mock adapter를 연결한다. `SensorChunk.isSimulated`는 실제 수집 데이터와 QA replay를 구분한다.

## iOS application and isolation

`R2D.xcodeproj`의 R2D iOS 17 App Target은 `App/R2DApp.swift`만 소유하고, 로컬 Package의 `R2DAppSupport`와 `R2DUI`를 연결한다. `AppContainer.production()`이 CoreLocation/CoreMotion을 생성하며 Preview/Test는 Mock을 주입한다.

SwiftUI와 `ActiveRideCoordinator`는 `@MainActor`다. CoreLocation delegate와 CoreMotion operation queue는 adapter 내부 lock으로 직렬화되며, 고빈도 raw sample은 UI로 전달되지 않는다. Coordinator는 저빈도 LocationSnapshot과 5초 SensorChunk만 받는다.

`AppLifecycleController`는 최초 실행과 active 복귀 시 restore/readiness를 확인하고 background 진입 시 현재 세션을 저장한다. inactive 또는 단순 View 전환은 수집을 중단하지 않는다. iOS 백그라운드 정책 아래 장시간 센서 지속성, 화면 잠금, 비정상 종료 복원은 실제 기기 검증 대상이다.

Production Ride Session은 Application Support의 atomic JSON 파일에 Data Protection 옵션으로 저장한다.

## Production telemetry pipeline

```text
CoreMotion → SensorChunk → ActiveRideCoordinator
                              ↓ TelemetryPipeline port
AES-GCM Persistent Queue → Upload Worker → HTTP Uploader → ACK delete
```

Queue와 Worker는 actor이고 MainActor 및 화면 생명주기와 분리된다. Coordinator는 암호화, 파일 경로, Keychain, URLSession과 retry 계산을 알지 못하며 immutable `TelemetryQueueSummary`만 UI에 반영한다. Game 확정 피해는 이 ACK가 아니라 별도 Progress 응답만 갱신한다.
