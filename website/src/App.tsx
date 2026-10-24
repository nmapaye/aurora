const githubUrl = 'https://github.com/nmapaye/aurora';

const betaEmail = 'nmapaye@outlook.com';
const betaSubject = 'Aurora beta request';
const betaBody = [
  "Hi, I'd like to join the free Aurora TestFlight beta.",
  '',
  'Name or handle:',
  'Device (iPhone / iPad / both):',
  'iOS or iPadOS version:',
  'Would you be up for testing with VoiceOver turned on? (yes / no):',
  'Would you do one guided session in the first week (about 4 short tasks, then a few quick questions)? (yes / maybe / no):',
  '',
  "Please don't include health information. This address is only used to send your TestFlight invite and beta updates.",
].join('\r\n');
const betaMailto = `mailto:${betaEmail}?subject=${encodeURIComponent(betaSubject)}&body=${encodeURIComponent(betaBody)}`;

export default function App() {
  return (
    <div className="site-shell">
      <a className="skip-link" href="#main">
        Skip to content
      </a>

      <main id="main">
        <section id="top" className="hero section" aria-labelledby="hero-title">
          <div className="hero-copy">
            <div className="hero-identity" aria-hidden="true" />
            <p className="eyebrow">In beta: request an invite by email</p>
            <h1 id="hero-title">Aurora is in beta.</h1>
            <p className="hero-text">Email us to request an invite. The TestFlight beta is free.</p>
            <div className="hero-actions">
              <a className="button button-primary" href={betaMailto} aria-describedby="beta-privacy">
                Request beta access
              </a>
            </div>
            <p id="beta-privacy" className="beta-privacy">
              Privacy: your email address is used only to send you a TestFlight invite and beta
              updates. It isn't sold, and it's shared only with Apple to send the invite. You can ask
              to be removed at any time.
            </p>
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
