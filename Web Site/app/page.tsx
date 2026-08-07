"use client";

import { useEffect, useRef, useState } from "react";
import { INITIAL_SENSOR_RULES } from "./sensor-rules";
import {
  cacheLastRegionResponse,
  calculateRegionalBossHealth,
  crossValidateRiderLogs,
  DEMO_REGION_CELLS,
  DEMO_VALIDATION_RIDERS,
  detectCyclingCadence,
  evaluateMinionPass,
  isRepairConfirmed,
  settleRideRewards,
} from "./game-rules";

type Screen =
  | "splash"
  | "intro"
  | "permissions"
  | "persuade"
  | "calibration"
  | "starter"
  | "home"
  | "deck"
  | "ride"
  | "analysis"
  | "damage"
  | "pack"
  | "summary"
  | "collection"
  | "ranking"
  | "shop"
  | "repair";

type Tab = "home" | "collection" | "ranking" | "shop";

type CardData = {
  name: string;
  type: string;
  grade: "BRONZE" | "SILVER" | "GOLD" | "SIGNATURE";
  damage: string;
  mileage: string;
  effect: string;
  glyph: string;
};

const INTRO = [
  {
    eyebrow: "01 · THE UNSEEN CITY",
    title: "당신의 도시는\n아직 스캔되지 않았습니다",
    body: "익숙한 도로 위에도 아직 기록되지 않은 위험이 남아 있습니다.",
    art: "fog",
  },
  {
    eyebrow: "02 · RIDE TO REVEAL",
    title: "달린 만큼\n지도가 열립니다",
    body: "자전거가 지나간 궤적은 도시를 밝히고 오래된 데이터를 다시 깨웁니다.",
    art: "reveal",
  },
  {
    eyebrow: "03 · FIND WHAT HIDES",
    title: "그리고 도로에 숨은\n것들이 보입니다",
    body: "라이더의 기록이 쌓이면 의심 지점은 검증되고 도시의 몹으로 드러납니다.",
    art: "monster",
  },
] as const;

const DECK_CARDS: CardData[] = [
  { name: "라인 브레이커", type: "SPRINTER", grade: "GOLD", damage: "×1.15", mileage: "×1.00", effect: "신규 구간 DMG +18%", glyph: "↗" },
  { name: "나이트 폭스", type: "SCOUT", grade: "SILVER", damage: "×1.05", mileage: "×1.10", effect: "야간 주행 +15%", glyph: "◒" },
  { name: "리페어 비트", type: "SUPPORT", grade: "BRONZE", damage: "×1.00", mileage: "×1.18", effect: "노후 구간 마일리지 +20%", glyph: "✦" },
  { name: "크랙 헌터", type: "TRACKER", grade: "BRONZE", damage: "×1.08", mileage: "×1.00", effect: "충격 후보 발견 +12%", glyph: "⌁" },
  { name: "리버 러너", type: "ROUTER", grade: "BRONZE", damage: "×1.03", mileage: "×1.08", effect: "하천 구간 거리 +10%", glyph: "≈" },
];

const STARTER_CARDS = DECK_CARDS.slice(2);

const GOLD_PACK: CardData[] = [
  { name: "골든 페달", type: "SPRINTER", grade: "GOLD", damage: "×1.22", mileage: "×1.00", effect: "신규 구간 크리티컬 +25%", glyph: "↟" },
  { name: "실버 에코", type: "TRACKER", grade: "SILVER", damage: "×1.08", mileage: "×1.12", effect: "재탐사 구간 +18%", glyph: "◉" },
  { name: "로드 핀", type: "SCOUT", grade: "BRONZE", damage: "×1.04", mileage: "×1.06", effect: "손상 후보 기록 +8%", glyph: "⌖" },
];

