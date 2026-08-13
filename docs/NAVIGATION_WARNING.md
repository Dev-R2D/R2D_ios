# Navigation road warnings

`RoadWarningEngine`은 MapKit 비의존 Core 값 타입이다. 입력은 location/speed/heading, route match, route, immutable RiskLayerSnapshot, clock이다.

경고 거리는 다음과 같다.

```text
clamp(minimumWarningDistance,
      speedMps * warningLookaheadSec,
      maximumWarningDistance)
```

Cell은 confidence, warning RiskState, 거리, route corridor, 현재 heading, route segment heading, map-match confidence를 모두 통과해야 한다. 반대 방향과 평행도로 후보를 제외하고 `cellID + riskState`별 cooldown을 적용한다. CONFIRMED_DAMAGE/RESTRICTED는 high, ROUGH는 caution, SUSPECTED_DAMAGE는 높은 confidence 전까지 informational이다.

표시 우선순위는 위험 경고, Game의 turn 안내, reroute, 장치 오류, Game animation 순이다. 동일 Coordinator state를 Navigator와 Game이 공유하므로 화면 전환으로 warning context가 초기화되지 않는다. 음성·진동은 `IRoadWarningOutput` 확장점에서 구현한다.
