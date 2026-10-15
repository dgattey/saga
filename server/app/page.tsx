import { getMacOSRelease } from "@/lib/macos-release";
import styles from "./page.module.css";

export const revalidate = 60;

export default async function HomePage() {
  const release = await getMacOSRelease();

  return (
    <main className={styles.page}>
      <div className={styles.heroUnit}>
        <div className={styles.photoColumn}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/saga-preview.png"
            alt="Saga book library and reading tracker on macOS"
            width={2000}
            height={1200}
            fetchPriority="high"
            className={styles.windowPreview}
          />
        </div>

        <div className={styles.downloadColumn}>
          <div className={styles.headingBlock}>
            <div className={styles.brandRow}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/app-icon.png"
                alt=""
                width={56}
                height={56}
                className={styles.appIcon}
              />
              <span className={styles.badge}>macOS 15+ · Apple Silicon</span>
            </div>
            <h1 className={styles.title}>Welcome to Saga</h1>
            <p className={styles.subtitle}>
              Your personal reading log for macOS and iOS — track books, reading status, star
              ratings, and notes synced with Contentful and Goodreads.
            </p>
          </div>

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
