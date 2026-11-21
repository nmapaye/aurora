import { useId, useState } from "react";
import {
  KSS_LABEL,
  KSS_OPTIONS,
  kssRating,
  parseKssSelection,
  type KssValue,
} from "./kss";

const githubUrl = "https://github.com/nmapaye/aurora";

// Waitlist: a plain email link. No form backend, trackers or ads.
const waitlistEmail = "nmapaye@outlook.com";
const waitlistBody = [
  "Please add me to the Aurora waitlist.",
  "",
  "Device (iPhone / iPad / both):",
  "",
  "Please don't include health information.",
].join("\r\n");
export const waitlistMailto = `mailto:${waitlistEmail}?subject=${encodeURIComponent(
  "Aurora waitlist",
)}&body=${encodeURIComponent(waitlistBody)}`;

const features = [
  {
    title: "Save and Undo",
    body: "Log caffeine and sleep. Undo a saved entry from its receipt.",
  },
  {
    title: "Clearly labeled",
    body: "Records, estimates and reaction-test results, each labeled.",
  },
  {
    title: "Apple Health, optional",
    body: "Each Health permission is a separate choice. Imported records stay read-only.",
  },
  {
    title: "Calendar, with approval",
    body: "Calendar changes happen only after you approve them.",
  },
  {
    title: "Reaction test",
    body: "A short reaction test that records your reaction times.",
  },
  {
    title: "Exports and reminders",
    body: "Export anytime. Reminders stay off until you turn them on.",
  },
];

type SleepState = "missing" | "recorded";
type CaffeineState = "missing" | "recorded";

export default function App() {
  const [kss, setKss] = useState<KssValue | null>(null);
  const kssInputId = useId();
  const kssHelpId = useId();
  const [sleep, setSleep] = useState<SleepState>("missing");
  const [caffeine, setCaffeine] = useState<CaffeineState>("missing");

  return (
    <div className="site-shell">
      <a className="skip-link" href="#main">
        Skip to content
      </a>

      <header className="topbar">
        <a className="brand" href="#top">
          <img
            className="brand-mark"
            src="aurora-mark.svg"
            alt=""
            aria-hidden="true"
          />
          <span className="brand-copy">
            <strong>Aurora</strong>
            <span>By Nathaniel Mapaye</span>
          </span>
        </a>
        <nav className="topnav" aria-label="Primary">
          <a href="#features">Features</a>
          <a href="#preview">Preview</a>
          <a href="#release">Release</a>
          <a href="privacy.html">Privacy</a>
          <a
            className="nav-cta"
            href={githubUrl}
            target="_blank"
            rel="noreferrer"
          >
            GitHub
          </a>
        </nav>
      </header>

      <main id="main">
        <section id="top" className="hero" aria-labelledby="hero-title">
          <div className="hero-copy">
            <h1 id="hero-title">
              Understand
              <br />
              your energy.
            </h1>
            <p className="hero-text">
              Log caffeine and sleep. See what is recorded and what is estimated. Your logs stay on your device.
            </p>
            <div className="hero-actions">
              <a className="button button-primary" href={waitlistMailto}>
                Join the waitlist <Arrow />
              </a>
              <a className="button button-secondary" href="#preview">
                Try the preview
              </a>
            </div>
          </div>
          <figure className="hero-product">
            <div className="product-frame">
              <div className="product-title">
                <img src="aurora-mark.svg" alt="" width="30" height="30" />
                <span>Aurora</span>
                <span className="product-time">Today</span>
              </div>
              <EnergyCard
                sleep="recorded"
                caffeine="recorded"
                kss={kss}
                announce={false}
              />
              <div className="product-footer">
                <span>Sleep</span>
                <span>Caffeine</span>
                <span>Reaction test</span>
              </div>
            </div>
            <figcaption>
              Interactive illustration: sample sleep and caffeine, your own KSS
              rating. Nothing is saved or sent.
            </figcaption>
          </figure>
          <div className="hero-meta">
            <span>Coming soon for iPhone &amp; iPad</span>
            <span>Native app. On-device.</span>
          </div>
        </section>

        <div className="statement">
          <p>
            One honest record
            <br />
            <span>at a time.</span>
          </p>
          <a href="#features" aria-label="Explore Aurora features">
            <Arrow direction="down" />
          </a>
        </div>

        <section
          id="features"
          className="section"
          aria-labelledby="features-title"
        >
          <div className="section-heading">
            <h2 id="features-title">
              Clear evidence.
              <br />
              You stay in control.
            </h2>
          </div>
          <ul className="feature-grid">
            {features.map((item) => (
              <li key={item.title} className="feature-row">
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </li>
            ))}
          </ul>
        </section>

        <section
          id="preview"
          className="section preview-section"
          aria-labelledby="preview-title"
        >
          <div className="section-heading">
            <h2 id="preview-title">
              Missing is
              <br />
              never zero.
            </h2>
            <p>
              Rate how sleepy you feel. Explore sleep and caffeine records
              alongside your check-in.
            </p>
          </div>

          <div className="preview-layout">
            <fieldset className="card preview-controls">
              <legend>Explore your day</legend>
              <div className="kss-field">
                <label htmlFor={kssInputId}>Your sleepiness rating</label>
                <p id={kssHelpId} className="control-help">
                  Think about the last five minutes. Higher means sleepier.
                </p>
                <select
                  id={kssInputId}
                  aria-describedby={kssHelpId}
                  value={kss ?? ""}
                  onChange={(event) =>
                    setKss(parseKssSelection(event.target.value))
                  }
                >
                  <option value="">Choose your rating</option>
                  {KSS_OPTIONS.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.value} — {option.interpretation}
                    </option>
                  ))}
                </select>
              </div>
              <ToggleRow
                label="Last night's sleep"
                checked={sleep === "recorded"}
                onChange={(on) => setSleep(on ? "recorded" : "missing")}
                onText="7 h 10 m"
              />
              <ToggleRow
                label="Coffee this morning"
                checked={caffeine === "recorded"}
                onChange={(on) => setCaffeine(on ? "recorded" : "missing")}
                onText="95 mg"
              />
              <button
                type="button"
                className="button button-secondary full-width"
                onClick={() => {
                  setSleep("missing");
                  setCaffeine("missing");
                  setKss(null);
                }}
              >
                Clear preview
              </button>
            </fieldset>

            <EnergyCard sleep={sleep} caffeine={caffeine} kss={kss} />
          </div>
          <details className="preview-notes">
            <summary>About KSS and this preview</summary>
            <p>
              The Karolinska Sleepiness Scale (1–9) records how sleepy you feel.
              It is not calculated from sleep or caffeine, and it does not
              measure performance or diagnose a condition. This demo does not
              run Aurora’s model or connect to Apple Health. Aurora does not
              prescribe caffeine or sleep schedules.
            </p>
            <p>
              Scale labels: Åkerstedt Miley, Kecklund &amp; Åkerstedt (2016),{" "}
              <a href="https://doi.org/10.1007/s41105-016-0048-8">
                KSS versions A and B
              </a>
              ,{" "}
              <a href="https://creativecommons.org/licenses/by/4.0/">
                CC BY 4.0
              </a>
              .
            </p>
          </details>
        </section>

        <section
          id="release"
          className="section release-section"
          aria-labelledby="release-title"
        >
          <div className="section-heading">
            <h2 id="release-title">
              In the making.
              <br />
              Not released yet.
            </h2>
          </div>
          <div className="release-grid">
            <article className="release-card">
              <h3>Planned</h3>
              <ul>
                <li>Paid upfront, US$4.99, on the App Store</li>
                <li>iPhone and iPad, iOS 17 or later</li>
                <li>A free TestFlight beta before release</li>
              </ul>
            </article>
            <article className="release-card" id="waitlist">
              <h3>Waitlist</h3>
              <p>Get an email when the free beta or the App Store version is ready.</p>
              <a className="button button-primary" href={waitlistMailto}>
                Join the waitlist <Arrow />
              </a>
              <a className="text-link" href="privacy.html#waitlist">
                How your email is used
              </a>
            </article>
            <article className="release-card">
              <h3>Private by design</h3>
              <p>
                Your records stay on your device. No account, no analytics SDK,
                no cloud AI.
              </p>
              <a className="text-link" href="privacy.html">
                Read the privacy policy
              </a>
            </article>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <a className="footer-brand" href="https://nmapaye.com">
          A product by <strong>Nathaniel Mapaye</strong>
          <Arrow />
        </a>
        <p className="footer-note">Informational only. Not medical advice.</p>
        <nav aria-label="Footer">
          <a href="privacy.html">Privacy Policy</a>
          <a href="terms.html">Terms</a>
          <a href="support.html">Support</a>
          <a href={githubUrl} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </nav>
      </footer>
    </div>
  );
}

