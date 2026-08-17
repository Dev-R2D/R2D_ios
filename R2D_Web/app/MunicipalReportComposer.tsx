"use client";

import { ChangeEvent, FormEvent, useEffect, useMemo, useState } from "react";

type ReportPoint = {
  latitude: number;
  longitude: number;
  time: number;
  score: number;
  eligible: boolean;
  grade: string;
};

type ReportAuthority = {
  name: string;
  department: string;
  channel: string;
  portalUrl: string;
  reason: string;
};

const categoryLabels: Record<string, string> = {
  missing: "탈락",
  step: "단차",
  damage: "파손",
  pothole: "포트홀",
  wear: "마모",
  joint_gap: "줄눈벌어짐",
  heave: "융기",
  drainage: "배수시설",
  tactile_block: "점자블록",
  utility_cover: "시설물커버",
  unknown: "판단불가",
};

const observationByCategory: Record<string, string> = {
  missing: "첨부 사진에서 포장재 또는 시설 일부가 탈락한 것으로 의심되는 지점을 확인했습니다.",
  step: "첨부 사진에서 자전거 통행에 충격을 줄 수 있는 단차로 의심되는 지점을 확인했습니다.",
  damage: "첨부 사진에서 도로 또는 부속시설 파손으로 의심되는 지점을 확인했습니다.",
  pothole: "첨부 사진에서 포장면 포트홀로 의심되는 지점을 확인했습니다.",
  wear: "첨부 사진에서 노면 마모로 의심되는 지점을 확인했습니다.",
  joint_gap: "첨부 사진에서 줄눈 벌어짐으로 의심되는 지점을 확인했습니다.",
  heave: "첨부 사진에서 노면 융기로 의심되는 지점을 확인했습니다.",
  drainage: "첨부 사진에서 배수시설 관련 이상으로 의심되는 지점을 확인했습니다.",
  tactile_block: "첨부 사진에서 점자블록 관련 이상으로 의심되는 지점을 확인했습니다.",
  utility_cover: "첨부 사진에서 시설물커버 관련 이상으로 의심되는 지점을 확인했습니다.",
  unknown: "첨부 사진만으로 유형 판단이 어려워 현장 확인을 요청합니다.",
};

const gradeLabels: Record<string, string> = {
  good: "양호",
  fair: "보통",
  caution: "주의",
  poor: "집중 확인",
};

const epeopleUrl = "https://www.epeople.go.kr/index.jsp";

function formatDuration(seconds: number) {
  const rounded = Math.round(seconds);
  const minutes = Math.floor(rounded / 60);
  const secs = rounded % 60;
  return `${minutes}:${String(secs).padStart(2, "0")}`;
}

function resolveAuthority(latitude: number, longitude: number): ReportAuthority {
  const isHangangSeoul = latitude >= 37.49 && latitude <= 37.56 && longitude >= 126.94 && longitude <= 127.12;
  if (isHangangSeoul) {
    return {
      name: "서울특별시",
      department: "미래한강본부 또는 관할 한강공원 안내센터",
      channel: "서울시 응답소",
      portalUrl: "https://eungdapso.seoul.go.kr/main.do",
      reason: "한강공원 내부 자전거도로는 일반 자치구 도로보다 미래한강본부 관리 가능성이 높습니다.",
    };
  }

  const isDongtan = latitude >= 37.12 && latitude <= 37.24 && longitude >= 127.02 && longitude <= 127.19;
  if (isDongtan) {
    return {
      name: "화성특례시 동탄구",
      department: "동탄구청 안전건설과 도로관리팀",
      channel: "국민신문고",
      portalUrl: epeopleUrl,
      reason: "동탄구 실측 좌표로 확인되어 국민신문고에서 관할기관 배정 후 접수하도록 연결합니다.",
    };
  }

  const isSeoul = latitude >= 37.41 && latitude <= 37.71 && longitude >= 126.76 && longitude <= 127.19;
  if (isSeoul) {
    return {
      name: "서울특별시 관할 자치구",
      department: "도로관리 또는 교통시설 담당부서",
      channel: "서울시 응답소",
      portalUrl: "https://eungdapso.seoul.go.kr/main.do",
      reason: "서울 지역 좌표로 확인되어 응답소에서 실제 관리기관 배정을 받도록 추천합니다.",
    };
  }

  return {
    name: "관할 지방자치단체",
    department: "도로관리·안전건설 담당부서",
    channel: "안전신문고",
    portalUrl: "https://www.safetyreport.go.kr/index.html",
    reason: "좌표를 기준으로 안전신문고에서 관할기관을 지정·조정하도록 연결합니다.",
  };
}

