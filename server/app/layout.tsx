import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Saga",
  description:
    "Download Saga for macOS — track books, reading progress, and reviews synced across your devices.",
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
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