const formatTime = (seconds: number) =>
  `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;

const ACTIVE_REGION_RIDERS = 12;
const BOSS_HEALTH = calculateRegionalBossHealth(DEMO_REGION_CELLS, ACTIVE_REGION_RIDERS);
const BOSS_REMAINING_HEALTH = Math.round(BOSS_HEALTH.totalHealth * 0.68);
const MINION_DEMO = evaluateMinionPass({
  distanceToMinionM: 6.4,
  photoVerified: true,
  spikeDetected: true,
  missionActive: false,
});
const CROSS_VALIDATION = crossValidateRiderLogs(DEMO_VALIDATION_RIDERS);
const REPAIR_DEMO = { maxTrajectoryDeviationM: 3.2, noImpactRiderCount: 4 };
const REWARDS = settleRideRewards({ xp: 320, bossDamage: 3059, cashMileage: 480 });
const DEMO_CADENCE_SIGNAL = Array.from({ length: 400 }, (_, index) => {
  const time = index / 100;
  return Math.sin(2 * Math.PI * 1.5 * time) + 0.16 * Math.sin(2 * Math.PI * 6.5 * time);
});
const CADENCE_DEMO = detectCyclingCadence(DEMO_CADENCE_SIGNAL, 100);

export default function Home() {
  const [screen, setScreen] = useState<Screen>("splash");
  const [introIndex, setIntroIndex] = useState(0);
  const [skipVisible, setSkipVisible] = useState(false);
  const [permissionStep, setPermissionStep] = useState<"location" | "activity">("location");
  const [calibrating, setCalibrating] = useState(false);
  const [calibrationCount, setCalibrationCount] = useState(3);
  const [starterOpened, setStarterOpened] = useState(false);
  const [bossOpen, setBossOpen] = useState(false);
  const [minionOpen, setMinionOpen] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [rideDistance, setRideDistance] = useState(0);
  const [rideSeconds, setRideSeconds] = useState(0);
  const [endConfirm, setEndConfirm] = useState(false);
  const [holdProgress, setHoldProgress] = useState(0);
  const [damageReady, setDamageReady] = useState(false);
  const [packIndex, setPackIndex] = useState(0);
  const [packRevealed, setPackRevealed] = useState(false);
  const [cardDrag, setCardDrag] = useState(0);
  const [shareOpen, setShareOpen] = useState(false);
  const [toast, setToast] = useState("");
  const [offline, setOffline] = useState(false);

  const pointerStart = useRef<number | null>(null);
  const holdInterval = useRef<number | null>(null);
  const audioContext = useRef<AudioContext | null>(null);
  const toneStage = useRef(0);

  function playTone(frequency: number, duration: number) {
    try {
      const AudioCtor = window.AudioContext
        ?? (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AudioCtor) return;
      const context = audioContext.current ?? new AudioCtor();
      audioContext.current = context;
      void context.resume();
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      oscillator.frequency.value = frequency;
      oscillator.type = "sine";
      gain.gain.setValueAtTime(0.0001, context.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.12, context.currentTime + 0.015);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + duration);
      oscillator.connect(gain).connect(context.destination);
      oscillator.start();
      oscillator.stop(context.currentTime + duration + 0.02);
    } catch {
      // Audio is a progressive enhancement; the ride stays safe and usable without it.
    }
  }

  useEffect(() => {
    const syncNetworkState = () => setOffline(!window.navigator.onLine);
    cacheLastRegionResponse({
      region: "동탄2동",
      totalHealth: BOSS_HEALTH.totalHealth,
      remainingHealth: BOSS_REMAINING_HEALTH,
      activeRiders: ACTIVE_REGION_RIDERS,
      cachedAt: new Date().toISOString(),
    });
    syncNetworkState();
    window.addEventListener("online", syncNetworkState);
    window.addEventListener("offline", syncNetworkState);
    return () => {
      window.removeEventListener("online", syncNetworkState);
      window.removeEventListener("offline", syncNetworkState);
    };
  }, []);

  useEffect(() => {
    if (screen !== "intro") return;
    const timer = window.setTimeout(() => setSkipVisible(true), 3000);
    return () => window.clearTimeout(timer);
  }, [screen]);

  useEffect(() => {
    if (!calibrating) return;
    if (calibrationCount <= 0) {
      const done = window.setTimeout(() => setScreen("starter"), 700);
      return () => window.clearTimeout(done);
    }
    const timer = window.setTimeout(() => setCalibrationCount((count) => count - 1), 1000);
    return () => window.clearTimeout(timer);
  }, [calibrating, calibrationCount]);

  useEffect(() => {
    if (screen !== "ride") return;
    const timer = window.setInterval(() => {
      setRideSeconds((value) => value + 1);
      setRideDistance((value) => {
        const next = Math.min(3.2, value + 0.16);
        if (toneStage.current === 0 && next >= 0.64) {
          toneStage.current = 1;
          playTone(740, 0.12);
        } else if (toneStage.current === 1 && next >= 1.76) {
          toneStage.current = 2;
          playTone(430, 0.18);
        } else if (toneStage.current === 2 && next >= 2.55) {
          toneStage.current = 3;
          playTone(880, 0.1);
        }
        return next;
      });
    }, 1000);
    return () => window.clearInterval(timer);
  }, [screen]);

  useEffect(() => {
    if (screen !== "analysis") return;
    const timer = window.setTimeout(() => {
      setDamageReady(false);
      setScreen("damage");
    }, 5200);
    return () => window.clearTimeout(timer);
  }, [screen]);

  useEffect(() => {
    if (screen !== "damage") return;
    const timer = window.setTimeout(() => setDamageReady(true), 4300);
    return () => window.clearTimeout(timer);
  }, [screen]);

  useEffect(() => {
    return () => {
      if (holdInterval.current !== null) window.clearInterval(holdInterval.current);
      audioContext.current?.close();
    };
  }, []);

  const enterIntro = () => {
    setIntroIndex(0);
    setSkipVisible(false);
    setScreen("intro");
  };

  const advanceIntro = () => {
    if (introIndex < INTRO.length - 1) setIntroIndex((value) => value + 1);
    else setScreen("permissions");
  };

  const onIntroPointerDown = (event: React.PointerEvent) => {
    pointerStart.current = event.clientX;
  };

  const onIntroPointerUp = (event: React.PointerEvent) => {
    if (pointerStart.current === null) return;
    const delta = event.clientX - pointerStart.current;
    pointerStart.current = null;
    if (delta < -45) advanceIntro();
    if (delta > 45 && introIndex > 0) setIntroIndex((value) => value - 1);
  };

  const grantPermission = () => {
    if (permissionStep === "location") setPermissionStep("activity");
    else setScreen("calibration");
  };

  const beginCalibration = () => {
    setCalibrationCount(3);
    setCalibrating(true);
  };

  const enterHome = () => {
    setScreen("home");
    setStarterOpened(false);
  };

  const startRide = () => {
    setBossOpen(false);
    setRideDistance(0);
    setRideSeconds(0);
    setHoldProgress(0);
    setEndConfirm(false);
    toneStage.current = 0;
    playTone(540, 0.08);
    setScreen("ride");
  };

  const beginHold = () => {
    if (endConfirm) return;
    setHoldProgress(0);
    if (holdInterval.current !== null) window.clearInterval(holdInterval.current);
    holdInterval.current = window.setInterval(() => {
      setHoldProgress((progress) => {
        const next = Math.min(100, progress + 4);
        if (next >= 100) {
          if (holdInterval.current !== null) window.clearInterval(holdInterval.current);
          holdInterval.current = null;
          setEndConfirm(true);
          return 100;
        }
        return next;
      });
    }, 45);
  };

  const cancelHold = () => {
    if (holdInterval.current !== null) window.clearInterval(holdInterval.current);
    holdInterval.current = null;
    if (!endConfirm) setHoldProgress(0);
  };

  const finishRide = () => {
    cancelHold();
    setEndConfirm(false);
    setRideDistance(3.2);
    setScreen("analysis");
  };

  const openPack = () => {
    setPackIndex(0);
    setPackRevealed(false);
    setCardDrag(0);
    setScreen("pack");
  };

  const onCardDown = (event: React.PointerEvent) => {
    pointerStart.current = event.clientX;
    event.currentTarget.setPointerCapture?.(event.pointerId);
  };

  const onCardMove = (event: React.PointerEvent) => {
    if (pointerStart.current === null) return;
    setCardDrag(Math.max(-110, Math.min(110, event.clientX - pointerStart.current)));
  };

  const onCardUp = () => {
    const swiped = Math.abs(cardDrag) > 48;
    pointerStart.current = null;
    setCardDrag(0);
    if (!swiped) return;
    if (!packRevealed) {
      setPackRevealed(true);
      playTone(GOLD_PACK[packIndex].grade === "GOLD" ? 920 : 690, 0.18);
    } else if (packIndex < GOLD_PACK.length - 1) {
      setPackIndex((index) => index + 1);
      setPackRevealed(false);
    } else {
      setScreen("summary");
    }
  };

  const showToast = (message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 1800);
  };

  const shareResult = async () => {
    const shareData = {
      title: "R2D · 오늘의 도시 복구",
      text: "오늘 3.2km를 새로 열고 동네 복구율을 41%에서 43%로 높였어요.",
      url: window.location.href,
    };
    if (navigator.share) {
      try {
        await navigator.share(shareData);
        return;
      } catch {
        return;
      }
    }
    setShareOpen(true);
  };

  const goTab = (tab: Tab) => {
    setScreen(tab);
    setBossOpen(false);
  };

  return (
    <main className="r2d-shell">
      <section className={`r2d-app screen-${screen}`} aria-label="R2D 게임 프로토타입">
        {screen === "splash" && <SplashScreen onLogin={enterIntro} />}
        {screen === "intro" && (
          <IntroScreen
            index={introIndex}
            skipVisible={skipVisible}
            onNext={advanceIntro}
            onSkip={() => setScreen("permissions")}
            onPointerDown={onIntroPointerDown}
            onPointerUp={onIntroPointerUp}
          />
        )}
        {screen === "permissions" && (
          <PermissionScreen
            step={permissionStep}
            onAllow={grantPermission}
            onDeny={() => permissionStep === "location" ? setScreen("persuade") : grantPermission()}
          />
        )}
        {screen === "persuade" && <PersuadeScreen onRetry={() => setScreen("permissions")} />}
        {screen === "calibration" && (
          <CalibrationScreen running={calibrating} count={calibrationCount} onStart={beginCalibration} />
        )}
        {screen === "starter" && (
          <StarterPackScreen opened={starterOpened} onOpen={() => setStarterOpened(true)} onDone={enterHome} />
        )}
        {screen === "home" && (
          <HomeScreen
            onBoss={() => setBossOpen(true)}
            onMinion={() => setMinionOpen(true)}
            onDeck={() => setScreen("deck")}
            onStart={startRide}
            onNotifications={() => setNotificationsOpen(true)}
            onProfile={() => setProfileOpen(true)}
            onTab={goTab}
            offline={offline}
          />
        )}
        {screen === "deck" && <DeckScreen onBack={() => setScreen("home")} onStart={startRide} />}
        {screen === "ride" && (
          <RideScreen
            distance={rideDistance}
            seconds={rideSeconds}
            holdProgress={holdProgress}
            confirmOpen={endConfirm}
            onHoldStart={beginHold}
            onHoldEnd={cancelHold}
            onCancel={() => { setEndConfirm(false); setHoldProgress(0); }}
            onConfirm={finishRide}
          />
        )}
        {screen === "analysis" && <AnalysisScreen />}
        {screen === "damage" && <DamageScreen ready={damageReady} onNext={openPack} />}
        {screen === "pack" && (
          <GoldPackScreen
            index={packIndex}
            revealed={packRevealed}
            drag={cardDrag}
            onPointerDown={onCardDown}
            onPointerMove={onCardMove}
            onPointerUp={onCardUp}
          />
        )}
        {screen === "summary" && (
          <SummaryScreen onShare={shareResult} onHome={() => setScreen("home")} onRepair={() => setScreen("repair")} />
        )}
        {screen === "collection" && <CollectionScreen onTab={goTab} />}
        {screen === "ranking" && <RankingScreen onTab={goTab} />}
        {screen === "shop" && <ShopScreen onTab={goTab} onExchange={() => showToast("쿠폰 교환을 예약했습니다")} />}
        {screen === "repair" && <RepairScreen onDone={() => setScreen("home")} />}

        {bossOpen && <BossSheet onClose={() => setBossOpen(false)} onDeck={() => { setBossOpen(false); setScreen("deck"); }} onStart={startRide} />}
        {minionOpen && <MinionSheet onClose={() => setMinionOpen(false)} />}
        {notificationsOpen && (
          <NotificationSheet
            onClose={() => setNotificationsOpen(false)}
            onRepair={() => { setNotificationsOpen(false); setScreen("repair"); }}
          />
        )}
        {profileOpen && (
          <ProfileSheet
            onClose={() => setProfileOpen(false)}
            onReplay={() => { setProfileOpen(false); enterIntro(); }}
          />
        )}
        {shareOpen && <ShareSheet onClose={() => setShareOpen(false)} />}
        {toast && <div className="toast" role="status">{toast}</div>}
      </section>
    </main>
  );
}

function SplashScreen({ onLogin }: { onLogin: () => void }) {
  return (
    <section className="full-screen splash-screen">
      <div className="city-silhouette"><i /><i /><i /><i /><i /><i /></div>
      <div className="splash-route"><span className="moving-bike">●</span></div>
      <div className="splash-brand">
        <div className="r2d-logo" aria-label="R2D"><span>R</span><span>2</span><span>D</span></div>
        <p>ROAD TO DATA</p>
      </div>
      <div className="splash-copy">
        <span>도시를 달리고</span>
        <strong>보이지 않던 길을 깨우세요</strong>
      </div>
      <button className="google-button" onClick={onLogin}>
        <span className="google-g">G</span>
        Google로 계속하기
      </button>
      <small className="prototype-label">JURY DEMO · GOOGLE LOGIN PROTOTYPE</small>
    </section>
  );
}

function IntroScreen({
  index,
  skipVisible,
  onNext,
  onSkip,
  onPointerDown,
  onPointerUp,
}: {
  index: number;
  skipVisible: boolean;
  onNext: () => void;
  onSkip: () => void;
  onPointerDown: (event: React.PointerEvent) => void;
  onPointerUp: (event: React.PointerEvent) => void;
}) {
  const slide = INTRO[index];
  return (
    <section className="full-screen intro-screen" onPointerDown={onPointerDown} onPointerUp={onPointerUp}>
      <button className={`skip-button ${skipVisible ? "visible" : ""}`} onClick={onSkip}>건너뛰기</button>
      <div className={`intro-art art-${slide.art}`}>
        <div className="intro-grid" />
        <div className="fog-cloud fog-a" /><div className="fog-cloud fog-b" /><div className="fog-cloud fog-c" />
        <div className="intro-road road-a" /><div className="intro-road road-b" /><div className="intro-road road-c" />
        <div className="intro-trail"><span className="trail-bike">●</span></div>
        <div className="intro-monster"><span className="monster-eye left" /><span className="monster-eye right" /></div>
        <div className="scan-caption">SCAN {String(index + 1).padStart(2, "0")}</div>
      </div>
      <div className="intro-content">
        <span className="eyebrow">{slide.eyebrow}</span>
        <h1>{slide.title.split("\n").map((line) => <span key={line}>{line}</span>)}</h1>
        <p>{slide.body}</p>
        <div className="intro-controls">
          <div className="dots">{INTRO.map((_, dot) => <i className={dot === index ? "active" : ""} key={dot} />)}</div>
          <button className="round-next" onClick={onNext} aria-label="다음">{index === INTRO.length - 1 ? "시작" : "→"}</button>
        </div>
        <small className="swipe-hint">좌우로 밀어 도시의 변화를 확인하세요</small>
      </div>
    </section>
  );
}

function PermissionScreen({
  step,
  onAllow,
  onDeny,
}: {
  step: "location" | "activity";
  onAllow: () => void;
  onDeny: () => void;
}) {
  const location = step === "location";
  return (
    <section className="full-screen permission-screen">
      <OnboardingHeader step={location ? 1 : 2} total={3} label="권한 설정" />
      <div className={`permission-orbit ${location ? "location" : "activity"}`}>
        <span className="orbit-center">{location ? "⌖" : "↟"}</span><i /><i /><i />
      </div>
      <span className="eyebrow">{location ? "BACKGROUND LOCATION" : "PHYSICAL ACTIVITY"}</span>
      <h1>{location ? "위치 접근을\n허용해 주세요" : "신체활동 접근을\n허용해 주세요"}</h1>
      <p>{location
        ? "화면을 꺼도 주행 궤적과 미탐사 구간을 정확히 기록하는 데 필요합니다."
        : "자전거 주행과 단순 이동을 구분해 데이터 품질을 지키는 데 필요합니다."}</p>
      <div className="permission-detail">
        <span>{location ? "항상 허용" : "활동 데이터"}</span>
        <b>{location ? "백그라운드에서도 경로 기록" : "주행 여부와 움직임 판별"}</b>
      </div>
      <button className="primary-button" onClick={onAllow}>{location ? "위치 항상 허용" : "신체활동 허용"}</button>
      <button className="text-button" onClick={onDeny}>{location ? "거부 상황 시연" : "지금은 허용하지 않기"}</button>
      <small className="privacy-copy">R2D는 주행 분석에 필요한 최소 정보만 사용합니다.</small>
    </section>
  );
}

function PersuadeScreen({ onRetry }: { onRetry: () => void }) {
  return (
    <section className="full-screen permission-screen persuade-screen">
      <OnboardingHeader step={1} total={3} label="한 번만 더 확인" />
      <div className="phone-sleep-art"><span className="sleep-screen" /><i className="route-behind" /><b>기록 중</b></div>
      <span className="eyebrow">WHY “ALWAYS”?</span>
      <h1>화면을 꺼도 기록되려면<br />‘항상 허용’이 필요합니다</h1>
      <p>주행 중 화면을 보는 위험 없이, 휴대폰을 주머니에 넣거나 화면을 꺼도 데이터가 이어집니다.</p>
      <ul className="reason-list">
        <li><span>01</span><b>주행 중 화면을 보지 않아도 됩니다</b></li>
        <li><span>02</span><b>잠금 화면에서도 경로가 끊기지 않습니다</b></li>
      </ul>
      <button className="primary-button" onClick={onRetry}>설정에서 다시 허용하기</button>
      <button className="text-button" onClick={onRetry}>제한된 기능으로 계속</button>
    </section>
  );
}

function CalibrationScreen({ running, count, onStart }: { running: boolean; count: number; onStart: () => void }) {
  const stable = !running || count <= 1;
  return (
    <section className="full-screen calibration-screen">
      <OnboardingHeader step={3} total={3} label="거치 캘리브레이션" />
      <div className={`level-ui ${stable ? "stable" : ""}`}>
        <div className="level-cross horizontal" /><div className="level-cross vertical" />
        <span className="level-bubble"><i /></span>
        <b>{running ? (count > 0 ? count : "✓") : "0.0°"}</b>
      </div>
      <span className="eyebrow">MOUNT CALIBRATION · REQUIRED</span>
      <h1>{running ? (count > 0 ? "자전거를 움직이지 마세요" : "기준축을 잡았습니다") : "휴대폰을 거치하고\n자전거를 세워 주세요"}</h1>
      <p>{running
        ? "중력 방향을 기준으로 기기와 거치대의 각도를 계산하고 있습니다."
        : "기기마다 다른 거치 각도를 보정해야 노면 충격의 수직 성분을 비교할 수 있습니다."}</p>
      {!running && <button className="primary-button" onClick={onStart}>3초 캘리브레이션 시작</button>}
      {running && <div className="calibration-progress"><span style={{ width: `${((3 - Math.max(count, 0)) / 3) * 100}%` }} /></div>}
      <small className="no-skip">데이터 품질을 위해 이 단계는 건너뛸 수 없습니다</small>
    </section>
  );
}

function StarterPackScreen({ opened, onOpen, onDone }: { opened: boolean; onOpen: () => void; onDone: () => void }) {
  return (
    <section className={`full-screen starter-screen ${opened ? "opened" : ""}`}>
      <div className="pack-rays" />
      <span className="eyebrow">WELCOME PACK · BRONZE</span>
      <h1>{opened ? "첫 덱이 준비됐습니다" : "첫 탐사 팩을 열어보세요"}</h1>
      <p>{opened ? "세 장은 자동으로 스타터 덱에 편성됩니다." : "팩을 여는 방법을 먼저 익혀볼게요. 결과는 브론즈 3장으로 고정됩니다."}</p>
      {!opened ? (
        <button className="starter-pack" onClick={onOpen} aria-label="스타터 팩 열기">
          <span className="pack-seal">R2D</span><b>STARTER</b><small>위로 밀어 개봉</small>
        </button>
      ) : (
        <div className="starter-card-fan">
          {STARTER_CARDS.map((card, index) => <MiniCard card={card} key={card.name} style={{ "--fan": index - 1 } as React.CSSProperties} />)}
        </div>
      )}
      <div className="pack-swipe-line"><span /></div>
      <button className={`primary-button ${opened ? "visible" : "hidden"}`} onClick={onDone}>R2D 시작하기</button>
    </section>
  );
}

function HomeScreen({
  onBoss,
  onMinion,
  onDeck,
  onStart,
  onNotifications,
  onProfile,
  onTab,
  offline,
}: {
  onBoss: () => void;
  onMinion: () => void;
  onDeck: () => void;
  onStart: () => void;
  onNotifications: () => void;
  onProfile: () => void;
  onTab: (tab: Tab) => void;
  offline: boolean;
}) {
  return (
    <section className="full-screen home-screen">
      <MapScene onBoss={onBoss} onMinion={onMinion} />
      <header className="map-header">
        <button className="profile-button" onClick={onProfile}><span>R</span><div><small>RIDER 019</small><b>동탄2동</b></div></button>
        <button className="bell-button" onClick={onNotifications} aria-label="알림"><span>2</span>♢</button>
      </header>
      <div className="boss-status">
        <div><span>REGION BOSS · 동탄2동</span><b>애스팔트 와이번</b></div>
        <strong>68%</strong>
        <div className="boss-bar"><span style={{ width: "68%" }} /></div>
      </div>
      {offline && <div className="offline-fallback" role="status"><i />오프라인 · 마지막 지역 응답 표시</div>}
      <div className="coverage-legend"><span><i className="new" />신규</span><span><i className="fresh" />탐사</span><span><i className="stale" />노후</span></div>
      <div className="home-cta-panel">
        <div className="recovery-copy"><span>우리 동네 복구율</span><b>41<small>%</small></b><i>이번 주 +3%</i></div>
        <button className="ride-cta" onClick={onStart}><span className="ride-cta-icon">↟</span><div><small>거리만큼 자동 공격</small><b>주행 시작</b></div><i>→</i></button>
      </div>
      <GameNav active="home" onTab={onTab} onDeck={onDeck} />
    </section>
  );
}

function MapScene({ onBoss, onMinion, compact = false }: { onBoss?: () => void; onMinion?: () => void; compact?: boolean }) {
  return (
    <div className={`game-map ${compact ? "compact" : ""}`}>
      <div className="map-grid" />
      <div className="map-river" />
      {Array.from({ length: 10 }).map((_, index) => <i className={`base-road road-${index + 1}`} key={index} />)}
      <i className="coverage-line cov-1" /><i className="coverage-line cov-2" /><i className="coverage-line cov-3" /><i className="coverage-line cov-4 stale" />
      <div className="fog-zone fog-1" /><div className="fog-zone fog-2" /><div className="fog-zone fog-3" />
      <span className="map-label label-a">동탄호수공원</span><span className="map-label label-b">신리천</span><span className="map-label label-c">동탄2동</span>
      <button className="map-boss" onClick={onBoss} aria-label="애스팔트 와이번 보스 상세">
        <span className="wyvern"><i className="wing left" /><i className="wing right" /><i className="head" /></span>
        <b>REGION BOSS</b>
      </button>
      <button className="submob suspect" onClick={onMinion} aria-label="의심 손상 지점"><span>?</span></button>
      <button className="submob confirmed one" onClick={onMinion} aria-label="확정 손상 지점"><span>⌁</span></button>
      <button className="submob confirmed two" onClick={onMinion} aria-label="확정 손상 지점"><span>⌁</span></button>
      <div className="player-pin"><span>↟</span></div>
    </div>
  );
}

function BossSheet({ onClose, onDeck, onStart }: { onClose: () => void; onDeck: () => void; onStart: () => void }) {
  return (
    <Sheet onClose={onClose} className="boss-sheet">
      <span className="eyebrow">REGION BOSS · DONGTAN 2</span>
      <div className="boss-sheet-title"><div><h2>애스팔트 와이번</h2><p>데이터 안개 속에 숨어 도로를 노후화시키는 지역 보스</p></div><span className="boss-grade">B+</span></div>
      <div className="sheet-hp"><span style={{ width: "68%" }} /></div>
      <div className="boss-stats"><div><small>남은 체력</small><b>{BOSS_REMAINING_HEALTH.toLocaleString()}</b></div><div><small>활성 라이더</small><b>{ACTIVE_REGION_RIDERS}명</b></div><div><small>예상 보상</small><b>GOLD</b></div></div>
      <div className="boss-formula">
        <span>HP 산정</span>
        <b>미조사 {BOSS_HEALTH.unscannedCells}셀 + 갱신 {BOSS_HEALTH.refreshCells}셀</b>
        <small>활성 인원 보정 ×{BOSS_HEALTH.populationScale.toFixed(2)} · 총 {BOSS_HEALTH.totalHealth.toLocaleString()} HP</small>
      </div>
      <div className="best-route">
        <div className="route-mini-map"><i /><i /><span>1</span><b>2.4km</b></div>
        <div><span>FASTEST DAMAGE ROUTE</span><b>가장 빨리 깎는 경로</b><p>미탐사 1.6km · 노후 0.8km 포함</p></div>
      </div>
      <p className="route-disclosure">공략 경로는 데이터가 부족한 도로를 우선합니다.</p>
      <div className="sheet-actions"><button className="secondary-button" onClick={onDeck}>덱 확인</button><button className="primary-button" onClick={onStart}>이 경로로 주행</button></div>
    </Sheet>
  );
}

function MinionSheet({ onClose }: { onClose: () => void }) {
  return (
    <Sheet onClose={onClose} className="minion-sheet">
      <span className="eyebrow">SUB MOB · CROSS VALIDATION</span>
      <div className="minion-title"><span>⌁</span><div><h2>크랙 스프라이트</h2><p>인접 통과와 사진 인증이 모두 충족되면 처치됩니다.</p></div></div>
      <div className="minion-checks">
        <div><span>통과 반경</span><b>6.4m / 12m</b><i>충족</i></div>
        <div><span>사진 인증</span><b>{MINION_DEMO.cleared ? "확인됨" : "대기"}</b><i>충족</i></div>
        <div><span>가상 라이더 로그</span><b>{CROSS_VALIDATION.matchingRiders}/3</b><i>{CROSS_VALIDATION.verified ? "교차검증" : "대기"}</i></div>
      </div>
      <div className="spike-policy"><b>우연히 들어온 스파이크</b><p>검증 데이터에는 사용하지만 보상은 지급하지 않습니다.</p><span>DATA 유지 · REWARD {MINION_DEMO.rewardMileage} M</span></div>
      <button className="primary-button" onClick={onClose}>판정 확인</button>
    </Sheet>
  );
}

function DeckScreen({ onBack, onStart }: { onBack: () => void; onStart: () => void }) {
  const totalDamage = 1.15;
  return (
    <section className="full-screen sub-screen deck-screen">
      <SubHeader title="덱 편성" subtitle="ACTIVE SQUAD · 5/5" onBack={onBack} />
      <div className="deck-summary"><div><span>최종 데미지 배율</span><b>×{totalDamage.toFixed(2)}</b></div><div><span>마일리지 배율</span><b>×1.18</b></div></div>
      <div className="deck-pitch">
        <div className="pitch-line v" /><div className="pitch-line h" />
        {DECK_CARDS.map((card, index) => (
          <button className={`squad-card pos-${index + 1}`} key={card.name}>
            <GameCard card={card} compact />
          </button>
        ))}
      </div>
      <div className="deck-detail"><span className="eyebrow">EQUIPPED EFFECTS</span>{DECK_CARDS.map((card) => <div key={card.name}><b>{card.name}</b><span>{card.effect}</span></div>)}</div>
      <button className="primary-button deck-start" onClick={onStart}>이 덱으로 주행 시작</button>
    </section>
  );
}

function RideScreen({
  distance,
  seconds,
  holdProgress,
  confirmOpen,
  onHoldStart,
  onHoldEnd,
  onCancel,
  onConfirm,
}: {
  distance: number;
  seconds: number;
  holdProgress: number;
  confirmOpen: boolean;
  onHoldStart: () => void;
  onHoldEnd: () => void;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <section className="full-screen ride-screen">
      <div className="ride-distance"><small>CURRENT DISTANCE</small><b>{distance.toFixed(2)}</b><span>km</span></div>
      <div className="ride-time"><span>경과 시간</span><b>{formatTime(seconds)}</b></div>
      <button
        className="hold-end"
        style={{ "--hold": `${holdProgress}%` } as React.CSSProperties}
        onPointerDown={onHoldStart}
        onPointerUp={onHoldEnd}
        onPointerLeave={onHoldEnd}
        onPointerCancel={onHoldEnd}
      >
        <span>■</span>
        <div><b>주행 종료</b><small>길게 눌러 종료</small></div>
      </button>
      <div className="sr-only" aria-live="polite">주행 중. 미탐사 또는 노후 구간 진입 시 소리로 안내합니다.</div>
      {confirmOpen && (
        <div className="ride-confirm" role="dialog" aria-modal="true" aria-labelledby="ride-confirm-title">
          <div><span className="warning-mark">!</span><h2 id="ride-confirm-title">주행을 종료할까요?</h2><p>종료하면 바로 정산이 시작되며,<br />현재 주행으로 되돌릴 수 없습니다.</p><div><button onClick={onCancel}>계속 주행</button><button onClick={onConfirm}>종료하고 정산</button></div></div>
        </div>
      )}
    </section>
  );
}

function AnalysisScreen() {
  return (
    <section className="full-screen analysis-screen">
      <header><span className="eyebrow">RIDE ANALYSIS · AI PIPELINE</span><b>주행 데이터 분석 중</b><small>IMU · GPS · 도로 메타데이터</small></header>
      <div className="analysis-map">
        <div className="analysis-grid" />
        <div className="replay-route base" /><div className="replay-route gold" /><div className="replay-route silver" /><div className="replay-route gray" /><div className="replay-route blue" />
        <span className="replay-rider">↟</span>
        <i className="impact impact-1" /><i className="impact impact-2" /><i className="impact impact-3 false-positive" />
        <div className="false-label">과속방지턱으로 판정 <b>제외</b></div>
        <div className="cell-transition"><b>노후 → 최신</b><span>양호 재주행 데모</span></div>
        <div className="analysis-legend"><span><i className="gold" />신규</span><span><i className="silver" />갱신</span><span><i className="blue" />양호</span><span><i className="gray" />기존</span></div>
      </div>
      <div className="ai-cards">
        <div className="ai-card active"><span>01</span><div><b>구간 분할</b><small>{INITIAL_SENSOR_RULES.analysisWindowSeconds}초 중첩 윈도우</small></div><i>✓</i></div>
        <div className="ai-card active delay"><span>02</span><div><b>케이던스 PSD</b><small>100Hz · {CADENCE_DEMO.peakHz.toFixed(2)}Hz · {CADENCE_DEMO.cadenceRpm}rpm</small></div><i>BIKE</i></div>
        <div className="ai-card active later"><span>03</span><div><b>교차검증</b><small>지터 로그 {CROSS_VALIDATION.matchingRiders}개 · 10m 이내</small></div><i>{CROSS_VALIDATION.verified ? "3/3" : "WAIT"}</i></div>
      </div>
      <p className="analysis-note">가상 라이더·양호 전환은 시연 데이터입니다. 차량 반례와 실제 양호 구간 재주행 로그 확보 후 기준을 확정합니다.</p>
    </section>
  );
}

function DamageScreen({ ready, onNext }: { ready: boolean; onNext: () => void }) {
  const lines = [
    ["기본 데미지", "1,240"],
    ["신규 구간 크리티컬", "×2.0", "+1,240"],
    ["노후 구간 보너스", "×1.3", "+180"],
    ["덱 배율", "×1.15", "+399"],
  ];
  return (
    <section className={`full-screen damage-screen ${ready ? "ready" : ""}`}>
      <span className="eyebrow">DAMAGE SETTLEMENT</span>
      <h1>주행 기여를<br />데미지로 전환합니다</h1>
      <div className="damage-lines">{lines.map((line, index) => <div style={{ "--delay": `${index * 0.62}s` } as React.CSSProperties} key={line[0]}><span>{line[0]}</span><b>{line[1]}</b>{line[2] && <strong>{line[2]}</strong>}</div>)}</div>
      <div className="total-damage"><span>총 데미지</span><b>3,059</b></div>
      <div className="reward-timing"><div><span>즉시 반영</span><b>+{REWARDS.immediate.xp} XP · 보스 DMG</b></div><div><span>D+1 검수</span><b>+{REWARDS.pending.cashMileage} M</b></div></div>
      <div className="damage-boss-scene">
        <div className="damage-boss"><span className="wing left" /><span className="wing right" /><i /></div>
        <div className="multi-hp"><span className="hp-stage broken" /><span className="hp-stage current"><i /></span><span className="hp-stage" /></div>
        <strong>-3,059</strong><div className="stage-break">HP STAGE BREAK</div>
      </div>
      <button className={`primary-button damage-next ${ready ? "visible" : ""}`} onClick={onNext}>탐사 팩 확인</button>
    </section>
  );
}

function GoldPackScreen({
  index,
  revealed,
  drag,
  onPointerDown,
  onPointerMove,
  onPointerUp,
}: {
  index: number;
  revealed: boolean;
  drag: number;
  onPointerDown: (event: React.PointerEvent) => void;
  onPointerMove: (event: React.PointerEvent) => void;
  onPointerUp: () => void;
}) {
  const card = GOLD_PACK[index];
  return (
    <section className={`full-screen gold-pack-screen grade-${card.grade.toLowerCase()} ${revealed ? "revealed" : ""}`}>
      <div className="pack-rays gold" />
      <span className="eyebrow">EXPLORATION REWARD</span>
      <h1>{index === 0 && !revealed ? "골드 팩 획득" : `${index + 1} / ${GOLD_PACK.length}`}</h1>
      <p>{revealed ? "한 번 더 밀어 다음 카드를 확인하세요" : "카드 뒷면을 옆으로 밀어 뒤집으세요"}</p>
      <div className="pack-card-stack">
        <div className="stack-card back-two" /><div className="stack-card back-one" />
        <div
          className={`swipe-card ${revealed ? "is-revealed" : ""}`}
          style={{ transform: `translateX(${drag}px) rotate(${drag / 18}deg)` }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
        >
          <div className="card-back"><span>R2D</span><b>{card.grade}</b><i /></div>
          <div className="card-front"><GameCard card={card} /></div>
        </div>
      </div>
      <div className="swipe-guide"><span>←</span><b>SWIPE TO FLIP</b><span>→</span></div>
    </section>
  );
}

function SummaryScreen({ onShare, onHome, onRepair }: { onShare: () => void; onHome: () => void; onRepair: () => void }) {
  return (
    <section className="full-screen summary-screen">
      <SubHeader title="오늘의 탐사" subtitle="RIDE COMPLETE" />
      <div className="summary-map-card"><MapScene compact /><div className="summary-route" /><span className="summary-distance">3.2 km</span></div>
      <div className="recovery-change"><div><span>동네 복구율</span><b>41%</b></div><i>→</i><div className="after"><span>현재</span><b>43%</b></div></div>
      <div className="summary-list">
        <div><span className="summary-icon gold">↗</span><p>오늘 연 도로<small>신규 커버리지</small></p><b>3.2km</b></div>
        <div><span className="summary-icon red">⌁</span><p>발견한 손상 후보<small>교차검증 대기</small></p><b>2곳</b></div>
        <div><span className="summary-icon green">◇</span><p>즉시 보상<small>카드 3장 · 보스 데미지</small></p><b>+{REWARDS.immediate.xp} XP</b></div>
        <div><span className="summary-icon pending">◷</span><p>현금성 마일리지<small>D+1 이상치 검수 후 확정</small></p><b>+{REWARDS.pending.cashMileage} M</b></div>
      </div>
      <button className="share-button" onClick={onShare}>오늘의 궤적 공유 <span>↗</span></button>
      <button className="primary-button" onClick={onRepair}>보수 완료 알림 시연</button>
      <button className="text-button" onClick={onHome}>지도로 돌아가기</button>
    </section>
  );
}

function CollectionScreen({ onTab }: { onTab: (tab: Tab) => void }) {
  return (
    <section className="full-screen sub-screen collection-screen">
      <SubHeader title="카드 도감" subtitle="COLLECTION · 8/48" />
      <div className="collection-filter"><button className="active">전체</button><button>라이더</button><button>서포트</button><button>트래커</button></div>
      <div className="collection-grid">{[...DECK_CARDS, ...GOLD_PACK].map((card) => <GameCard card={card} compact key={`${card.name}-${card.grade}`} />)}{Array.from({ length: 4 }).map((_, index) => <div className="locked-card" key={index}><span>?</span><small>미획득</small></div>)}</div>
      <div className="signature-section"><div><span className="eyebrow">SIGNATURE ARCHIVE</span><b>도시를 바꾼 라이더의 증표</b></div><div className="signature-empty"><span>✦</span><b>아직 시그니처 카드가 없습니다</b><p>내가 발견한 손상이 교차검증되거나 실제 보수되면 획득할 수 있어요.</p></div></div>
      <GameNav active="collection" onTab={onTab} />
    </section>
  );
}

function RankingScreen({ onTab }: { onTab: (tab: Tab) => void }) {
  return (
    <section className="full-screen sub-screen ranking-screen">
      <SubHeader title="지역 리그" subtitle="LOCAL RESTORE LEAGUE" />
      <div className="league-card"><span>WEEK 04 · 화성시</span><div><b>동탄2동</b><strong>3위</strong></div><div className="league-progress"><span style={{ width: "43%" }} /></div><small>복구율 43% · 다음 순위까지 2.8%</small></div>
      <div className="neighborhood-rank">
        {[['1','동탄7동','48.2%','+5.1'],['2','동탄5동','45.8%','+3.7'],['3','동탄2동','43.0%','+3.0'],['4','반송동','40.4%','+1.9']].map((row) => <div className={row[0] === '3' ? 'mine' : ''} key={row[0]}><strong>{row[0]}</strong><span>{row[1]}</span><b>{row[2]}</b><i>{row[3]}%</i></div>)}
      </div>
      <div className="personal-rank"><div><span className="eyebrow">INDIVIDUAL COVERAGE</span><b>개인 커버리지 순위</b></div><div className="my-rank"><span>12</span><div><b>RIDER 019</b><small>중복 제외 커버리지 18.4km</small></div><strong>상위 8%</strong></div></div>
      <p className="ranking-rule">순위는 주행거리가 아니라 중복을 제외한 유효 커버리지로 계산합니다.</p>
      <GameNav active="ranking" onTab={onTab} />
    </section>
  );
}

function ShopScreen({ onTab, onExchange }: { onTab: (tab: Tab) => void; onExchange: () => void }) {
  const coupons = [
    ["MILE 01", "신리천 로스터스", "아메리카노 1잔", "1,200 M"],
    ["MILE 02", "카페 수평선", "브런치 세트 20%", "1,800 M"],
    ["MILE 03", "페달 앤 빈", "라이더 보틀", "2,400 M"],
  ];
  return (
    <section className="full-screen sub-screen shop-screen">
      <SubHeader title="마일리지 상점" subtitle="SHINRICHEON PARTNERS" />
      <div className="mileage-wallet"><span>AVAILABLE MILEAGE</span><b>3,480 <small>M</small></b><p>오늘의 탐사로 +480M</p></div>
      <div className="cafe-strip"><span>동탄 신리천</span><b>카페거리 파트너 혜택</b><p>도시를 밝힌 마일리지를 동네에서 사용하세요.</p></div>
      <div className="coupon-list">{coupons.map((coupon, index) => <button onClick={onExchange} key={coupon[0]}><div className={`coupon-visual cafe-${index + 1}`}><span>R2D</span></div><div><small>{coupon[0]}</small><b>{coupon[1]}</b><span>{coupon[2]}</span></div><strong>{coupon[3]}</strong></button>)}</div>
      <p className="shop-note">제휴 혜택은 시연용 예시이며 실제 제휴 확정 전에는 사용할 수 없습니다.</p>
      <GameNav active="shop" onTab={onTab} />
    </section>
  );
}

function RepairScreen({ onDone }: { onDone: () => void }) {
  return (
    <section className="full-screen repair-screen">
      <header><span className="eyebrow">REAL WORLD UPDATE</span><b>도로 보수 확인</b></header>
      <div className="repair-map"><div className="repair-road"><span /></div><div className="repair-monster"><i /><b>⌁</b></div><div className="repair-sparkles"><i /><i /><i /><i /><i /></div><span className="repair-stamp">RESTORED</span></div>
      <div className="repair-copy"><span className="repair-check">✓</span><h1>당신이 처음 발견한<br />손상이 사라졌습니다</h1><p>동탄2동 신리천 자전거도로의 보수가 확인되었습니다. 지도에서 해당 몹이 소멸합니다.</p></div>
      <div className="repair-contribution"><span>궤적 편차</span><b>{REPAIR_DEMO.maxTrajectoryDeviationM}m / 5m</b><i>충족</i><span>무충격 재주행</span><b>라이더 {REPAIR_DEMO.noImpactRiderCount}명</b><i>{isRepairConfirmed(REPAIR_DEMO) ? "동시 충족" : "대기"}</i></div>
      <div className="signature-award"><span>✦</span><div><small>SIGNATURE CARD AWARDED</small><b>도시의 첫 목격자</b></div></div>
      <button className="primary-button" onClick={onDone}>복구된 지도 확인</button>
    </section>
  );
}

function NotificationSheet({ onClose, onRepair }: { onClose: () => void; onRepair: () => void }) {
  return (
    <Sheet onClose={onClose} className="notification-sheet">
      <span className="eyebrow">ASYNCHRONOUS EVENTS</span><h2>도시에서 온 소식</h2>
      <button className="notification important" onClick={onRepair}><span>✓</span><div><b>동탄2동 자전거도로 보수 완료</b><p>당신이 처음 발견한 손상이 사라졌습니다.</p><small>방금 전</small></div><i>→</i></button>
      <button className="notification"><span>4</span><div><b>교차검증이 완료되었습니다</b><p>3일 전 발견한 지점이 다른 라이더 4명에게 확인되었습니다.</p><small>2시간 전 · 시그니처 카드 지급</small></div><i>→</i></button>
    </Sheet>
  );
}

function ProfileSheet({ onClose, onReplay }: { onClose: () => void; onReplay: () => void }) {
  return (
    <Sheet onClose={onClose} className="profile-sheet">
      <div className="profile-avatar">R</div><span className="eyebrow">RIDER 019</span><h2>도시를 밝히는 중</h2>
      <div className="profile-stats"><div><b>18.4km</b><span>유효 커버리지</span></div><div><b>7곳</b><span>발견 기여</span></div><div><b>43%</b><span>동네 복구율</span></div></div>
      <button className="secondary-button full" onClick={onReplay}>온보딩 다시보기</button>
    </Sheet>
  );
}

function ShareSheet({ onClose }: { onClose: () => void }) {
  return (
    <Sheet onClose={onClose} className="share-sheet">
      <div className="share-card"><span className="eyebrow">R2D · TODAY</span><h2>오늘 3.2km의<br />도시를 열었습니다</h2><div className="share-route-art"><i /><b>3.2km</b></div><p>동탄2동 복구율 41% → 43%</p></div>
      <button className="primary-button" onClick={() => { void navigator.clipboard?.writeText(window.location.href); onClose(); }}>링크 복사</button>
    </Sheet>
  );
}

function GameNav({ active, onTab, onDeck }: { active: Tab; onTab: (tab: Tab) => void; onDeck?: () => void }) {
  const items: Array<[Tab | "deck", string, string]> = [["home", "⌖", "지도"], ["deck", "▣", "덱"], ["collection", "◇", "도감"], ["ranking", "↟", "리그"], ["shop", "M", "상점"]];
  return <nav className="game-nav" aria-label="게임 메뉴">{items.map(([tab, icon, label]) => <button className={tab === active ? "active" : ""} onClick={() => tab === "deck" ? onDeck?.() : onTab(tab)} key={tab}><span>{icon}</span><small>{label}</small></button>)}</nav>;
}

function GameCard({ card, compact = false }: { card: CardData; compact?: boolean }) {
  return (
    <article className={`game-card grade-${card.grade.toLowerCase()} ${compact ? "compact" : ""}`}>
      <span className="card-grade">{card.grade}</span><div className="card-glyph">{card.glyph}</div><span className="card-type">{card.type}</span><h3>{card.name}</h3>
      <div className="card-stats"><span>DMG <b>{card.damage}</b></span><span>MILE <b>{card.mileage}</b></span></div><p>{card.effect}</p>
    </article>
  );
}

function MiniCard({ card, style }: { card: CardData; style?: React.CSSProperties }) {
  return <div className="mini-card" style={style}><span>{card.glyph}</span><b>{card.name}</b><small>{card.grade}</small></div>;
}

function OnboardingHeader({ step, total, label }: { step: number; total: number; label: string }) {
  return <header className="onboarding-header"><span>{label}</span><div>{Array.from({ length: total }).map((_, index) => <i className={index < step ? "active" : ""} key={index} />)}</div><b>{step}/{total}</b></header>;
}

function SubHeader({ title, subtitle, onBack }: { title: string; subtitle: string; onBack?: () => void }) {
  return <header className="sub-header">{onBack ? <button onClick={onBack}>←</button> : <span className="sub-logo">R2D</span>}<div><small>{subtitle}</small><h1>{title}</h1></div><button className="sub-more">···</button></header>;
}

function Sheet({ children, onClose, className = "" }: { children: React.ReactNode; onClose: () => void; className?: string }) {
  return <div className="sheet-backdrop" role="presentation"><section className={`bottom-sheet ${className}`} role="dialog" aria-modal="true"><button className="sheet-close" onClick={onClose} aria-label="닫기">×</button><div className="sheet-grabber" />{children}</section></div>;
}
