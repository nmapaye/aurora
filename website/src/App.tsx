import { useMemo, useState } from 'react';

import {
  demoScenarios,
  siteSections,
  type DemoMode,
  type DemoScenario,
} from './demoData';

type DemoScreen = 'home' | 'sleep' | 'insights' | 'vigilance';

const githubUrl = 'https://github.com/nmapaye/aurora';

export default function App() {
  const [mode, setMode] = useState<DemoMode>('healthkit');
  const [screen, setScreen] = useState<DemoScreen>('home');
  const [vigilanceStep, setVigilanceStep] = useState(0);

  const scenario = demoScenarios[mode];
  const vigilanceTimeline = useMemo(
    () => [
      'Get ready. Wait for the screen to change, then respond as quickly as you can.',
      'The cue appears and the user taps the active area right away.',
      `Aurora saves the result as ${scenario.latestVigilance.score} ${scenario.latestVigilance.rating}, with a median reaction time of ${scenario.latestVigilance.medianReactionMs} ms.`,
    ],
    [scenario]
  );

  return (
    <div className="site-shell">
      <header className="topbar">
        <a className="brand" href="#top">
          <span className="brand-mark" aria-hidden="true">
            A
          </span>
          <span className="brand-copy">
            <strong>Aurora</strong>
            <span>sleep-aware caffeine guidance</span>
          </span>
        </a>
        <nav className="topnav">
          <a href="#capabilities">What it does</a>
          <a href="#demo">Demo</a>
          <a href="#proof">Proof</a>
          <a className="nav-cta" href={githubUrl} target="_blank" rel="noreferrer">
            View on GitHub
          </a>
        </nav>
      </header>

      <main id="top">
        <section className="hero section">
          <div className="hero-copy">
            <div className="eyebrow">Sleep-aware caffeine guidance</div>
            <h1>Track intake, protect sleep, and measure attentiveness in one calm daily flow.</h1>
            <p className="hero-text">
              Aurora helps people understand how caffeine fits into the rest of the day.
              You can log intake quickly, see a clearer cutoff, and run a short vigilance test
              to track how alert you feel over time.
            </p>
            <div className="hero-actions">
              <a className="button button-primary" href="#demo">
                Try the interactive preview
              </a>
              <a className="button button-secondary" href={githubUrl} target="_blank" rel="noreferrer">
                Explore the project
              </a>
            </div>
            <div className="hero-points">
              <span>Health-backed sleep timing</span>
              <span>Quick manual logging</span>
              <span>On-device vigilance testing</span>
            </div>
          </div>

          <div className="hero-preview">
            <div className="device-frame">
              <DemoPhone
                scenario={scenario}
                screen={screen}
                vigilanceStep={vigilanceStep}
                vigilanceTimeline={vigilanceTimeline}
              />
            </div>
          </div>
        </section>

        <section id="capabilities" className="section">
          <div className="section-heading">
            <div className="eyebrow">What it does</div>
            <h2>Aurora keeps the signal clear when caffeine and sleep start to overlap.</h2>
          </div>
          <div className="capability-grid">
            {siteSections.map((item) => (
              <article key={item.title} className="capability-card">
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="demo" className="section demo-section">
          <div className="section-heading">
            <div className="eyebrow">Interactive preview</div>
            <h2>Move through the core Aurora experience in the browser.</h2>
            <p>
              Switch between a Health-connected view and a manual-only flow, then step through
              the screens that shape the everyday experience.
            </p>
          </div>

          <div className="demo-layout">
            <aside className="demo-controls">
              <div className="control-group">
                <span className="control-label">View</span>
                <div className="segmented">
                  {(['healthkit', 'manual'] as DemoMode[]).map((nextMode) => (
                    <button
                      key={nextMode}
                      type="button"
                      className={nextMode === mode ? 'segmented-button active' : 'segmented-button'}
                      onClick={() => {
                        setMode(nextMode);
                        setScreen('home');
                        setVigilanceStep(0);
                      }}
                    >
                      {demoScenarios[nextMode].modeLabel}
                    </button>
                  ))}
                </div>
              </div>

              <div className="control-group">
                <span className="control-label">Screens</span>
                <div className="screen-list">
                  {([
                    ['home', 'Home / Today'],
                    ['sleep', 'Sleep'],
                    ['insights', 'Insights'],
                    ['vigilance', 'Vigilance'],
                  ] as Array<[DemoScreen, string]>).map(([key, label]) => (
                    <button
                      key={key}
                      type="button"
                      className={key === screen ? 'screen-link active' : 'screen-link'}
                      onClick={() => setScreen(key)}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>

              <div className="control-group callout">
                <span className="control-label">Selected view</span>
                <strong>{scenario.modeLabel}</strong>
                <p>{scenario.heroLine}</p>
              </div>

              {screen === 'vigilance' ? (
                <div className="control-group">
                  <span className="control-label">Reaction flow</span>
                  <div className="screen-list">
                    {vigilanceTimeline.map((label, index) => (
                      <button
                        key={label}
                        type="button"
                        className={index === vigilanceStep ? 'screen-link active' : 'screen-link'}
                        onClick={() => setVigilanceStep(index)}
                      >
                        Step {index + 1}
                      </button>
                    ))}
                  </div>
                  <p className="small-copy">{vigilanceTimeline[vigilanceStep]}</p>
                </div>
              ) : null}
            </aside>

            <div className="demo-stage">
              <div className="device-frame large">
                <DemoPhone
                  scenario={scenario}
                  screen={screen}
                  vigilanceStep={vigilanceStep}
                  vigilanceTimeline={vigilanceTimeline}
                />
              </div>
            </div>
          </div>
        </section>

        <section id="proof" className="section">
          <div className="section-heading">
            <div className="eyebrow">Product context</div>
            <h2>Built around the current Aurora app, with the details kept honest.</h2>
          </div>
          <div className="proof-grid">
            <article className="proof-card">
              <h3>What Aurora already does</h3>
              <ul>
                <li>iPhone-first app with Health-backed sleep import</li>
                <li>Fast caffeine logging with quick-add and custom entries</li>
                <li>On-device vigilance testing with saved insights</li>
              </ul>
            </article>
            <article className="proof-card">
              <h3>What stays out of scope here</h3>
              <ul>
                <li>No cloud sync</li>
                <li>No Android health parity</li>
                <li>No App Store-style promises that do not exist yet</li>
              </ul>
            </article>
            <article className="proof-card">
              <h3>See how it is built</h3>
              <p>
                The interactive preview is meant to explain the product quickly. GitHub is there
                if you want the real code, current scope, and implementation details behind it.
              </p>
              <a className="button button-secondary full-width" href={githubUrl} target="_blank" rel="noreferrer">
                Open Aurora on GitHub
              </a>
            </article>
          </div>
        </section>
      </main>
    </div>
  );
}

function DemoPhone({
  scenario,
  screen,
  vigilanceStep,
  vigilanceTimeline,
}: {
  scenario: DemoScenario;
  screen: DemoScreen;
  vigilanceStep: number;
  vigilanceTimeline: string[];
}) {
  return (
    <div className="phone">
      <div className="phone-header">
        <div>
          <p className="phone-title">
            {screen === 'home'
              ? 'Today'
              : screen === 'sleep'
              ? 'Sleep'
              : screen === 'insights'
              ? 'Insights'
              : 'Vigilance'}
          </p>
          <p className="phone-subtitle">{scenario.modeLabel}</p>
        </div>
        <span className="status-pill">{scenario.sleepStatus}</span>
      </div>

      {screen === 'home' ? <HomePreview scenario={scenario} /> : null}
      {screen === 'sleep' ? <SleepPreview scenario={scenario} /> : null}
      {screen === 'insights' ? <InsightsPreview scenario={scenario} /> : null}
      {screen === 'vigilance' ? (
        <VigilancePreview
          scenario={scenario}
          vigilanceStep={vigilanceStep}
          vigilanceTimeline={vigilanceTimeline}
        />
      ) : null}

      <div className="tabbar">
        {['Home', 'Log', 'Sleep', 'Insights'].map((label) => (
          <span key={label} className={label.toLowerCase() === screen ? 'tab active' : 'tab'}>
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}

function HomePreview({ scenario }: { scenario: DemoScenario }) {
  return (
    <div className="phone-content">
      <div className="stats-grid">
        <MetricCard label="Caffeine" value={`${scenario.todayCaffeineMg} mg`} detail="today total" />
        <MetricCard label="Active now" value={`${scenario.activeCaffeineMg} mg`} detail={`alertness ${scenario.alertnessScore}`} />
      </div>

      <ScreenCard title="Quick add">
        <div className="pill-row">
          {scenario.doses.map((dose) => (
            <span key={dose.label} className="demo-pill">
              {dose.label.split(' ')[0]} {dose.mg}mg
            </span>
          ))}
        </div>
      </ScreenCard>

      <ScreenCard title="Vigilance">
        <div className="row between">
          <strong>
            {scenario.latestVigilance.score} {scenario.latestVigilance.rating}
          </strong>
          <span>{scenario.latestVigilance.completedAt}</span>
        </div>
        <p>Latest median reaction time: {scenario.latestVigilance.medianReactionMs} ms.</p>
      </ScreenCard>

      <ScreenCard title="Recommendations">
        <KeyValue label="Daily cutoff" value={scenario.cutoffTime} />
        <KeyValue label="Suggested bedtime" value={scenario.bedtime} />
        <KeyValue label="Suggested wake" value={scenario.wakeTime} />
      </ScreenCard>
    </div>
  );
}

function SleepPreview({ scenario }: { scenario: DemoScenario }) {
  return (
    <div className="phone-content">
      <ScreenCard title="Connection">
        <p>{scenario.sleepSummary}</p>
        <span className="inline-status">{scenario.sleepStatus}</span>
      </ScreenCard>

      <div className="stats-grid">
        <MetricCard label="Cutoff" value={scenario.cutoffTime} detail="sleep-aware" />
        <MetricCard label="Bedtime" value={scenario.bedtime} detail={scenario.sleepDetail} />
      </div>

      <ScreenCard title="Suggested plan">
        {scenario.plan.map((item) => (
          <KeyValue key={item.label} label={item.label} value={`${item.mg} mg at ${item.time}`} />
        ))}
      </ScreenCard>
    </div>
  );
}

function InsightsPreview({ scenario }: { scenario: DemoScenario }) {
  return (
    <div className="phone-content">
      <ScreenCard title="Trend">
        <MiniChart values={scenario.trend} />
      </ScreenCard>

      <ScreenCard title="Daypart mix">
        {scenario.daypartMix.map((item) => (
          <BarRow key={item.label} label={item.label} value={item.pct} detail={`${item.mg} mg`} />
        ))}
      </ScreenCard>

      <ScreenCard title="Source mix">
        {scenario.sourceMix.map((item) => (
          <BarRow key={item.label} label={item.label} value={item.pct} detail={`${item.mg} mg`} />
        ))}
      </ScreenCard>

      <ScreenCard title="History">
        {scenario.history.map((row) => (
          <div key={row.title + row.detail} className="history-row">
            <div>
              <strong>{row.title}</strong>
              <p>{row.subtitle}</p>
            </div>
            <span>{row.detail}</span>
          </div>
        ))}
      </ScreenCard>
    </div>
  );
}

function VigilancePreview({
  scenario,
  vigilanceStep,
  vigilanceTimeline,
}: {
  scenario: DemoScenario;
  vigilanceStep: number;
  vigilanceTimeline: string[];
}) {
  return (
    <div className="phone-content">
      <ScreenCard title="Test area" emphasis={vigilanceStep === 1}>
        <div className={vigilanceStep === 1 ? 'reaction-zone active' : 'reaction-zone'}>
          <span>{vigilanceStep === 1 ? 'Tap now' : vigilanceStep === 2 ? 'Result saved' : 'Wait for the cue'}</span>
        </div>
        <p>{vigilanceTimeline[vigilanceStep]}</p>
      </ScreenCard>

      <ScreenCard title="Saved result">
        <div className="stats-grid single">
          <MetricCard
            label="Latest"
            value={`${scenario.latestVigilance.score} ${scenario.latestVigilance.rating}`}
            detail={scenario.latestVigilance.completedAt}
          />
        </div>
        <KeyValue label="Median reaction" value={`${scenario.latestVigilance.medianReactionMs} ms`} />
        <KeyValue label="Lapses / false starts" value={`${scenario.latestVigilance.lapseCount} / ${scenario.latestVigilance.falseStartCount}`} />
        <KeyValue label="Valid taps" value={scenario.latestVigilance.validTaps} />
      </ScreenCard>
    </div>
  );
}

function ScreenCard({
  title,
  children,
  emphasis = false,
}: {
  title: string;
  children: React.ReactNode;
  emphasis?: boolean;
}) {
  return (
    <section className={emphasis ? 'screen-card emphasis' : 'screen-card'}>
      <div className="screen-card-title">{title}</div>
      {children}
    </section>
  );
}

function MetricCard({
  label,
  value,
  detail,
}: {
  label: string;
  value: string;
  detail: string;
}) {
  return (
    <div className="metric-card">
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </div>
  );
}

function KeyValue({ label, value }: { label: string; value: string }) {
  return (
    <div className="kv-row">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function BarRow({
  label,
  value,
  detail,
}: {
  label: string;
  value: number;
  detail: string;
}) {
  return (
    <div className="bar-row">
      <div className="bar-row-label">
        <span>{label}</span>
        <small>{detail}</small>
      </div>
      <div className="bar-track">
        <div className="bar-fill" style={{ width: `${value}%` }} />
      </div>
    </div>
  );
}

function MiniChart({ values }: { values: number[] }) {
  const points = values
    .map((value, index) => {
      const x = (index / Math.max(1, values.length - 1)) * 100;
      const y = 100 - ((value - Math.min(...values)) / Math.max(1, Math.max(...values) - Math.min(...values))) * 60 - 20;
      return `${x},${y}`;
    })
    .join(' ');

  return (
    <svg viewBox="0 0 100 100" className="mini-chart" preserveAspectRatio="none" aria-hidden="true">
      <polyline points={points} />
    </svg>
  );
}
