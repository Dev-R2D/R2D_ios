import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL("https://roadpulse-jamwon-260717.rudfhr020205.chatgpt.site"),
  title: "R2D | 실시간 도로 노면 관제",
  description: "공무원이 GPS·IMU 노면 신호, 충격 이벤트와 시민 현장 제보를 한 지도에서 확인하는 실시간 도로 상태 관제 대시보드",
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
  openGraph: {
    title: "R2D | 실시간 도로 노면 관제",
    description: "노면 신호, 충격 이벤트와 시민 현장 제보를 한 지도에서 확인하는 공무원용 관제 대시보드",
    type: "website",
    images: [{ url: "/og.png", width: 1536, height: 1024, alt: "R2D 실시간 도로 노면 관제" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "R2D | 실시간 도로 노면 관제",
    description: "센서와 시민 현장 제보를 결합한 공무원용 도로 상태 관제 대시보드",
    images: ["/og.png"],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ko">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body>
    </html>
  );
}
