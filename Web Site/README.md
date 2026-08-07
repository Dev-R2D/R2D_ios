# R2D Web Site

[▶ 배포된 R2D 게임 웹사이트 열기](https://roadpulse-go-sensor-mvp.rudfhr020205.chatgpt.site/)

이 폴더는 R2D 게임 웹사이트를 저장소의 다른 자료와 구분해 관리하기 위한 독립 실행형 웹 프로젝트입니다.

## 포함된 기능

- 자전거 주행 기반 도로 탐사 게임
- 거치 캘리브레이션과 안전 주행 화면
- AI 분석, 오탐 제외, 데미지 정산
- 탐사 팩, 카드 도감, 지역 리그, 마일리지 상점
- 손상 후보 교차검증 및 보수 완료 알림 시연

## 로컬 실행

Node.js 22.13 이상과 pnpm을 준비한 뒤 이 폴더에서 실행합니다.

```bash
pnpm install
pnpm dev
```

브라우저에서 터미널에 표시된 주소를 엽니다.

## 검증

```bash
pnpm build
pnpm exec node --test tests/rendered-html.test.mjs
```

## 배포 정보

- 공개 사이트: https://roadpulse-go-sensor-mvp.rudfhr020205.chatgpt.site/
- 호스팅 설정: `.openai/hosting.json`
- 웹 화면: `app/page.tsx`
- 스타일: `app/globals.css`
- 센서 판정: `app/sensor-rules.ts`
- 게임 규칙: `app/game-rules.ts`

> 실제 API 키, 위치 원본 데이터, 개인정보와 인증 비밀값은 이 폴더에 커밋하지 않습니다.
