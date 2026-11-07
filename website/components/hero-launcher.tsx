'use client';
// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import Image from 'next/image';
import { useEffect, useState } from 'react';
import examples from '@/lib/try-hero-examples.json';
import '@/app/try/try.css';

type Example = (typeof examples.examples)[number];

const startDelay = 250;
const typingDelay = 60;
const answerHold = 2200;
const promptRest = 800;
const prompt = 'Try Volant in your browser now…';

/** A fixed date for the label, so server and browser render the same text. */
function capturedLabel(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
}

/** The /try address that opens with this text in the field. */
function tryLink(text: string) {
  return text ? `/try?q=${encodeURIComponent(text.slice(0, 200))}` : '/try';
}

/** Opens /try with what was typed, so the first keystroke carries over and the calculator starts at once. */
function handOff(text: string) {
  window.location.assign(tryLink(text));
}

/** A saved example's answer line: the calculator's result, or the extension's name and top row. */
function answerOf(example: Example) {
  if (example.kind === 'rows') return { result: example.extension ?? example.query, detail: example.rows?.[0]?.title ?? '' };
  return { result: example.result ?? '', detail: example.detail ?? '' };
}

/** The homepage hero's launcher card, the /try card in plain HTML. Its suggestion rows are the
 * saved examples with the answers /try gave when they were captured (lib/try-hero-examples.json,
 * refreshed by every website build), server-rendered so they show on first paint; each opens /try
 * with that query. After hydration it types the examples one by one into the field and highlights
 * the matching row, resting on the prompt briefly between them. It computes nothing. Clicking or
 * typing in the field hands over to /try. Under reduced motion nothing is typed. `large` is the
 * launcher-as-hero variant. */
export function HeroLauncher({ large = false }: { large?: boolean }) {
  const [current, setCurrent] = useState<number | null>(null);
  const [typed, setTyped] = useState(0);
  const [settled, setSettled] = useState(false);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || paused) return;
    let index = 0, count = 0, timer = 0;
    /** Types the next example, holds it with its row highlighted, then rests on the prompt. */
    const step = () => {
      const query = examples.examples[index].query;
      if (count < query.length) {
        count += 1;
        setCurrent(index); setTyped(count); setSettled(false);
        timer = window.setTimeout(step, typingDelay);
      } else if (count === query.length) {
        count += 1;
        setSettled(true);
        timer = window.setTimeout(step, answerHold);
      } else {
        setCurrent(null); setTyped(0); setSettled(false);
        index = (index + 1) % examples.examples.length;
        count = 0;
        timer = window.setTimeout(step, promptRest);
      }
    };
    timer = window.setTimeout(step, startDelay);
    return () => window.clearTimeout(timer);
  }, [paused]);

  const typing = !paused && current !== null;
  const example = current === null ? null : examples.examples[current];

  return (
    <section className={`try-launcher hero-launcher${large ? ' hero-launcher-large' : ''}`} aria-label="Volant launcher demo">
      <div className="try-bar">
        <input
          placeholder={prompt}
          className={typing ? 'hero-typing' : undefined}
          aria-label="Try Volant in your browser now"
          onFocus={() => setPaused(true)}
          onPointerDown={() => handOff('')}
          onInput={(event) => handOff(event.currentTarget.value)}
          onKeyDown={(event) => { if (event.key === 'Enter') handOff(event.currentTarget.value); }}
          spellCheck={false}
          autoComplete="off"
        />
        {typing && example ? (
          <span className="hero-ghost" aria-hidden>
            {example.query.slice(0, typed)}
            {!settled ? <span className="hero-caret" /> : null}
          </span>
        ) : null}
      </div>
      <ul className="try-results hero-suggestions" aria-label="Examples to try">
        {examples.examples.map((item, i) => {
          const { result, detail } = answerOf(item);
          return (
            <li key={item.query}>
              <a className="try-row hero-suggestion" href={tryLink(item.query)} aria-current={typing && settled && current === i}>
                <span className="hero-query">{item.query}</span>
                <span className="try-row-text">
                  <span className="try-title hero-answer">
                    {item.kind === 'rows' && item.icon ? <Image unoptimized src={item.icon} alt="" width={16} height={16} /> : null}
                    {result}
                  </span>
                  {detail ? <span className="try-subtitle">{detail}</span> : null}
                </span>
                <span className="try-kind hero-open">Open ↗</span>
              </a>
            </li>
          );
        })}
      </ul>
      <div className="try-footer">
        <span className="try-footer-note">
          {`Real Volant code in your browser. Answers captured ${capturedLabel(examples.capturedAt)}; Hacker News from sample data.`}
        </span>
        <a className="hero-try-link" href="/try">Open the demo</a>
      </div>
    </section>
  );
}
