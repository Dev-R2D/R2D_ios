"use client";

import { useEffect, useState } from "react";

export type MapConfig = {
  kakaoJavascriptKey: string;
  vworldApiKey: string;
  loaded: boolean;
};

const emptyConfig: MapConfig = {
  kakaoJavascriptKey: "",
  vworldApiKey: "",
  loaded: false,
};

export function useMapConfig() {
  const [config, setConfig] = useState<MapConfig>(emptyConfig);

  useEffect(() => {
    const controller = new AbortController();
    void fetch("/api/map-config", { signal: controller.signal, cache: "no-store" })
      .then((response) => {
        if (!response.ok) throw new Error("Map configuration request failed");
        return response.json() as Promise<Omit<MapConfig, "loaded">>;
      })
      .then((value) => setConfig({ ...value, loaded: true }))
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setConfig({ ...emptyConfig, loaded: true });
      });
    return () => controller.abort();
  }, []);

  return config;
}
