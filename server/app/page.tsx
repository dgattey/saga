import { getMacOSRelease } from "@/lib/macos-release";
import { PreviewShowcase } from "./PreviewShowcase";
import styles from "./page.module.css";

export const revalidate = 60;

export default async function HomePage() {
  const release = await getMacOSRelease();

  return (
    <main className={styles.page}>
      <div className={styles.heroUnit}>
        <div className={styles.photoColumn}>
          <PreviewShowcase />
        </div>

        <div className={styles.downloadColumn}>
          <div className={styles.headingBlock}>
            <div className={styles.brandRow}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/icon-192.png"
                alt="Saga app icon — open hardcover book with a monstera leaf bookmark"
                width={60}
                height={60}
                className={styles.appIcon}
              />
              <span className={styles.badge}>macOS · iOS · Apple Silicon</span>
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
                    <path d="M8 1.5a3.5 3.5 0 0 0-3.5 3.5v2H3.75A1.75 1.75 0 0 0 2 8.75v4.5C2 14.216 2.784 15 3.75 15h8.5A1.75 1.75 0 0 0 14 13.25v-4.5A1.75 1.75 0 0 0 12.25 7H11.5V5A3.5 3.5 0 0 0 8 1.5ZM6 5a2 2 0 1 1 4 0v2H6V5Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>Private Notes & Reviews</strong>
              </div>
              <p className={styles.featureBody}>
                Editorial book layout with public reviews alongside a locked{" "}
                <code>Private Notes</code> section that stays in Saga.
              </p>
            </li>

            <li className={styles.featureCard}>
              <div className={styles.featureHeader}>
                <span className={styles.featureIcon} aria-hidden="true">
                  <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
                    <path d="M11.5 7a4.5 4.5 0 1 1-9 0 4.5 4.5 0 0 1 9 0Zm-.82 4.74a6 6 0 1 1 1.06-1.06l2.79 2.79a.75.75 0 1 1-1.06 1.06l-2.79-2.79Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>⌘K Spotlight Search</strong>
              </div>
              <p className={styles.featureBody}>
                Instant search across titles, reviews, and notes with <code>Has notes</code>,
                status, star rating, and year filter tokens.
              </p>
            </li>

            <li className={styles.featureCard}>
              <div className={styles.featureHeader}>
                <span className={styles.featureIcon} aria-hidden="true">
                  <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
                    <path d="M4.25 2A1.75 1.75 0 0 0 2.5 3.75v9.81a.75.75 0 0 0 1.22.58L8 10.72l4.28 3.42a.75.75 0 0 0 1.22-.58V3.75A1.75 1.75 0 0 0 11.75 2h-7.5Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>Currently Reading Bar</strong>
              </div>
              <p className={styles.featureBody}>
                Crisp frosted floating bar pinned to the sidebar on macOS and iOS for one-click
                access to your active book.
              </p>
            </li>

            <li className={styles.featureCard}>
              <div className={styles.featureHeader}>
                <span className={styles.featureIcon} aria-hidden="true">
                  <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
                    <path d="M2 3.75A.75.75 0 0 1 2.75 3h6.5a.75.75 0 0 1 0 1.5h-6.5A.75.75 0 0 1 2 3.75Zm9.5 0a1.75 1.75 0 1 1 3.5 0 1.75 1.75 0 0 1-3.5 0ZM1.25 8a1.75 1.75 0 1 1 3.5 0 1.75 1.75 0 0 1-3.5 0ZM6.75 7.25a.75.75 0 0 0 0 1.5h6.5a.75.75 0 0 0 0-1.5h-6.5ZM2 12.25a.75.75 0 0 1 .75-.75h6.5a.75.75 0 0 1 0 1.5h-6.5a.75.75 0 0 1-.75-.75Zm9.5 0a1.75 1.75 0 1 1 3.5 0 1.75 1.75 0 0 1-3.5 0Z" />
                  </svg>
                </span>
                <strong className={styles.featureTitle}>6-Pane Native Settings</strong>
              </div>
              <p className={styles.featureBody}>
                Categorized <code>General</code>, <code>Sync</code>, <code>Storage</code>,{" "}
                <code>Animations</code>, <code>Credits</code>, and <code>About</code> panes with
                stepped cache sliders.
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
