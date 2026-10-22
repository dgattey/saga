import { getMacOSRelease } from "@/lib/macos-release";
import styles from "./page.module.css";

export const revalidate = 60;

export default async function HomePage() {
  const release = await getMacOSRelease();

  return (
    <main className={styles.page}>
      <div className={styles.heroUnit}>
        <div className={styles.photoColumn}>
          <picture className={styles.previewPicture}>
            <source media="(prefers-color-scheme: light)" srcSet="/saga-preview-light.png" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/saga-preview.png"
              alt="Saga book library and reading tracker on macOS showing editorial reviews, private notes, and the Currently reading sidebar card"
              width={1600}
              height={1067}
              fetchPriority="high"
              className={styles.windowPreview}
            />
          </picture>
        </div>

        <div className={styles.downloadColumn}>
          <div className={styles.headingBlock}>
            <div className={styles.brandRow}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/icon-192.png"
                alt="Saga app icon — open hardcover book with a monstera leaf bookmark"
                width={56}
                height={56}
                className={styles.appIcon}
              />
              <span className={styles.badge}>macOS 15+ · iOS · Apple Silicon</span>
            </div>
            <h1 className={styles.title}>Welcome to Saga</h1>
            <p className={styles.subtitle}>
              Your personal reading log for macOS and iOS — track books, reading status, star
              ratings, public reviews, and private notes synced with Contentful and Goodreads.
            </p>
          </div>

          <ul className={styles.featureGrid} aria-label="Key features">
            <li className={styles.featureCard}>
              <div className={styles.featureHeader}>
                <span className={styles.featureIcon} aria-hidden="true">
                  <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
                    <path d="M4.25 2A1.75 1.75 0 0 0 2.5 3.75v9.81a.75.75 0 0 0 1.22.58L8 10.72l4.28 3.42a.75.75 0 0 0 1.22-.58V3.75A1.75 1.75 0 0 0 11.75 2h-7.5Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>Books & Active Reading</strong>
              </div>
              <p className={styles.featureBody}>
                Track what you’re reading, finished dates, and star ratings with a pinned{" "}
                <em>Currently reading</em> card always one click away.
              </p>
            </li>

            <li className={styles.featureCard}>
              <div className={styles.featureHeader}>
                <span className={styles.featureIcon} aria-hidden="true">
                  <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
                    <path d="M8 1.5a3.5 3.5 0 0 0-3.5 3.5v2H3.75A1.75 1.75 0 0 0 2 8.75v4.5C2 14.216 2.784 15 3.75 15h8.5A1.75 1.75 0 0 0 14 13.25v-4.5A1.75 1.75 0 0 0 12.25 7H11.5V5A3.5 3.5 0 0 0 8 1.5ZM6 5a2 2 0 1 1 4 0v2H6V5Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>Private Notes & Reviews</strong>
              </div>
              <p className={styles.featureBody}>
                Editorial book pages pair public reviews with a locked <code>Private Notes</code>{" "}
                section for personal quotes and marginalia.
              </p>
            </li>

            <li className={styles.featureCard}>
              <div className={styles.featureHeader}>
                <span className={styles.featureIcon} aria-hidden="true">
                  <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
                    <path d="M11.5 7a4.5 4.5 0 1 1-9 0 4.5 4.5 0 0 1 9 0Zm-.82 4.74a6 6 0 1 1 1.06-1.06l2.79 2.79a.75.75 0 1 1-1.06 1.06l-2.79-2.79Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>Instant ⌘K Search</strong>
              </div>
              <p className={styles.featureBody}>
                Jump to any book or search across full reviews and private notes with{" "}
                <code>Has notes</code>, status, rating, and year tokens.
              </p>
            </li>

            <li className={styles.featureCard}>
              <div className={styles.featureHeader}>
                <span className={styles.featureIcon} aria-hidden="true">
                  <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
                    <path d="M8 2.5a5.487 5.487 0 0 0-4.131 1.869l1.204 1.204A.25.25 0 0 1 4.896 6H1.25A.25.25 0 0 1 1 5.75V2.104a.25.25 0 0 1 .427-.177l1.38 1.38A7.002 7.002 0 0 1 14.95 7.16a.75.75 0 0 1-1.49.178A5.5 5.5 0 0 0 8 2.5ZM1.705 8.005a.75.75 0 0 1 .834.656 5.5 5.5 0 0 0 9.592 2.97l-1.204-1.204a.25.25 0 0 1 .177-.427h3.646a.25.25 0 0 1 .25.25v3.646a.25.25 0 0 1-.427.177l-1.38-1.38A7.002 7.002 0 0 1 1.05 8.84a.75.75 0 0 1 .656-.835Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>Cloud & Goodreads Sync</strong>
              </div>
              <p className={styles.featureBody}>
                Two-way Contentful sync and automatic Goodreads shelf imports keep your library up
                to date across macOS and iOS.
              </p>
            </li>
          </ul>

          {release ? (
            <div className={styles.downloadActions}>
              <a className={styles.downloadButton} href="/download/macos">
                Download for macOS{release.version ? ` (v${release.version})` : ""}
              </a>
              {!release.downloadReady ? (
                <p className={styles.hint}>
                  That version is still deploying. Refresh in a minute if download fails.
                </p>
              ) : null}

              <details className={styles.manualApproval}>
                <summary>First time on this Mac? macOS may block the app</summary>
                <div className={styles.manualApprovalBody}>
                  <p className={styles.finePrint}>
                    After you download and try to open Saga once, approve it in System Settings.
                  </p>
                  <ol className={styles.manualSteps}>
                    <li>
                      Try opening <strong>Saga</strong> from Applications so macOS records the
                      block.
                    </li>
                    <li>
                      Open <strong>System Settings → Privacy & Security</strong>.
                    </li>
                    <li>
                      Under Security, click <strong>Open Anyway</strong> next to the Saga message.
                    </li>
                    <li>Open the app again.</li>
                  </ol>
                  <p className={styles.finePrint}>
                    On an MDM-managed Mac where <strong>Open Anyway</strong> is disabled by
                    device policy, clear the download quarantine attribute in Terminal:
                  </p>
                  <pre className={styles.commandSnippet}>
                    <code>xattr -cr /Applications/Saga.app</code>
                  </pre>
                  <figure className={styles.manualApprovalFigure}>
                    <div className={styles.manualApprovalMedia}>
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src="/macos-open-anyway.png"
                        alt="Privacy and Security settings showing the app was blocked with an Open Anyway button"
                        width={1024}
                        height={903}
                        decoding="async"
                      />
                    </div>
                    <figcaption>
                      Open Anyway appears after you try to launch the app once.
                    </figcaption>
                  </figure>
                </div>
              </details>
            </div>
          ) : (
            <p className={styles.noRelease}>
              A macOS build is not published yet. Check back after the next release.
            </p>
          )}
        </div>
      </div>
    </main>
  );
}
