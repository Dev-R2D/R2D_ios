# Risk layer

## Domain policy

- `DataState`: UNKNOWN, STALE, REVIEW, VERIFIED
- `RiskState`: NORMAL, ROUGH, SUSPECTED_DAMAGE, CONFIRMED_DAMAGE, REPAIR_PENDING, RESTRICTED
- UNKNOWN은 정보 부족이며 경고를 만들지 않는다.
- REVIEW는 지도에는 표시할 수 있지만 확정 위험 경고를 만들지 않는다.
- VERIFIED는 정상이라는 뜻이 아니다. `VERIFIED + CONFIRMED_DAMAGE`가 가능하다.
- 클라이언트는 cache가 오래되었다는 이유로 서버 RiskState를 변경하지 않는다.

## Sync and cache

Viewport는 bbox GET, 선택 route와 reroute는 corridor POST를 사용한다. `RiskLayerSyncWorker` actor가 동시 요청을 coalesce하고 Progress version이 달라진 경우에만 다시 조회한다. 304는 현재 snapshot을 유지한다.

Production cache:

```text
Application Support/R2D/RiskLayer/
  latest-route.json
  latest-viewport.json
  metadata.json
```

파일은 atomic write하며 손상 snapshot은 `.corrupt-<UUID>`로 격리한다. Offline/API 오류 시 마지막 성공 snapshot을 사용하며 cache가 없으면 위험 layer를 비워 둔다. UNKNOWN cell을 합성하지 않는다.

Demo Replay snapshot은 `isSimulated=true`로 실제 통계와 구분한다.
