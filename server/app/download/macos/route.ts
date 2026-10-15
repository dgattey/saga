import { getMacOSRelease } from "@/lib/macos-release";
import { NextResponse } from "next/server";

export const revalidate = 60;

export async function GET() {
  const release = await getMacOSRelease();
  if (!release) {
    return NextResponse.json({ error: "No macOS release is published yet." }, { status: 404 });
  }
  if (!release.downloadReady) {
    return NextResponse.json(
      { error: "Release is still deploying. Try again in a minute." },
      { status: 503, headers: { "Retry-After": "60" } },
    );
  }
  const location = release.downloadUrl.startsWith("https://saga.gattey.com/")
    ? new URL(release.downloadUrl).pathname
    : release.downloadUrl;
  return new Response(null, {
    status: 302,
    headers: { Location: location },
  });
}
