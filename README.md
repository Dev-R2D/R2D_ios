# R2D

R2D는 Navigator를 기본 제품으로 두고, 하나의 Ride Session을 Navigator와 Game이 공유하는 SwiftUI P0 구현입니다.

## 실행 및 검증

```sh
swift test
swift build
```

`R2DUI/R2DAppView`를 iOS SwiftUI App target의 루트 뷰로 사용하면 됩니다. 기본 composition은 mock 위치·센서·경로와 in-memory 서버를 사용해 전체 주행 흐름을 재현합니다.

## Navigator Demo

서버와 GPS 없이 실행하는 팀 공유용 1차 데모는 [`docs/NAVIGATOR_DEMO.md`](docs/NAVIGATOR_DEMO.md)를 참고하세요. Xcode에서 `R2D-Navigator-Demo` scheme을 선택하면 됩니다. Navigator↔Game 전환은 유지되며 Game은 자동 전투 보조 미리보기만 노출합니다.

## 핵심 원칙

- 화면 전환은 `activeView`만 바꾸며 수집기를 재시작하지 않습니다.
- Navigator와 Game은 서로를 import하지 않고 `ActiveRideCoordinator` 상태만 구독합니다.
- 예상 진행도와 서버 확정 진행도를 별도로 표시합니다.
- `DataState`와 `RiskState`는 독립적으로 관리합니다.
- 업로드 큐는 ACK된 청크만 제거합니다.