function readAscii(view: DataView, offset: number, length: number) {
  let value = "";
  for (let index = 0; index < length; index += 1) value += String.fromCharCode(view.getUint8(offset + index));
  return value;
}

function extractJpegGps(buffer: ArrayBuffer) {
  const view = new DataView(buffer);
  if (view.byteLength < 4 || view.getUint16(0, false) !== 0xffd8) return null;
  let offset = 2;

  while (offset + 4 < view.byteLength) {
    if (view.getUint8(offset) !== 0xff) break;
    const marker = view.getUint8(offset + 1);
    const length = view.getUint16(offset + 2, false);
    const dataStart = offset + 4;
    if (marker === 0xe1 && dataStart + 6 < view.byteLength && readAscii(view, dataStart, 6) === "Exif\u0000\u0000") {
      const tiff = dataStart + 6;
      const littleEndian = readAscii(view, tiff, 2) === "II";
      if (view.getUint16(tiff + 2, littleEndian) !== 42) return null;
      const ifd0 = tiff + view.getUint32(tiff + 4, littleEndian);
      const ifd0Count = view.getUint16(ifd0, littleEndian);
      let gpsIfd = 0;
      for (let index = 0; index < ifd0Count; index += 1) {
        const entry = ifd0 + 2 + index * 12;
        if (view.getUint16(entry, littleEndian) === 0x8825) {
          gpsIfd = tiff + view.getUint32(entry + 8, littleEndian);
          break;
        }
      }
      if (!gpsIfd || gpsIfd + 2 >= view.byteLength) return null;

      let latitudeRef = "N";
      let longitudeRef = "E";
      let latitude: number[] | null = null;
      let longitude: number[] | null = null;
      const gpsCount = view.getUint16(gpsIfd, littleEndian);
      const rationals = (entry: number) => {
        const valueOffset = tiff + view.getUint32(entry + 8, littleEndian);
        return [0, 1, 2].map((part) => {
          const numerator = view.getUint32(valueOffset + part * 8, littleEndian);
          const denominator = view.getUint32(valueOffset + part * 8 + 4, littleEndian);
          return denominator ? numerator / denominator : 0;
        });
      };
      for (let index = 0; index < gpsCount; index += 1) {
        const entry = gpsIfd + 2 + index * 12;
        const tag = view.getUint16(entry, littleEndian);
        if (tag === 1) latitudeRef = String.fromCharCode(view.getUint8(entry + 8));
        if (tag === 2) latitude = rationals(entry);
        if (tag === 3) longitudeRef = String.fromCharCode(view.getUint8(entry + 8));
        if (tag === 4) longitude = rationals(entry);
      }
      if (!latitude || !longitude) return null;
      const toDecimal = (parts: number[]) => parts[0] + parts[1] / 60 + parts[2] / 3600;
      const lat = toDecimal(latitude) * (latitudeRef === "S" ? -1 : 1);
      const lon = toDecimal(longitude) * (longitudeRef === "W" ? -1 : 1);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
      return { latitude: lat, longitude: lon };
    }
    if (length < 2) break;
    offset += length + 2;
  }
  return null;
}

