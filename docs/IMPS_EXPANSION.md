# iMPS expansion plan

R2D는 UIKit 기반 iOS 앱과 Flutter/JavaScript WebView 확장을 유지하면서 iMPS 기능을 단계적으로 붙인다.

## Current integration point

- `R2DUIKit/R2DMapViewController`: iNavi Maps SDK 표시, 마커, 정보창, 클러스터링, 좌표계 변환
- `IPlaceSearchRepository`: 검색, 지오코딩, 리버스 지오코딩 포트
- `IMapMatchingRepository`: GPS 좌표를 도로 위치로 보정하는 포트
- `IRouteOptimizationRepository`: 다중 목적지와 제약 조건 기반 최적화 포트
- `IRouteRepository`: 기존 경로 탐색/재탐색 포트

## Geocoding

- Method: `GET`
- Base URL: `https://imaps.inavi.com`
- Path template: `/maps/v3.0/appkeys/{APPKEY}/coordinates`
- Required query: `query`
- Optional query: `coordtype`, `startposition`, `reqcount`, `admcode`, `posX`, `posY`, `addrext`
- Current adapter: `HTTPIMPSGeocodingRepository`

## Reverse geocoding

- Method: `GET`
- Base URL: `https://imaps.inavi.com`
- Path template: `/maps/v3.0/appkeys/{APPKEY}/addresses`
- Required query: `posX`, `posY`
- Optional query: `coordtype`
- Response source: `location.adm`, `location.adm_address`, `location.legal_address`
- Current adapter: `HTTPIMPSGeocodingRepository.reverseGeocode`

## Route search

- Method: `GET`
- Base URL: `https://imaps.inavi.com`
- Path template: `/maps/v3.0/appkeys/{APPKEY}/route-normal`
- Required query: `option`, `startX`, `startY`, `endX`, `endY`
- Optional query: `coordType`, `via1X/via1Y` ... `via5X/via5Y`, `carType`, `groupByTrafficColor`, `useAngle`, `searchByAddress`, `avoidWaterSourceArea`, `avoidNarrowRoad`, `avoidUTurn`, `useTaxifare`
- Supported options: `real_traffic`, `real_traffic2`, `real_traffic_freeroad`, `short_distance_priority`, `time_priority`, `motorcycle`, `recommendation`, `highway_priority`
- Response mapping: `route.data.distance` -> `Route.totalDistance`, `route.data.spend_time` -> `Route.totalDuration`, `route.data.paths[].coords` -> `Route.polyline`
- Current adapter: `HTTPIMPSRouteRepository`

## Special Map Matching

- Method: `POST`
- Base URL: `https://imaps.inavi.com`
- Path template: `/maps/v3.0/appkeys/{APPKEY}/map-match`
- Required body: `userId`, `paths[]`
- Required path item fields: `time`, `x`, `y`, `speed`, `angle`
- Response mapping: `roadMatch.paths[].x/y` -> `MatchedRoadPoint.matched`, `errorDistance` -> `distanceFromOriginalM`, `roadMatch.safeDrivingScore` and event lists are available for later driving-pattern analysis
- Current adapter: `HTTPIMPSMapMatchingRepository`

## Implementation order

1. iNavi 지도 화면 안정화
2. 출발지/목적지 검색과 지오코딩 연결
3. 경로 API 연결
4. Map Matching으로 GPS/센서 이벤트를 도로 구간에 부착
5. 다중 목적지/제약 조건 기반 경로 최적화
6. GeoJSON 또는 3D 도로 모델링 레이어 확장

## TMS MCP note

공유된 TMS MCP 글의 핵심은 API 목록을 사람이 직접 고르기보다, MCP 툴이 엔드포인트 탐색과 디버깅을 돕는 개발 흐름이다. 현재 저장소에는 TMS MCP 서버가 연결되어 있지 않으므로, 실제 연동 전까지는 mock repository로 앱 구조와 테스트를 먼저 고정한다.
