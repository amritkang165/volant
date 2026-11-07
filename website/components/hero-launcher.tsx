'use client';
// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import Image from 'next/image';
import { useEffect, useRef, useState } from 'react';
import examples from '@/lib/try-hero-examples.json';
import '@/app/try/try.css';

type Example = (typeof examples.examples)[number];
type Shown = { example: Example; typed: number; settled: boolean };

const typingDelay = 70;
const answerHold = 2600;

/** A fixed date for the label, so server and browser render the same text. */
function capturedLabel(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
}

/** Opens /try with what was typed, so the first keystroke carries over and the calculator starts at once. */
function handOff(text: string) {
  window.location.assign(text ? `/try?q=${encodeURIComponent(text.slice(0, 200))}` : '/try');
}

/** The homepage hero's launcher card. Plain HTML: it loops through three example queries and the
 * answers /try gave for them when they were captured (lib/try-hero-examples.json, refreshed by
 * tools/try-wasm/publish-calculator.sh); it computes nothing. Clicking it, typing, or pressing
 * Return hands over to /try. Under reduced motion it shows the first example without the loop. */
export function HeroLauncher() {
  const [shown, setShown] = useState<Shown>({ example: examples.examples[0], typed: examples.examples[0].query.length, settled: true });
  const [paused, setPaused] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (reduced.matches || paused) return;
    let index = 0, typed = 0, timer = 0;
    /** Types the current example one character at a time, holds its answer, then moves on. */
    const step = () => {
      const example = examples.examples[index];
      if (typed < example.query.length) {
        typed += 1;
        setShown({ example, typed, settled: false });
        timer = window.setTimeout(step, typingDelay);
      } else {
        setShown({ example, typed, settled: true });
        index = (index + 1) % examples.examples.length;
        typed = 0;
        timer = window.setTimeout(step, answerHold);
      }
    };
    timer = window.setTimeout(step, 600);
    return () => window.clearTimeout(timer);
  }, [paused]);

  const { example, typed, settled } = shown;
  const ghost = example.query.slice(0, typed);

  return (
    <section className="try-launcher hero-launcher" aria-label="Volant launcher demo">
      <div className="try-bar">
        <input
          ref={input}
          placeholder={paused ? 'Try Volant in your browser now…' : ''}
          aria-label="Try Volant in your browser now"
          onFocus={() => setPaused(true)}
          onPointerDown={() => handOff('')}
          onInput={(event) => handOff(event.currentTarget.value)}
          onKeyDown={(event) => { if (event.key === 'Enter') handOff(event.currentTarget.value); }}
          spellCheck={false}
          autoComplete="off"
        />
        {!paused ? (
          <span className="hero-ghost" aria-hidden>
            {ghost || <span className="hero-placeholder">Try Volant in your browser now…</span>}
            {!settled ? <span className="hero-caret" /> : null}
          </span>
        ) : null}
      </div>
      {!paused ? (
        <ul className="try-results" aria-hidden>
          {settled && example.kind === 'answer' ? (
            <li>
              <span className="try-row try-answer" aria-current>
                <span className="try-row-text">
                  <span className="try-answer-result">{example.result}</span>
                  <span className="try-subtitle">{example.query}{example.detail ? ` · ${example.detail}` : ''}</span>
                </span>
              </span>
            </li>
          ) : null}
          {settled && example.kind === 'rows' && example.rows
            ? example.rows.map((row, i) => (
                <li key={row.title}>
                  <span className="try-row" aria-current={i === 0}>
                    <Image unoptimized src={example.icon ?? '/try/extensions/hackernews/icon.webp'} alt="" width={22} height={22} />
                    <span className="try-row-text">
                      <span className="try-title">{row.title}</span>
                      <span className="try-subtitle">{row.subtitle}</span>
                    </span>
                  </span>
                </li>
              ))
            : null}
        </ul>
      ) : null}
      <div className="try-footer">
        <span className="try-footer-note">
          {paused
            ? 'Start typing to try Volant in your browser'
            : `Example answers from the in-browser demo, captured ${capturedLabel(examples.capturedAt)}${example.kind === 'rows' ? ' (Hacker News sample data)' : ''}`}
        </span>
        <a className="hero-try-link" href="/try">Open the demo</a>
      </div>
    </section>
  );
}
