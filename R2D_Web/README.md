# R2D 웹 대시보드

R2D 도로 노면 관제 대시보드에서 사용하는 웹앱 코드, 실측 데이터, 분석 산출물 저장소입니다.

## Prerequisites

- Node.js `>=22.13.0`

## Quick Start

```bash
npm install
npm run dev
npm run build
```

## 디렉터리

- `app/`: R2D 웹 대시보드 화면과 API 라우트
- `app/data/`: 대시보드에서 직접 읽는 주행 JSON 데이터
- `public/`: 지도/이벤트 영상, 이미지, CSV, GeoJSON 정적 파일
- `raw/`: 잠원 및 동탄 주행에서 정리한 GPS·IMU·이벤트 JSON
- `processed/`: 주행별 구간 점수 CSV와 경로 GeoJSON
- `scripts/`: 실측 데이터 가공 및 미디어 추출 스크립트
- `db/`, `drizzle/`: 민원/리포트 저장소 스키마와 마이그레이션
- `.openai/hosting.json`: Sites 배포 설정

## 데이터 해석

- 노면 점수는 동일 주행 내 4초 구간을 비교하기 위한 R2D 프로토타입 지표입니다.
- `영상 확인 후보`와 `센서 단독 후보`는 현장 확인 전 단계이며, 확정 파손 판정이 아닙니다.
- GPS 위치는 스마트폰 측위 오차를 포함하므로 정밀 측량 좌표로 사용하지 않습니다.

## Useful Commands

- `npm run dev`: 로컬 개발 서버 실행
- `npm run build`: vinext 빌드 확인
- `npm test`: 빌드와 렌더링 스모크 테스트 실행
- `npm run db:generate`: Drizzle 마이그레이션 생성

## Workspace Auth Headers

OpenAI workspace sites can read the current user's email from
`oai-authenticated-user-email`.

SIWC-authenticated workspace sites may also receive
`oai-authenticated-user-full-name` when the user's SIWC profile has a non-empty
`name` claim. The full-name value is percent-encoded UTF-8 and is accompanied by
`oai-authenticated-user-full-name-encoding: percent-encoded-utf-8`.

Use `app/chatgpt-auth.ts` for optional or required ChatGPT sign-in helpers.

## Commit convention

Conventional Commits 형식을 사용합니다.

- `feat(data):` 새로운 주행·분석 데이터 추가
- `fix(data):` 좌표, 시간 동기화 또는 잘못된 값 수정
- `docs:` 데이터 설명과 사용법 변경
- `chore:` 분류·파일 구조 등 유지보수 작업
