import { useState } from 'react';

const githubUrl = 'https://github.com/nmapaye/aurora';

const features = [
  {
    title: 'Log with Save and Undo',
    body: 'Caffeine and manual sleep entries are drafts until you tap Save, and a saved entry can be undone from its receipt.',
  },
  {
    title: 'Evidence, not guesses',
    body: 'Cards separate missing records from estimates. No record is never shown as zero, and estimates say they are estimates.',
  },
  {
    title: 'Apple Health, your choice',
    body: 'Optionally read sleep and caffeine from Apple Health, and add caffeine you save in Aurora. Each is a separate choice. Imported records stay read-only.',
  },
  {
    title: 'Calendar edits you approve',
    body: 'Review selected Apple and Google calendars. Each change needs your fresh, explicit approval before it is made.',
  },
  {
    title: 'Reaction test',
    body: 'A short on-device reaction test gives a measured result alongside your records.',
  },
  {
    title: 'Exports and reminders',
    body: 'Export your records when you want them. Reminders are off until you opt in.',
  },
];

type SleepState = 'missing' | 'recorded';
type CaffeineState = 'missing' | 'recorded';

export default function App() {
  const [sleep, setSleep] = useState<SleepState>('missing');
  const [caffeine, setCaffeine] = useState<CaffeineState>('missing');

  return (
    <div className="site-shell">
      <a className="skip-link" href="#main">
        Skip to content
      </a>

      <header className="topbar">
        <a className="brand" href="#top">
          <img className="brand-mark" src="aurora-mark.svg" alt="" aria-hidden="true" />
          <span className="brand-copy">
            <strong>Aurora</strong>
            <span>Energy and daily rhythm</span>
          </span>
        </a>
        <nav className="topnav" aria-label="Primary">
          <a href="#features">Features</a>
          <a href="#preview">Preview</a>
          <a href="#release">Release</a>
          <a href="privacy.html">Privacy</a>
          <a className="nav-cta" href={githubUrl} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </nav>
      </header>

      <main id="main">
        <section id="top" className="hero section">
          <div className="hero-copy">
            <div className="hero-identity" aria-hidden="true" />
            <p className="eyebrow">Coming soon for iPhone and iPad</p>
            <h1>Understand your energy, one honest record at a time.</h1>
            <p className="hero-text">
              Aurora is a native assistant for recording sleep and caffeine, reviewing clearly labelled
              estimates and measured reaction tests, and keeping selected commitments in view.
            </p>
            <div className="hero-actions">
              <a className="button button-primary" href="#preview">
                Try the synthetic preview
              </a>
              <a className="button button-secondary" href="#release">
                Release status
              </a>
            </div>
            <p className="hero-note">
              Aurora does not diagnose fatigue or prescribe caffeine or sleep schedules.
            </p>
          </div>
        </section>

        <section id="features" className="section" aria-labelledby="features-title">
          <div className="section-heading">
            <p className="eyebrow">In the app</p>
            <h2 id="features-title">Finite cards. Clear evidence. You stay in control.</h2>
          </div>
          <ul className="feature-grid">
            {features.map((item) => (
              <li key={item.title} className="card feature-card">
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </li>
            ))}
          </ul>
        </section>

        <section id="preview" className="section" aria-labelledby="preview-title">
          <div className="section-heading">
            <p className="eyebrow">Synthetic preview</p>
            <h2 id="preview-title">See how an energy card treats missing records.</h2>
            <p>
              This is an illustration built for this page. It uses made-up values held only in your
              browser tab, sends nothing anywhere, and does not run Aurora's model.
            </p>
          </div>

          <div className="preview-layout">
            <fieldset className="card preview-controls">
              <legend>Synthetic records</legend>
              <ToggleRow
                label="Last night's sleep"
                checked={sleep === 'recorded'}
                onChange={(on) => setSleep(on ? 'recorded' : 'missing')}
                onText="7 h 10 m"
              />
              <ToggleRow
                label="Coffee this morning"
                checked={caffeine === 'recorded'}
                onChange={(on) => setCaffeine(on ? 'recorded' : 'missing')}
                onText="95 mg"
              />
              <button
                type="button"
                className="button button-quiet full-width"
                onClick={() => {
                  setSleep('missing');
                  setCaffeine('missing');
                }}
              >
                Clear preview
              </button>
            </fieldset>

            <EnergyCard sleep={sleep} caffeine={caffeine} />
          </div>
        </section>

        <section id="release" className="section" aria-labelledby="release-title">
          <div className="section-heading">
            <p className="eyebrow">Release status</p>
            <h2 id="release-title">Not released yet.</h2>
          </div>
          <div className="release-grid">
            <article className="card release-card">
              <h3>Planned</h3>
              <ul>
                <li>Paid upfront, US$4.99, on the App Store</li>
                <li>iPhone and iPad, iOS 17 or later</li>
                <li>A free TestFlight beta before release</li>
              </ul>
            </article>
            <article className="card release-card">
              <h3>Not open yet</h3>
              <p>
                TestFlight and the App Store listing are not available. There is no download or
                sign-up on this page.
              </p>
            </article>
            <article className="card release-card">
              <h3>Private by design</h3>
              <p>
                Aurora classifies requests on device. No cloud inference, AI keys, analytics SDK, or
                cross-device health and conversation sync.
              </p>
              <a className="text-link" href="privacy.html">
                Read the privacy policy
              </a>
            </article>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <a href="privacy.html">Privacy Policy</a>
        <a href="support.html">Support</a>
        <a href={githubUrl} target="_blank" rel="noreferrer">
          GitHub
        </a>
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
        <small>{checked ? `Synthetic: ${onText}` : 'No record'}</small>
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

function EnergyCard({ sleep, caffeine }: { sleep: SleepState; caffeine: CaffeineState }) {
  const hasSleep = sleep === 'recorded';
  const hasCaffeine = caffeine === 'recorded';
  const illustrativeScore = hasCaffeine ? 74 : 68;

  return (
    <article className="card energy-card" aria-labelledby="energy-card-title" aria-live="polite">
      <div className="energy-card-header">
        <h3 id="energy-card-title">Energy</h3>
        <span className="badge">
          <span aria-hidden="true">◆</span> Synthetic preview
        </span>
      </div>

      <div className="energy-lead">
        <span className="metric-label">Estimated alertness</span>
        {hasSleep ? (
          <>
            <strong className="hero-value">
              {illustrativeScore}
              <span className="unit"> / 100</span>
            </strong>
            <p className="evidence">
              Illustrative number for this page. In Aurora, this is an estimate, not a measurement.
            </p>
          </>
        ) : (
          <>
            <strong className="hero-value muted">Unavailable</strong>
            <p className="evidence">No sleep is recorded in the last 24 hours.</p>
          </>
        )}
      </div>

      <dl className="metric-list">
        <div className="metric-row">
          <dt>Sleep, last 24 h</dt>
          <dd className={hasSleep ? undefined : 'muted'}>{hasSleep ? '7 h 10 m' : 'No record'}</dd>
        </div>
        <div className="metric-row">
          <dt>Caffeine today</dt>
          <dd className={hasCaffeine ? undefined : 'muted'}>{hasCaffeine ? '95 mg' : 'No record'}</dd>
        </div>
      </dl>

      <p className="source">
        {hasSleep || hasCaffeine
          ? 'Source: synthetic values on this page only.'
          : 'Missing records are shown as missing, never as zero.'}
      </p>
    </article>
  );
}
