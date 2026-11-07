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
          Running in your browser: real Volant extensions and Volant’s own calculator, compiled to WebAssembly. Nothing
          you type leaves this page.
        </p>
        <TryLauncher />
        <ul className="try-facts">
          <li>Try <strong>2+2</strong>, <strong>15% of 80</strong>, <strong>5 km in miles</strong>, <strong>3pm tokyo in new york</strong> or <strong>100 usd in eur</strong>.</li>
          <li>Or type <strong>hn</strong>, <strong>wiki</strong>, <strong>case</strong>, <strong>encode</strong>, <strong>fancy</strong> or <strong>count</strong>, then press Return.</li>
          <li>For a currency answer, this site fetches public exchange rates once and caches them; your query never leaves the page. News and Wikipedia replay responses recorded once.</li>
          <li>This is a web demo of the launcher, not the app. Files, contacts, clipboard and agents run only in Volant on your Mac. The demo answers in English.</li>
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