function buildDraft({
  category,
  severity,
  locationLabel,
  latitude,
  longitude,
  datasetLabel,
  point,
  photoName,
}: {
  category: string;
  severity: string;
  locationLabel: string;
  latitude: string;
  longitude: string;
  datasetLabel: string;
  point: ReportPoint;
  photoName: string;
}) {
  const categoryLabel = categoryLabels[category] ?? "도로 노면 이상";
  const location = locationLabel.trim() || `${latitude}, ${longitude}`;
  const title = `[현장점검 요청] ${location} ${categoryLabel}`;
  const scoreEvidence = point.eligible
    ? `${datasetLabel} ${formatDuration(point.time)} 구간에서 R2D 상대 노면점수 ${point.score}점(${gradeLabels[point.grade] ?? point.grade})으로 표시되었습니다.`
    : `${datasetLabel}의 인접 센서 구간은 신뢰도 조건으로 점수에서 제외되어 사진을 중심으로 확인을 요청합니다.`;
  const urgency = severity === "urgent"
    ? "자전거 이용자의 전도·충돌 위험이 우려되어 신속한 현장 확인과 임시 안전조치를 요청드립니다."
    : "자전거 통행 안전을 위해 현장 확인과 보수 필요성 검토를 요청드립니다.";
  const description = [
    `○ 신고 위치: ${location}`,
    `○ 좌표: ${latitude}, ${longitude}`,
    `○ 신고 유형: ${categoryLabel}`,
    `○ 현장 관찰: ${observationByCategory[category] ?? observationByCategory.unknown}`,
    `○ 첨부 사진: ${photoName || "현장 사진 1장"}`,
    `○ R2D 참고정보: ${scoreEvidence}`,
    `○ 요청사항: ${urgency}`,
    "※ R2D 점수는 스마트폰 GPS·IMU 기반 현장 확인 후보이며 공인 IRI·PCI 또는 파손 확정 판정이 아닙니다.",
  ].join("\n");
  return { title, description };
}

