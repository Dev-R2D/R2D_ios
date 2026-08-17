export async function GET() {
  return Response.json(
    {
      kakaoJavascriptKey: process.env.KAKAO_JAVASCRIPT_KEY ?? "",
      vworldApiKey: process.env.VWORLD_API_KEY ?? "",
    },
    {
      headers: {
        "Cache-Control": "no-store, max-age=0",
      },
    },
  );
}
