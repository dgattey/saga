import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://saga.gattey.com"),
  title: "Saga",
  description:
    "Download Saga for macOS — track books, editorial reviews, private notes, ⌘K Spotlight search, and reading progress synced across your devices.",
  manifest: "/site.webmanifest",
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "16x16 32x32 48x48" },
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/favicon-16x16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicon-32x32.png", sizes: "32x32", type: "image/png" },
      { url: "/favicon-64x64.png", sizes: "64x64", type: "image/png" },
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
  openGraph: {
    title: "Saga — Personal Reading Log for macOS & iOS",
    description:
      "Track books, reading status, star ratings, public reviews, and private notes with ⌘K Spotlight search and Contentful + Goodreads sync.",
    url: "https://saga.gattey.com",
    siteName: "Saga",
    images: [
      {
        url: "/opengraph-image.png",
        width: 1200,
        height: 630,
        alt: "Saga book library, Private Notes, and reading tracker on macOS",
      },
    ],
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Saga — Personal Reading Log for macOS & iOS",
    description:
      "Track books, reading status, star ratings, public reviews, and private notes with ⌘K Spotlight search and Contentful + Goodreads sync.",
    images: ["/opengraph-image.png"],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="preload" href="/saga-preview.png" as="image" />
      </head>
      <body>{children}</body>
    </html>
  );
}
