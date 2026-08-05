# HTTP telemetry adapter

`HTTPClient`는 base URL, transport, 상태 코드 분류를 담당하고 `TelemetryHTTPUploader`가 `/v1/rides/{rideId}/telemetry` 계약을 구성한다. `URLSession`은 Infrastructure 밖으로 노출되지 않는다.

P0 payload는 base64 JSON을 선택했다. 구현과 OpenAPI 검증이 단순하며 이후 `payload_encoding`을 유지한 채 compressed binary 또는 multipart로 전환할 수 있다.

요청에는 `Idempotency-Key`, `X-Client-Event-ID`, `X-Request-ID`가 포함된다. 429와 5xx, offline, timeout만 지수 backoff 대상으로 취급한다. 400, 401, 403과 영구 거부는 무한 재시도하지 않는다. 서버 `duplicate=true`는 성공 ACK다.

`R2DAPIBaseURL`이 비어 있으면 Queue-only uploader가 offline을 반환하며 데이터는 암호화 Queue에 보존된다. 현재 인증, token refresh, 운영 Progress API는 Mock이다. 로그에 payload, 키, 좌표, 인증 값을 남기지 않는다.

## Risk layer adapter

`RiskLayerHTTPRepository`는 `GET /v1/map/cells`, `POST /v1/map/cells/along-route`, `GET /v1/map/cells/{cellId}`를 구성한다. 긴 route coordinate는 query string이 아닌 JSON body로 전송한다. `layer_version`과 HTTP 304를 지원하며 304는 기존 snapshot을 교체하지 않는다.

서버 WKT는 Infrastructure에서 `RoadGeometry`로 변환한다. 잘못된 geometry는 `RiskLayerError.invalidGeometry`이고, 401은 `unauthorized`로 반환해 향후 token refresh가 한 번만 개입할 경계를 남긴다. 429와 5xx도 Risk 전용 오류로 정규화하지만 Risk sync worker는 Ride를 실패시키지 않는다.
