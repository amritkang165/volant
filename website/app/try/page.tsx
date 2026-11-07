// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import type { Metadata } from 'next';
import { SiteFooter, SiteHeader, downloadURL, repositoryURL } from '@/components/site-chrome';
import { TryLauncher } from '@/components/try-launcher';
import './try.css';

export const metadata: Metadata = {
  title: 'Try Volant in your browser',
  description:
    'Type into Volant in your browser: real Volant extensions and Volant’s own calculator, compiled to WebAssembly. Nothing you type leaves the page.',
  alternates: { canonical: 'https://usevolant.com/try' },
};

/** The interactive, clearly labeled browser demo of the launcher, running real Volant code. The
 * homepage hero hands typed text over as `?q=`. */
export default async function TryPage({ searchParams }: { searchParams: Promise<{ q?: string | string[] }> }) {
  const { q } = await searchParams;
  const initialQuery = (Array.isArray(q) ? q[0] : q ?? '').slice(0, 200);
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
        <TryLauncher initialQuery={initialQuery} />
        <ul className="try-facts">
          <li>Try <strong>2+2</strong>, <strong>15% of 80</strong>, <strong>5 km in miles</strong>, <strong>3pm tokyo in new york</strong> or <strong>100 usd in eur</strong>.</li>
          <li>Or type <strong>hn</strong>, <strong>wiki</strong>, <strong>case</strong>, <strong>encode</strong>, <strong>fancy</strong> or <strong>count</strong>, then press Return.</li>
          <li>
            Currency answers use public exchange rates this site refreshes on a schedule; your query never leaves the page and
            never reaches the providers. News and Wikipedia replay responses recorded once.
          </li>
          <li>This is a web demo of the launcher, not the app. Files, contacts, clipboard and agents run only in Volant on your Mac. The demo answers in English only; the full app formats numbers, dates and units for your language and region.</li>
        </ul>
        <p className="try-credits">
          Exchange rates:{' '}
          <a href="https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html">European Central Bank</a>
          {' · '}
          <a href="https://www.exchangerate-api.com">Rates By Exchange Rate API</a>
          {' · '}
          <a href="https://www.coingecko.com">Data provided by CoinGecko</a>
          {' · '}
          <a href={`${repositoryURL}/blob/main/docs/try-volant.md`}>How the demo works</a>
        </p>
        <div className="try-actions">
          <a className="button" href={downloadURL} download>Download Volant for Mac</a>
          <a className="button secondary" href={repositoryURL}>Star Volant on GitHub</a>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
