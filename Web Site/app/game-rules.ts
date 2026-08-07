export enum CellStatus {
  UNSCANNED = "UNSCANNED",
  FRESH = "FRESH",
  NEEDS_REFRESH = "NEEDS_REFRESH",
  DAMAGED = "DAMAGED",
}

export type RoadCell = {
  id: string;
  status: CellStatus;
};

export type CellEvent = "SCAN_GOOD" | "AGE_OUT" | "DAMAGE_CONFIRMED" | "REPAIR_CONFIRMED";

export type RepairEvidence = {
  maxTrajectoryDeviationM: number;
  noImpactRiderCount: number;
};

export const GAMEPLAY_RULES = {
  minionPassRadiusM: 12,
  crossValidationRadiusM: 10,
  minimumCrossValidationRiders: 3,
  repairMaxTrajectoryDeviationM: 5,
  repairMinimumNoImpactRiders: 3,
  unscannedCellHp: 500,
  refreshCellHp: 300,
  activeRiderReference: 50,
  minimumPopulationScale: 0.25,
  maximumPopulationScale: 1.5,
  cadenceBandHz: { min: 1, max: 2 },
  cadenceMinimumBandEnergyRatio: 0.18,
} as const;

const makeCells = (prefix: string, status: CellStatus, count: number) =>
  Array.from({ length: count }, (_, index) => ({ id: `${prefix}-${index + 1}`, status }));

// road-pulse-web의 셀 배열과 동일한 입력 형태를 쓰는 데모 스냅샷입니다.
// 운영에서는 이 배열만 실제 행정동 셀 응답으로 교체합니다.
export const DEMO_REGION_CELLS: RoadCell[] = [
  ...makeCells("DT2-U", CellStatus.UNSCANNED, 96),
  ...makeCells("DT2-F", CellStatus.FRESH, 224),
  ...makeCells("DT2-R", CellStatus.NEEDS_REFRESH, 37),
  ...makeCells("DT2-D", CellStatus.DAMAGED, 9),
];

export function calculateRegionalBossHealth(cells: RoadCell[], activeRiders: number) {
  const unscannedCells = cells.filter((cell) => cell.status === CellStatus.UNSCANNED).length;
  const refreshCells = cells.filter((cell) => cell.status === CellStatus.NEEDS_REFRESH).length;
  const rawHealth = unscannedCells * GAMEPLAY_RULES.unscannedCellHp
    + refreshCells * GAMEPLAY_RULES.refreshCellHp;
  const populationScale = Math.min(
    GAMEPLAY_RULES.maximumPopulationScale,
    Math.max(GAMEPLAY_RULES.minimumPopulationScale, activeRiders / GAMEPLAY_RULES.activeRiderReference),
  );

  return {
    unscannedCells,
    refreshCells,
    rawHealth,
    populationScale,
    totalHealth: Math.max(1, Math.round(rawHealth * populationScale)),
  };
}

export function evaluateMinionPass(input: {
  distanceToMinionM: number;
  photoVerified: boolean;
  spikeDetected: boolean;
  missionActive: boolean;
}) {
  const adjacentPass = input.distanceToMinionM <= GAMEPLAY_RULES.minionPassRadiusM;
  const cleared = adjacentPass && input.photoVerified;
  const useForVerification = input.spikeDetected;
  const rewardMileage = input.spikeDetected && input.missionActive ? 60 : 0;

  return {
    adjacentPass,
    cleared,
    useForVerification,
    rewardMileage,
    rewardReason: input.spikeDetected && !input.missionActive
      ? "incidental-spike-no-reward"
      : input.spikeDetected
        ? "mission-spike-rewarded"
        : "no-spike",
  } as const;
}

export const DEMO_VALIDATION_RIDERS = [
  { riderId: "RIDER-031", offsetMeters: 2.4, spikeDetected: true, photoVerified: true },
  { riderId: "RIDER-044", offsetMeters: 4.1, spikeDetected: true, photoVerified: false },
  { riderId: "RIDER-058", offsetMeters: 6.8, spikeDetected: true, photoVerified: true },
] as const;

