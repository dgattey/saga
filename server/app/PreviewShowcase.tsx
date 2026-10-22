"use client";

import { useState } from "react";
import styles from "./page.module.css";

export type PreviewScreen = {
  id: string;
  label: string;
  caption: string;
  src: string;
  alt: string;
  width: number;
  height: number;
};

export const PREVIEW_SCREENS: PreviewScreen[] = [
  {
    id: "editorial",
    label: "Book & Private Notes",
    caption: "Editorial detail view · lock.fill Private Notes · Currently reading bar",
    src: "/saga-preview.png",
    alt: "Saga editorial book detail view showing Review, locked Private Notes, and the floating Currently reading bar in the sidebar",
    width: 1600,
    height: 1067,
  },
  {
    id: "spotlight",
    label: "⌘K Spotlight Search",
    caption: "Has notes token · private note matches · highlighted excerpts",
    src: "/saga-search-preview.png",
    alt: "Saga ⌘K Spotlight search overlay filtering by Has notes token with highlighted private note excerpts",
    width: 1600,
    height: 1067,
  },
  {
    id: "settings-storage",
    label: "6-Pane Settings",
    caption: "General · Sync · Storage · Animations · Credits · About",
    src: "/saga-settings-storage-preview.png",
    alt: "Saga 6-pane Tuneful-style Settings window showing Storage cache limit sliders and Clear Caches",
    width: 1280,
    height: 1100,
  },
  {
    id: "settings-about",
    label: "About & Credits",
    caption: "Open-book & monstera icon · version badge · quick links",
    src: "/saga-settings-about-preview.png",
    alt: "Saga Settings About pane showing the open hardcover book and monstera leaf app icon hero card",
    width: 1280,
    height: 1100,
  },
];

export function PreviewShowcase() {
  const [activeId, setActiveId] = useState<string>(PREVIEW_SCREENS[0].id);
  const active = PREVIEW_SCREENS.find((item) => item.id === activeId) ?? PREVIEW_SCREENS[0];

  return (
    <div className={styles.showcase}>
      <div className={styles.stageFrame}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          key={active.src}
          src={active.src}
          alt={active.alt}
          width={active.width}
          height={active.height}
          fetchPriority="high"
          className={styles.windowPreview}
        />
      </div>

      <div className={styles.previewStrip} role="tablist" aria-label="Saga app screens">
        {PREVIEW_SCREENS.map((screen) => {
          const isSelected = screen.id === active.id;
          return (
            <button
              key={screen.id}
              type="button"
              role="tab"
              aria-selected={isSelected}
              onClick={() => setActiveId(screen.id)}
              className={`${styles.previewThumbButton} ${isSelected ? styles.previewThumbActive : ""}`}
            >
              <span className={styles.previewThumbMedia}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={screen.src}
                  alt=""
                  width={screen.width}
                  height={screen.height}
                  decoding="async"
                  className={styles.previewThumbImg}
                />
              </span>
              <span className={styles.previewThumbLabel}>{screen.label}</span>
              <span className={styles.previewThumbCaption}>{screen.caption}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