function ToggleRow({
  label,
  checked,
  onChange,
  onText,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  onText: string;
}) {
  return (
    <label className="toggle-row">
      <span className="toggle-copy">
        <span>{label}</span>
        <small>{checked ? onText : "No record"}</small>
      </span>
      <input
        type="checkbox"
        aria-label={label}
        role="switch"
        className="toggle"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
      />
    </label>
  );
}

export function EnergyCard({
  sleep,
  caffeine,
  kss,
  announce = true,
}: {
  sleep: SleepState;
  caffeine: CaffeineState;
  kss: KssValue | null;
  announce?: boolean;
}) {
  const titleId = useId();
  const hasSleep = sleep === "recorded";
  const hasCaffeine = caffeine === "recorded";
  const rating = kssRating(kss);

  return (
    <article
      className="card energy-card"
      aria-labelledby={titleId}
      aria-live={announce ? "polite" : undefined}
    >
      <div className="energy-card-header">
        <h3 id={titleId}>Energy</h3>
        <span className="badge">Demo</span>
      </div>

      <div className="energy-lead">
        <span className="metric-label">{KSS_LABEL}</span>
        {rating ? (
          <>
            <strong className="hero-value">
              {rating.value}
              <span className="unit"> / 9</span>
            </strong>
            <p className="evidence">{rating.interpretation}</p>
          </>
        ) : (
          <>
            <strong className="hero-value muted">Not rated</strong>
            <p className="evidence">
              Choose your sleepiness rating in the preview.
            </p>
          </>
        )}
      </div>

      <dl className="metric-list">
        <div className="metric-row">
          <dt>Sleep, last 24 h</dt>
          <dd className={hasSleep ? undefined : "muted"}>
            {hasSleep ? "7 h 10 m" : "No record"}
          </dd>
        </div>
        <div className="metric-row">
          <dt>Caffeine today</dt>
          <dd className={hasCaffeine ? undefined : "muted"}>
            {hasCaffeine ? "95 mg" : "No record"}
          </dd>
        </div>
      </dl>
    </article>
  );
}

function Arrow({ direction = "right" }: { direction?: "right" | "down" }) {
  return (
    <svg
      className={`arrow arrow-${direction}`}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      aria-hidden="true"
    >
      <path d="M4 12h15M12 5l7 7-7 7" />
    </svg>
  );
}
