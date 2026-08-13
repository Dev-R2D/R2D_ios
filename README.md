# R2D_iOS

R2D는 UIKit 기반 Navigator를 기본 제품으로 두고, iOS는 `UIViewController`, Android 확장은 Flutter와 JavaScript WebView 레이어를 기준으로 구현합니다.

## 실행 및 검증

```sh
swift test
swift build
```

Xcode에서는 `R2D-Navigator-Demo` scheme을 선택해 iOS Simulator에서 실행합니다. 앱 루트는 `App/R2DApp.swift`의 UIKit `SceneDelegate`와 `R2DUIKit/R2DRootViewController`입니다.

## 로컬 키 설정

Google Maps iOS 키와 카카오 네이티브 키는 저장소에 직접 넣지 않고 로컬 설정으로 관리합니다.

1. `Config/Local.xcconfig.example`를 복사해서 `Config/Local.xcconfig` 생성
2. 아래 값을 로컬 파일에 입력
   - `KAKAO_NATIVE_APP_KEY`
   - `R2D_GOOGLE_MAPS_API_KEY`

## Navigator Demo

서버와 GPS 없이 실행하는 팀 공유용 1차 데모는 [`docs/NAVIGATOR_DEMO.md`](docs/NAVIGATOR_DEMO.md)를 참고하세요. Xcode에서 `R2D-Navigator-Demo` scheme을 선택하면 됩니다.

## 핵심 원칙

- 화면 전환은 수집기를 재시작하지 않습니다.
- JavaScript 게임 레이어는 네이티브 Navigator와 WebView bridge로 분리합니다.
- 예상 진행도와 서버 확정 진행도를 별도로 표시합니다.
- `DataState`와 `RiskState`는 독립적으로 관리합니다.
- 업로드 큐는 ACK된 청크만 제거합니다.