export function crossValidateRiderLogs(
  logs: ReadonlyArray<{ offsetMeters: number; spikeDetected: boolean }>,
) {
  const matchingRiders = logs.filter(
    (log) => log.spikeDetected && log.offsetMeters <= GAMEPLAY_RULES.crossValidationRadiusM,
  ).length;

  return {
    matchingRiders,
    verified: matchingRiders >= GAMEPLAY_RULES.minimumCrossValidationRiders,
  };
}

export function isRepairConfirmed(evidence: RepairEvidence) {
  return evidence.maxTrajectoryDeviationM <= GAMEPLAY_RULES.repairMaxTrajectoryDeviationM
    && evidence.noImpactRiderCount >= GAMEPLAY_RULES.repairMinimumNoImpactRiders;
}

export function transitionCellStatus(
  current: CellStatus,
  event: CellEvent,
  repairEvidence?: RepairEvidence,
) {
  if (event === "SCAN_GOOD" && (current === CellStatus.UNSCANNED || current === CellStatus.NEEDS_REFRESH)) {
    return CellStatus.FRESH;
  }
  if (event === "AGE_OUT" && current === CellStatus.FRESH) return CellStatus.NEEDS_REFRESH;
  if (event === "DAMAGE_CONFIRMED") return CellStatus.DAMAGED;
  if (
    event === "REPAIR_CONFIRMED"
    && current === CellStatus.DAMAGED
    && repairEvidence
    && isRepairConfirmed(repairEvidence)
  ) {
    return CellStatus.FRESH;
  }
  return current;
}

export function detectCyclingCadence(acceleration: number[], sampleRateHz = 100) {
  if (acceleration.length < sampleRateHz * 2) {
    return { isCycling: false, peakHz: 0, cadenceRpm: 0, bandEnergyRatio: 0 };
  }

  const mean = acceleration.reduce((sum, value) => sum + value, 0) / acceleration.length;
  const windowed = acceleration.map((value, index) => {
    const hann = 0.5 - 0.5 * Math.cos((2 * Math.PI * index) / (acceleration.length - 1));
    return (value - mean) * hann;
  });
  const powerAt = (bin: number) => {
    let real = 0;
    let imaginary = 0;
    for (let index = 0; index < windowed.length; index += 1) {
      const angle = (2 * Math.PI * bin * index) / windowed.length;
      real += windowed[index] * Math.cos(angle);
      imaginary -= windowed[index] * Math.sin(angle);
    }
    return real * real + imaginary * imaginary;
  };

  const firstBin = Math.max(1, Math.ceil((GAMEPLAY_RULES.cadenceBandHz.min * windowed.length) / sampleRateHz));
  const lastBin = Math.floor((GAMEPLAY_RULES.cadenceBandHz.max * windowed.length) / sampleRateHz);
  const nyquistBin = Math.floor(windowed.length / 2);
  let peakBin = firstBin;
  let peakPower = 0;
  let bandPower = 0;
  let totalPower = 0;

  for (let bin = 1; bin <= nyquistBin; bin += 1) {
    const power = powerAt(bin);
    totalPower += power;
    if (bin >= firstBin && bin <= lastBin) {
      bandPower += power;
      if (power > peakPower) {
        peakPower = power;
        peakBin = bin;
      }
    }
  }

  const peakHz = (peakBin * sampleRateHz) / windowed.length;
  const bandEnergyRatio = totalPower > 0 ? bandPower / totalPower : 0;
  return {
    isCycling: bandEnergyRatio >= GAMEPLAY_RULES.cadenceMinimumBandEnergyRatio,
    peakHz,
    cadenceRpm: Math.round(peakHz * 60),
    bandEnergyRatio,
  };
}

export function settleRideRewards(input: { xp: number; bossDamage: number; cashMileage: number }) {
  return {
    immediate: { xp: input.xp, bossDamage: input.bossDamage },
    pending: { cashMileage: input.cashMileage, available: "D+1" as const },
  };
}

export const REGION_CACHE_KEY = "r2d:last-region-response";

export function cacheLastRegionResponse(value: unknown) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(REGION_CACHE_KEY, JSON.stringify(value));
  } catch {
    // Storage can be unavailable in private browsing; the game remains usable without it.
  }
}
