export type SurfaceEvent = {
  atMeters: number;
  segmentRms: number;
  baselineRms: number;
  repeatPasses: number;
};

export type ScorableSurfaceEvent = SurfaceEvent & {
  speedKmh: number;
  mounted: boolean;
};

export const INITIAL_SENSOR_RULES = {
  version: "sensor-logger-initial-v0.1",
  calibrationSeconds: 15,
  analysisWindowSeconds: 4,
  analysisWindowOverlap: 0.5,
  speedReferenceMps: 5,
  speedCorrectionExponent: 1.15,
  highImpactReviewMps2: 8,
  segmentMeters: 8,
  candidateRatio: 1.8,
  cautionRatio: 2.6,
  severeRatio: 3.8,
  minimumRepeatPasses: 2,
  validSpeedKmh: { min: 5, max: 35 },
  distanceDamagePer100m: 14,
  bonusDamage: {
    candidate: 12,
    caution: 26,
    severe: 44,
    repeatMultiplier: 1.35,
  },
} as const;

export function damageForDistance(meters: number) {
  return Math.max(0, Math.round((meters / 100) * INITIAL_SENSOR_RULES.distanceDamagePer100m));
}

export function scoreSurfaceEvent(event: ScorableSurfaceEvent) {
  const speedValid = event.speedKmh >= INITIAL_SENSOR_RULES.validSpeedKmh.min
    && event.speedKmh <= INITIAL_SENSOR_RULES.validSpeedKmh.max;
  const ratio = event.baselineRms > 0 ? event.segmentRms / event.baselineRms : 0;
  const accepted = event.mounted && speedValid && ratio >= INITIAL_SENSOR_RULES.candidateRatio;
  const verified = accepted && event.repeatPasses >= INITIAL_SENSOR_RULES.minimumRepeatPasses;

  let severity: "candidate" | "caution" | "severe" = "candidate";
  let severityLabel = "주의";
  if (ratio >= INITIAL_SENSOR_RULES.severeRatio) {
    severity = "severe";
    severityLabel = "심한 이상";
  } else if (ratio >= INITIAL_SENSOR_RULES.cautionRatio) {
    severity = "caution";
    severityLabel = "노면 이상";
  }

  const baseBonus = INITIAL_SENSOR_RULES.bonusDamage[severity];
  const bonusDamage = accepted
    ? Math.round(baseBonus * (verified ? INITIAL_SENSOR_RULES.bonusDamage.repeatMultiplier : 1))
    : 0;

  return {
    accepted,
    verified,
    ratio,
    severity,
    severityLabel,
    bonusDamage,
    reason: !event.mounted
      ? "phone-not-mounted"
      : !speedValid
        ? "speed-out-of-range"
        : ratio < INITIAL_SENSOR_RULES.candidateRatio
          ? "below-candidate-threshold"
          : verified
            ? "repeat-confirmed"
            : "candidate-only",
  } as const;
}
