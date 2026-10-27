import { tx } from "../lib/i18n";
import { BRAND } from "../lib/mode";

/**
 * The wordmark: the mark, then HAMMER in chamfered capitals. One even-odd path.
 * The mark is a hammer drawn as a hammer candle: a short body on top, a long lower wick below,
 * the reversal pattern traders call "the hammer".
 */
export function Wordmark({ height = 18, title = BRAND }: { height?: number; title?: string }) {
  return (
    <svg className="wordmark" viewBox="0 0 600 160" height={height} role="img" aria-label={tx(title)}>
      <path fill="currentColor" fillRule="evenodd" d={WORDMARK_PATH} />
    </svg>
  );
}

/** The square mark: the hammer on its own, tilted mid-swing like the wordmark's. */
export function Mark({ size = 24, title = BRAND }: { size?: number; title?: string }) {
  return (
    <svg className="mark" viewBox="0 0 160 160" width={size} height={size} role="img" aria-label={tx(title)}>
      <g transform="rotate(-28 80 84)"><path fill="currentColor" d={MARK_PATH} transform="translate(16 12) scale(.8)" /></g>
    </svg>
  );
}

/** Width over height of the wordmark. */
export const WORDMARK_RATIO = 3.7500;
export const BRAND_ACCENT = "#ff8a1f";

/** The hammer in a 160 x 160 box: the head (candle body) with a chamfered striking face, the handle (wick). */
export const MARK_PATH = "M22 20H124L140 36V70H90V138L80 148L70 138V70H22Z";

/** The wordmark's outline (even-odd), in a 600 x 160 box: for drawing it on a canvas. */
export const WORDMARK_PATH = [
  "M4 59L47.3 32L61.4 35.2L72.3 52.5L50.6 66.1L84 119.6L83.3 128L75.3 125L41.9 71.5L20.3 85.1Z", // the hammer, tilted mid-swing
  "M104 30H126V69H152V30H174V130H152V91H126V130H104Z", // H
  "M184 130V50L204 30H234L254 50V130H232V98H206V130ZM206 76H232V56L227 52H211L206 56Z", // A
  "M264 130V30H288L299 60L310 30H334V130H312V74L299 102L286 74V130Z", // M
  "M344 130V30H368L379 60L390 30H414V130H392V74L379 102L366 74V130Z", // M
  "M424 30H494V52H446V69H488V91H446V108H494V130H424Z", // E
  "M504 130V30H556L574 48V74L564 86L576 130H553L542 92H526V130ZM526 52V70H550L552 68V54L550 52Z", // R
].join("");
export const WORDMARK_SIZE: [number, number] = [600, 160];
