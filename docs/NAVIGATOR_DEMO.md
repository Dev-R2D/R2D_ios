# R2D Navigator 1차 데모

## 목적

서버, 계정, API Key, Simulator GPS 없이 Route Matching, Turn/ETA, MapKit rendering, Risk Overlay, Safety Warning과 reroute를 팀에서 재현하는 Navigator 검증용 데모입니다. Game Domain은 삭제하지 않고 자동 전투 미리보기만 제공합니다.

## 포함 기능

- Navigator 홈, 테스트 목적지와 경로 후보 3개
- 빠른 경로, 안전 경로, 자전거 우선 경로 비교
- 실제 `NavigationEngine`, `RoadWarningEngine`, MapKit Adapter
- 결정론적 위치 Replay와 Demo Sensor
- UNKNOWN, STALE, REVIEW, ROUGH, CONFIRMED_DAMAGE Risk fixture
- Turn, 남은 거리, ETA, 진행률 갱신
- off-route와 자동 reroute
- Safety Overlay 및 동일 Cell cooldown
- Navigator ↔ Game 전환
- Game 자동 전투, Boss HP, 예상 피해/서버 확정 피해, Navigator 미니 안내
- 목적지 도착 시 자동 주행 결과

## 제외 기능

Game의 장비 변경, 인벤토리, 보상 수령, 쿠폰, Mission 상세, 복잡한 설정, 인증/Queue/API debug, Raw Sensor와 내부 로그는 표시하지 않습니다. Reward와 Mission 기능은 코드에 남아 있고 Demo Feature Flag로 비활성화됩니다.

## 실행 요구사항

- Xcode와 iOS 17 이상 Simulator
- 서버와 별도 계정 불필요
- API Key와 실제 위치 권한 불필요
- 지도 타일 표시에는 네트워크가 유용하지만 Route/Overlay/Replay 상태 흐름은 오프라인에서도 유지됩니다.

## Xcode 실행

1. `R2D.xcodeproj`를 엽니다.
2. shared scheme `R2D-Navigator-Demo`를 선택합니다.
3. iPhone Simulator를 선택하고 Run 합니다.
4. 홈에서 `안전 경로`를 선택합니다.
5. `데모 경로 시작`을 누릅니다.

Scheme은 `R2D_ENVIRONMENT=demoNavigator`를 전달합니다. 기존 `R2D` scheme과 Production composition은 변경하지 않습니다.

## 권장 시나리오

1. 세 경로의 차이를 확인하고 안전 경로를 선택합니다.
2. 데모 데이터 준비 상태와 Risk 범례를 확인합니다.
3. 시작 후 Turn, ETA, 남은 거리 감소를 봅니다.
4. `위험` 이동으로 거친 노면과 확정 위험 Safety Overlay를 확인합니다.
5. `Game 미리보기`에서 자동 전투와 예상/확정 피해 분리를 확인합니다.
6. `Navigator로 복귀`합니다.
7. `Reroute` 이동으로 경로 재탐색과 새 polyline을 확인합니다.
8. `도착 전` 이동으로 자동 결과 화면을 확인합니다.

## Demo Control

Demo 환경에서만 지도 상단에 표시됩니다.

- `1x / 3x / 5x`: 재생 속도
- `처음`: 동일 seed의 첫 위치로 이동
- `위험`: 위험 구간으로 이동
- `Reroute`: off-route 구간으로 이동
- `도착 전`: 목적지 직전으로 이동
- 일반 일시정지/재개 버튼은 Replay와 Ride Session을 함께 제어합니다.

## 실제 데이터와 구분

화면의 `데모 모드 · 로컬 데이터`, `데모 데이터`, `DEMO` 배지가 표시되면 CoreLocation, 운영 서버 및 실사용자 데이터가 아닙니다. 지도, NavigationEngine, WarningEngine과 Coordinator는 Production과 같은 구현입니다.

## 초기화와 문제 해결

- 주행 중에는 Demo Control의 `처음`을 누릅니다.
- 완전 초기화는 앱을 종료한 뒤 다시 Run 합니다. Demo environment는 in-memory session/cache를 사용하므로 항상 초기 상태로 시작합니다.
- Route가 없으면 홈 화면이 로딩될 때까지 잠시 기다립니다.
- 지도 타일이 비어 있어도 route polyline과 안내 상태는 계속 진행됩니다.

## 알려진 제한사항

- Replay 위치와 Risk fixture는 코드에 고정된 P0 데이터입니다.
- Mock Progress는 Boss 확정 피해 예시를 제공하며 운영 서버 계산을 대신하지 않습니다.
- 음성 TTS와 실제 백그라운드 장시간 위치 수집은 이 데모 범위가 아닙니다.
- 실제 기기 권한, GPS 품질과 서버 지연은 Production 환경에서 별도 검증해야 합니다.

## Fixture 위치

공유 가능한 manifest는 `Sources/R2DInfrastructure/Resources/Demo/`에 있고, 실행 fixture는 `DemoNavigatorFixture`에서 타입 안전한 Domain Model로 제공합니다.
