"use client";

import { useEffect, useRef, useState } from "react";
import { useMapConfig } from "./useMapConfig";

declare global {
  interface Window {
    kakao?: {
      maps: {
        load: (callback: () => void) => void;
        LatLng: new (latitude: number, longitude: number) => unknown;
        Roadview: new (container: HTMLElement) => { setPanoId: (panoId: number, position: unknown) => void };
        RoadviewClient: new () => {
          getNearestPanoId: (position: unknown, radius: number, callback: (panoId: number | null) => void) => void;
        };
      };
    };
  }
}

let kakaoLoader: Promise<void> | null = null;

function loadKakaoMaps(key: string) {
  if (window.kakao?.maps) {
    return new Promise<void>((resolve) => window.kakao?.maps.load(resolve));
  }
  if (kakaoLoader) return kakaoLoader;

  kakaoLoader = new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = `https://dapi.kakao.com/v2/maps/sdk.js?appkey=${encodeURIComponent(key)}&autoload=false`;
    script.async = true;
    script.onload = () => {
      if (!window.kakao?.maps) {
        reject(new Error("Kakao Maps SDK did not initialize"));
        return;
      }
      window.kakao.maps.load(resolve);
    };
    script.onerror = () => reject(new Error("Kakao Maps SDK failed to load"));
    document.head.appendChild(script);
  });

  return kakaoLoader;
}

export default function KakaoRoadview({
  latitude,
  longitude,
  spotId,
}: {
  latitude: number;
  longitude: number;
  spotId: number;
}) {
  const config = useMapConfig();
  const containerRef = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "missing" | "setup">("loading");

  useEffect(() => {
    if (!config.loaded) return;
    let disposed = false;
    let statusTimer: number | undefined;
    const updateStatus = (next: "loading" | "ready" | "missing" | "setup") => {
      window.clearTimeout(statusTimer);
      statusTimer = window.setTimeout(() => {
        if (!disposed) setStatus(next);
      }, 0);
    };

    if (!config.kakaoJavascriptKey) {
      updateStatus("setup");
      return () => {
        disposed = true;
        window.clearTimeout(statusTimer);
      };
    }

    updateStatus("loading");
    void loadKakaoMaps(config.kakaoJavascriptKey)
      .then(() => {
        if (disposed || !containerRef.current || !window.kakao?.maps) return;
        const maps = window.kakao.maps;
        const position = new maps.LatLng(latitude, longitude);
        const roadview = new maps.Roadview(containerRef.current);
        const client = new maps.RoadviewClient();
        client.getNearestPanoId(position, 500, (panoId) => {
          if (disposed) return;
          if (panoId === null) {
            setStatus("missing");
            return;
          }
          roadview.setPanoId(panoId, position);
          setStatus("ready");
        });
      })
      .catch(() => {
        if (!disposed) setStatus("setup");
      });

    return () => {
      disposed = true;
      window.clearTimeout(statusTimer);
    };
  }, [config.kakaoJavascriptKey, config.loaded, latitude, longitude]);

  const mapUrl = `https://map.kakao.com/link/map/R2D%20SPOT%20${spotId},${latitude},${longitude}`;
  const roadviewUrl = `https://map.kakao.com/link/roadview/${latitude},${longitude}`;

  return (
    <section className="kakao-roadview-card" aria-label={`충격 SPOT ${spotId} 카카오 로드뷰`}>
      <div className="kakao-roadview-head">
        <div>
          <span>KAKAO ROADVIEW / NEAREST PANORAMA</span>
          <strong>SPOT {String(spotId).padStart(2, "0")} 주변 실사</strong>
        </div>
        <small>GPS 좌표에서 500 m 안의 가장 가까운 파노라마</small>
      </div>
      <div className="kakao-roadview-stage">
        <div ref={containerRef} className="kakao-roadview-canvas" />
        {status !== "ready" && (
          <div className="kakao-roadview-message">
            {status === "loading" && <><strong>로드뷰를 불러오는 중</strong><span>선택한 이벤트 좌표와 가까운 카카오 파노라마를 찾고 있습니다.</span></>}
            {status === "missing" && <><strong>가까운 로드뷰 촬영점이 없습니다.</strong><span>한강 자전거전용도로는 카카오 촬영 파노라마가 없을 수 있습니다. 이벤트 영상과 항공사진을 함께 확인하세요.</span></>}
            {status === "setup" && <><strong>카카오 지도 설정을 확인해 주세요.</strong><span>JavaScript 키, 현재 사이트 도메인 등록, Kakao Map API 활성화가 모두 필요합니다.</span></>}
          </div>
        )}
      </div>
      <div className="spot-actions">
        <a href={roadviewUrl} target="_blank" rel="noreferrer">카카오 로드뷰 새 창</a>
        <a href={mapUrl} target="_blank" rel="noreferrer">카카오 지도 좌표</a>
      </div>
    </section>
  );
}
