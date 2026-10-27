import { useId, useRef } from "react";
import { MARK_PATH } from "./Wordmark";

export function LandingArrow() {
  return <svg className="lp-arrow" width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4 12h15m-6-6 6 6-6 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}

/** A fixed, seeded price walk, so the picture is the same on every visit and on the server. */
function trace(): { line: string; area: string; end: [number, number]; low: [number, number] } {
  let seed = 7;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const left = 92, right = 548, top = 132, bottom = 372, n = 64;
  const pts: [number, number][] = [];
  let v = 0.38;
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    // A quiet drift, a shakeout below entry, then the breakout the position was waiting for.
    const pull = t < 0.42 ? -0.002 : t < 0.55 ? -0.012 : 0.017;
    v = Math.min(0.96, Math.max(0.06, v + pull + (rand() - 0.5) * 0.06));
    pts.push([left + (right - left) * t, bottom - (bottom - top) * v]);
  }
  const line = pts.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`).join("");
  const area = `${line}L${right} ${bottom}L${left} ${bottom}Z`;
  // The bottom of the shakeout, where the hammer candle prints before the breakout.
  const low = pts.reduce((a, b) => (b[1] > a[1] ? b : a));
  return { line, area, end: pts[pts.length - 1], low };
}
const TRACE = trace();

/** Hammer's hero: a terminal screen with one position on it, the trace lit like a live wire. */
export function HammerScope() {
  const id = useId().replace(/:/g, "");
  const ref = useRef<HTMLDivElement>(null);
  const [ex, ey] = TRACE.end;
  const [hx, hy] = TRACE.low;
  return <div className="lp-tape-art lp-scope" aria-hidden="true" ref={ref}
    onPointerMove={(e) => {
      if (e.pointerType !== "mouse" || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      const box = e.currentTarget.getBoundingClientRect();
      ref.current?.style.setProperty("--tilt-x", `${(e.clientY - box.top - box.height / 2) / box.height * -7}deg`);
      ref.current?.style.setProperty("--tilt-y", `${(e.clientX - box.left - box.width / 2) / box.width * 9}deg`);
    }}
    onPointerLeave={() => { ref.current?.style.setProperty("--tilt-x", "0deg"); ref.current?.style.setProperty("--tilt-y", "0deg"); }}>
    <svg viewBox="0 0 620 540" className="lp-tape-sculpture" fill="none">
      <defs>
        <linearGradient id={`${id}-fill`} x1="0" y1="132" x2="0" y2="372" gradientUnits="userSpaceOnUse"><stop stopColor="#ff8a1f" stopOpacity=".28" /><stop offset="1" stopColor="#ff8a1f" stopOpacity="0" /></linearGradient>
        <linearGradient id={`${id}-glass`} x1="40" y1="60" x2="600" y2="480" gradientUnits="userSpaceOnUse"><stop stopColor="#1b2536" /><stop offset="1" stopColor="#0f151f" /></linearGradient>
        <filter id={`${id}-glow`} x="-20%" y="-40%" width="140%" height="180%"><feGaussianBlur stdDeviation="6" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
        <clipPath id={`${id}-screen`}><rect x="40" y="70" width="560" height="380" rx="14" /></clipPath>
      </defs>
      <ellipse cx="320" cy="490" rx="230" ry="10" fill="#000" opacity=".35" />
      <g className="lp-tape-object">
        <rect x="40" y="70" width="560" height="380" rx="14" fill={`url(#${id}-glass)`} stroke="#2f3c54" />
        <g clipPath={`url(#${id}-screen)`}>
          {Array.from({ length: 12 }, (_, i) => <line key={`v${i}`} x1={92 + i * 41.5} x2={92 + i * 41.5} y1="110" y2="400" stroke="#ffffff" strokeOpacity=".05" />)}
          {Array.from({ length: 7 }, (_, i) => <line key={`h${i}`} x1="60" x2="580" y1={132 + i * 40} y2={132 + i * 40} stroke="#ffffff" strokeOpacity=".05" />)}
          {/* Entry and the bust line, the two prices a 1000x position lives between. */}
          <line x1="60" x2="580" y1="300" y2="300" stroke="#9ba7bc" strokeOpacity=".5" strokeDasharray="2 5" />
          <line x1="60" x2="580" y1="352" y2="352" stroke="#ff5d6c" strokeDasharray="10 6" />
          <path d={TRACE.area} fill={`url(#${id}-fill)`} className="lp-scope-area" />
          <path d={TRACE.line} stroke="#ff8a1f" strokeWidth="3" strokeLinejoin="round" filter={`url(#${id}-glow)`} pathLength={1} className="lp-scope-line" />
          {/* The hammer: a short body on top, a long lower wick down to the low. The reversal the brand is named after. */}
          <g className="lp-scope-hammer">
            <line x1={hx} x2={hx} y1={hy + 2} y2={hy - 44} stroke="#36d399" strokeWidth="2" />
            <rect x={hx - 7} y={hy - 60} width="14" height="16" rx="2" fill="#36d399" />
            <text x={hx} y={hy - 70} fill="#36d399" fontFamily="var(--mono)" fontSize="11" fontWeight="600" textAnchor="middle">hammer</text>
          </g>
          <circle cx={ex} cy={ey} r="7" fill="#ff8a1f" className="lp-scope-dot" />
          <circle cx={ex} cy={ey} r="7" stroke="#ff8a1f" className="lp-scope-ping" />
        </g>
        {/* Screen chrome: the market, the side, the leverage. */}
        <path d={MARK_PATH} transform="translate(62 86) scale(.14) rotate(-28 80 84)" fill="#ff8a1f" />
        <text x="92" y="102" fill="#e7ecf5" fontFamily="var(--mono)" fontSize="15" fontWeight="600">BTC-PERP</text>
        <rect x="186" y="87" width="46" height="21" rx="4" fill="#36d399" fillOpacity=".16" />
        <text x="209" y="102" fill="#36d399" fontFamily="var(--ui)" fontSize="13" fontWeight="700" textAnchor="middle">Long</text>
        <rect x="238" y="87" width="56" height="21" rx="4" fill="#ff8a1f" />
        <text x="266" y="102" fill="#10151f" fontFamily="var(--mono)" fontSize="13" fontWeight="700" textAnchor="middle">1000x</text>
        <text x="580" y="102" fill="#36d399" fontFamily="var(--mono)" fontSize="15" fontWeight="600" textAnchor="end">+412.6%</text>
        <text x="572" y="296" fill="#9ba7bc" fontFamily="var(--mono)" fontSize="11" textAnchor="end">entry</text>
        <text x="572" y="370" fill="#ff5d6c" fontFamily="var(--mono)" fontSize="11" textAnchor="end">bust</text>
        <line x1="40" x2="600" y1="420" y2="420" stroke="#222d40" />
        <text x="62" y="440" fill="#7f8ba2" fontFamily="var(--mono)" fontSize="12">$50 margin, $50,000 size, settled in USDC</text>
      </g>
    </svg>
  </div>;
}

/** Kept under its old name so the landing page needs no other change. */
export const HammerSculpture = HammerScope;
