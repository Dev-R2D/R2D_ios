import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const protocol = requestHeaders.get("x-forwarded-proto") ?? (host?.includes("localhost") ? "http" : "https");
  const origin = host ? `${protocol}://${host}` : "https://roadpulse-go-sensor-mvp.rudfhr020205.chatgpt.site";
  const imageUrl = `${origin}/og-road-to-data.png`;

  return {
    title: "R2D — Road to Data",
    description: "자전거 주행을 도로 데이터와 동네 보스 공략으로 연결하는 도시 복구 게임",
    manifest: "/manifest.webmanifest",
    applicationName: "R2D",
    openGraph: {
      type: "website",
      title: "R2D — Road to Data",
      description: "RIDE · VERIFY · RESTORE",
      images: [{ url: imageUrl, width: 1536, height: 1024, alt: "R2D 도시 탐사 게임" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "R2D — Road to Data",
      description: "RIDE · VERIFY · RESTORE",
      images: [imageUrl],
    },
  };
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  viewportFit: "cover",
  themeColor: "#070a09",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ko"><body>{children}</body></html>;
}
