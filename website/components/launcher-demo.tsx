'use client';
import Image from 'next/image';
import { useEffect, useState } from 'react';

/** The README's real native fixture. Reduced motion never loads the animated asset. */
export function LauncherDemo() {
  const [playing, setPlaying] = useState(false);
  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
    setPlaying(!preference.matches);
    const changed = () => {
      if (preference.matches) setPlaying(false);
    };
    preference.addEventListener('change', changed);
    return () => preference.removeEventListener('change', changed);
  }, []);
  return (
    <figure className="home-product">
      <div className="home-product-label">
        <span /> YOUR NEXT MOVE, WITHIN REACH
      </div>
      <Image
        unoptimized
        src={
          playing
            ? '/images/volant-demo.webp'
            : '/images/volant-demo-poster.webp'
        }
        alt="Native Volant demo: finding Safari, calculating 12% of 840, then showing fictional coding agents waiting for a decision."
        width={1500}
        height={960}
        preload
      />
      <figcaption className="home-demo-caption">
        <span>Native interface · fictional activity</span>
        <button
          className="home-demo-control"
          type="button"
          onClick={() => setPlaying((value) => !value)}
        >
          {playing ? 'Stop demo' : 'Play demo'}
        </button>
      </figcaption>
    </figure>
  );
}
