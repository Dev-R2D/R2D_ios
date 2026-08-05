# iOS setup

1. 전체 Xcode 16 이상을 설치한다.
2. `R2D.xcodeproj`를 연다.
3. R2D Target의 Signing Team을 선택한다.
4. iOS 17 이상 Simulator 또는 기기를 선택한다.
5. 첫 실행에서 When In Use 위치 권한과 Motion 권한을 확인한다.

현재 CI 환경에는 Command Line Tools만 있어 iOS SDK, Simulator, code signing을 이용한 App Target 빌드는 수행할 수 없다. Swift Package의 macOS 컴파일은 iOS 전용 CoreMotion 구현을 조건부 컴파일하고, iOS Target에서 해당 구현이 포함된다.
