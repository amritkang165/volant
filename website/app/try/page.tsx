import type { Metadata } from 'next';
import { SiteFooter, SiteHeader, downloadURL, repositoryURL } from '@/components/site-chrome';
import { TryLauncher } from '@/components/try-launcher';
import './try.css';

export const metadata: Metadata = {
  title: 'Try Volant in your browser',
  description: 'Type into a demo launcher that runs real Volant extensions in your browser with WebAssembly.',
  alternates: { canonical: 'https://usevolant.com/try' },
  robots: { index: false },
};

/** The "Try Volant" spike: an interactive, clearly labeled browser demo, not a picture of the app. */
export default function TryPage() {
  return (
    <>
      <a className="skip" href="#main">Skip to content</a>
      <SiteHeader />
      <main id="main" className="wrap try-page">
        <p className="try-eyebrow">Interactive demo · runs in your browser</p>
        <h1>Try Volant now</h1>
        <p className="try-lede">
          Running in your browser: real Volant extensions, the same WebAssembly modules the Mac app installs, with
          Volant’s own extension host ported to JavaScript. Nothing you type leaves this page.
        </p>
        <TryLauncher />
        <ul className="try-facts">
          <li>Type <strong>hn</strong>, <strong>wiki</strong>, <strong>case</strong>, <strong>encode</strong>, <strong>fancy</strong> or <strong>count</strong>, then press Return.</li>
          <li>News and Wikipedia replay responses recorded once, so the demo makes no network requests on your behalf.</li>
          <li>This is a web demo of the launcher, not the app. Calculator, files, contacts, clipboard and agents run only in Volant on your Mac.</li>
        </ul>
        <div className="try-actions">
          <a className="button" href={downloadURL} download>Download Volant for Mac</a>
          <a className="button secondary" href={repositoryURL}>Star Volant on GitHub</a>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