export default function MunicipalReportComposer({
  datasetLabel,
  point,
  onSaved,
}: {
  datasetLabel: string;
  point: ReportPoint;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    category: "damage",
    severity: "caution",
    locationLabel: `${datasetLabel} ${formatDuration(point.time)} 구간`,
    latitude: point.latitude.toFixed(6),
    longitude: point.longitude.toFixed(6),
  });
  const [draftTitle, setDraftTitle] = useState("");
  const [draftDescription, setDraftDescription] = useState("");
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);
  const [photoName, setPhotoName] = useState("");
  const [photoSize, setPhotoSize] = useState(0);
  const [photoLocationState, setPhotoLocationState] = useState<"none" | "found" | "missing">("none");
  const [consented, setConsented] = useState(false);
  const [submitState, setSubmitState] = useState<"idle" | "submitting" | "success" | "error">("idle");
  const [message, setMessage] = useState("");

  const latitude = Number(form.latitude);
  const longitude = Number(form.longitude);
  const authority = useMemo(
    () => resolveAuthority(Number.isFinite(latitude) ? latitude : 0, Number.isFinite(longitude) ? longitude : 0),
    [latitude, longitude],
  );

  useEffect(() => () => {
    if (photoUrl) URL.revokeObjectURL(photoUrl);
  }, [photoUrl]);

  function generateDraft(nextForm = form, nextPhotoName = photoName) {
    const draft = buildDraft({ ...nextForm, datasetLabel, point, photoName: nextPhotoName });
    setDraftTitle(draft.title);
    setDraftDescription(draft.description);
    setMessage("위치·유형·센서 참고정보를 이용해 민원서 초안을 만들었습니다. 사진과 내용이 일치하는지 확인해 주세요.");
  }

  async function selectPhoto(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    if (!new Set(["image/jpeg", "image/png", "image/webp"]).has(file.type)) {
      setSubmitState("error");
      setMessage("JPG, PNG 또는 WebP 사진만 올릴 수 있습니다.");
      return;
    }
    if (file.size > 12 * 1024 * 1024) {
      setSubmitState("error");
      setMessage("사진은 12MB 이하로 선택해 주세요.");
      return;
    }
    if (photoUrl) URL.revokeObjectURL(photoUrl);
    setPhotoUrl(URL.createObjectURL(file));
    setPhotoName(file.name);
    setPhotoSize(file.size);
    setSubmitState("idle");

    let nextForm = form;
    if (file.type === "image/jpeg") {
      try {
        const gps = extractJpegGps(await file.arrayBuffer());
        if (gps) {
          nextForm = {
            ...form,
            locationLabel: "사진 GPS 위치",
            latitude: gps.latitude.toFixed(6),
            longitude: gps.longitude.toFixed(6),
          };
          setForm(nextForm);
          setPhotoLocationState("found");
        } else {
          setPhotoLocationState("missing");
        }
      } catch {
        setPhotoLocationState("missing");
      }
    } else {
      setPhotoLocationState("missing");
    }
    generateDraft(nextForm, file.name);
  }

  function useSelectedLocation() {
    const nextForm = {
      ...form,
      locationLabel: `${datasetLabel} ${formatDuration(point.time)} 구간`,
      latitude: point.latitude.toFixed(6),
      longitude: point.longitude.toFixed(6),
    };
    setForm(nextForm);
    generateDraft(nextForm);
  }

	  function usePhoneLocation() {
    if (!navigator.geolocation) {
      setSubmitState("error");
      setMessage("이 기기에서는 현재 위치를 가져올 수 없습니다.");
      return;
    }
    setMessage("휴대전화 위치를 확인하고 있습니다…");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const nextForm = {
          ...form,
          locationLabel: "휴대전화 현재 위치",
          latitude: position.coords.latitude.toFixed(6),
          longitude: position.coords.longitude.toFixed(6),
        };
        setForm(nextForm);
        generateDraft(nextForm);
      },
      () => {
        setSubmitState("error");
        setMessage("위치 권한을 확인하지 못했습니다. 지도 좌표를 사용하거나 직접 입력해 주세요.");
      },
      { enableHighAccuracy: true, timeout: 12_000, maximumAge: 5_000 },
	    );
	  }

	  function officialComplaintText() {
	    return `${draftTitle}\n\n${draftDescription}`;
	  }

	  async function copyDraftToClipboard() {
	    if (!draftTitle || draftDescription.length < 20) {
	      setSubmitState("error");
	      setMessage("복사할 민원서 초안을 먼저 생성해 주세요.");
	      return;
	    }

	    try {
	      await navigator.clipboard.writeText(officialComplaintText());
	      setSubmitState("success");
	      setMessage("민원 초안을 복사했습니다. 국민신문고 접수 화면에 붙여넣어 주세요.");
	    } catch {
	      setSubmitState("error");
	      setMessage("브라우저 권한 때문에 복사하지 못했습니다. 아래 민원 내용을 직접 선택해 복사해 주세요.");
	    }
	  }

	  async function submitReport(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!photoUrl) {
      setSubmitState("error");
      setMessage("현장 사진을 먼저 선택해 주세요.");
      return;
    }
    if (!draftTitle || draftDescription.length < 20) {
      setSubmitState("error");
      setMessage("민원서 초안을 먼저 생성해 주세요.");
      return;
    }
    if (!consented) {
      setSubmitState("error");
      setMessage("사진과 민원 내용 확인 항목에 동의해 주세요.");
      return;
    }

	    const portalWindow = window.open(authority.portalUrl, "_blank");
	    if (portalWindow) portalWindow.opener = null;

	    setSubmitState("submitting");
	    setMessage("R2D 제보를 저장하고 공식 작성 화면으로 이동합니다…");
    try {
      const response = await fetch("/api/reports", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          category: form.category,
          severity: form.severity,
          description: `${draftTitle} — ${draftDescription}`,
          locationLabel: form.locationLabel,
          latitude,
          longitude,
        }),
      });
      const payload = await response.json() as { report?: unknown; error?: string };
      if (!response.ok || !payload.report) throw new Error(payload.error || "R2D 제보 저장에 실패했습니다.");
      setSubmitState("success");
      onSaved();
	    setMessage(
	      portalWindow
	        ? `${authority.channel} 작성 화면을 열었습니다. '민원 초안 복사' 버튼으로 내용을 복사한 뒤 붙여넣고 최종 제출해 주세요.`
	        : `R2D에는 저장됐지만 팝업이 차단됐습니다. 아래 '${authority.channel} 열기'를 눌러 작성 화면으로 이동해 주세요.`,
	    );
    } catch (error) {
      setSubmitState("error");
      setMessage(error instanceof Error ? error.message : "제보 저장에 실패했습니다.");
    }
  }

  return (
    <form className="card report-form report-composer" onSubmit={submitReport}>
      <div className="report-form-head">
        <div>
          <span className="card-label">PHOTO → DRAFT → AUTHORITY → SUBMIT</span>
          <h3>사진으로 민원서 자동작성</h3>
        </div>
        <span className="provisional">최종 제출 전 확인</span>
      </div>

      <ol className="report-steps" aria-label="민원 작성 단계">
        <li className={photoUrl ? "done" : "active"}><b>1</b><span>사진</span></li>
        <li className={draftDescription ? "done" : photoUrl ? "active" : ""}><b>2</b><span>자동작성</span></li>
        <li className={draftDescription ? "active" : ""}><b>3</b><span>관할 확인</span></li>
        <li><b>4</b><span>공식 제출</span></li>
      </ol>

      <label className={`report-photo-drop ${photoUrl ? "has-photo" : ""}`}>
        <input type="file" accept="image/jpeg,image/png,image/webp" onChange={selectPhoto} />
        {photoUrl ? (
          <>
            <img src={photoUrl} alt="민원에 첨부할 현장 사진 미리보기" />
            <span><strong>{photoName}</strong><small>{(photoSize / 1024 / 1024).toFixed(1)}MB · 사진 변경</small></span>
          </>
        ) : (
          <span><strong>현장 사진 선택</strong><small>JPG·PNG·WebP · 최대 12MB</small></span>
        )}
      </label>
      <p className="report-privacy-note">
        사진은 현재 브라우저에서 미리보기와 GPS 확인에만 사용하며 R2D 서버에는 저장하지 않습니다. 공식 접수창에서 같은 사진을 다시 첨부해야 합니다.
      </p>
      {photoLocationState !== "none" && (
        <p className={`photo-location-state ${photoLocationState}`}>
          {photoLocationState === "found" ? "사진의 EXIF GPS 좌표를 적용했습니다." : "사진에 GPS가 없어 지도 선택 좌표를 유지합니다."}
        </p>
      )}

      <div className="report-form-fields">
        <label>
          <span>사진 분류</span>
          <select value={form.category} onChange={(event) => setForm((current) => ({ ...current, category: event.target.value }))}>
            {Object.entries(categoryLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label>
          <span>확인 우선순위</span>
          <select value={form.severity} onChange={(event) => setForm((current) => ({ ...current, severity: event.target.value }))}>
            <option value="caution">주의</option>
            <option value="urgent">긴급 확인</option>
          </select>
        </label>
        <label className="wide">
          <span>위치 설명</span>
          <input value={form.locationLabel} maxLength={80} onChange={(event) => setForm((current) => ({ ...current, locationLabel: event.target.value }))} />
        </label>
        <label>
          <span>위도</span>
          <input inputMode="decimal" value={form.latitude} onChange={(event) => setForm((current) => ({ ...current, latitude: event.target.value }))} required />
        </label>
        <label>
          <span>경도</span>
          <input inputMode="decimal" value={form.longitude} onChange={(event) => setForm((current) => ({ ...current, longitude: event.target.value }))} required />
        </label>
      </div>

      <div className="report-location-actions">
        <button type="button" onClick={useSelectedLocation}>지도 선택 좌표 사용</button>
        <button type="button" onClick={usePhoneLocation}>휴대전화 현재 위치</button>
        <button type="button" className="draft-refresh" onClick={() => generateDraft()}>초안 다시 생성</button>
      </div>

      {draftDescription && (
        <div className="report-draft-editor">
          <label>
            <span>민원 제목</span>
            <input value={draftTitle} maxLength={120} onChange={(event) => setDraftTitle(event.target.value)} />
          </label>
          <label>
            <span>민원 내용</span>
            <textarea value={draftDescription} maxLength={1800} onChange={(event) => setDraftDescription(event.target.value)} />
          </label>
        </div>
      )}

      <div className="authority-result">
        <span>추천 관할기관</span>
        <strong>{authority.name}</strong>
        <b>{authority.department}</b>
        <p>{authority.reason}</p>
        <small>공식 접수 채널 · {authority.channel}</small>
      </div>

      <label className="report-consent">
        <input type="checkbox" checked={consented} onChange={(event) => setConsented(event.target.checked)} />
        <span>사진에 얼굴·차량번호 등 불필요한 개인정보가 없는지 확인했고, 민원 내용과 위치를 최종 검토했습니다.</span>
	      </label>

	      {message && <p className={`report-message ${submitState}`} role="status">{message}</p>}
	      <button className="report-submit secondary" type="button" onClick={copyDraftToClipboard}>
	        민원 초안 복사
	      </button>
	      <button className="report-submit" type="submit" disabled={submitState === "submitting"}>
	        {submitState === "submitting" ? "접수 준비 중…" : `R2D 저장 + ${authority.channel} 접수창 열기`}
	      </button>
      <a className="official-portal-fallback" href={authority.portalUrl} target="_blank" rel="noreferrer">{authority.channel} 직접 열기</a>
      <p className="official-submit-boundary">기관 로그인·본인확인·사진 첨부·최종 제출은 공식 사이트에서 사용자가 완료해야 합니다.</p>
    </form>
  );
}
