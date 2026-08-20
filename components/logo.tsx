// The wordmark. White, on nothing — no plate, no box, no background — so it sits
// on the page rather than on a rectangle of its own.
//
// `--logo-ink` is the one knob: it defaults to white, and any parent can set it
// to recolour the whole lockup. That is deliberately a CSS variable rather than
// `currentColor`: the logo should not change colour just because it was dropped
// inside a paragraph of muted text, which is what happened when it inherited.
//
// The fills go through `style`, not `fill=`, on purpose. A presentation attribute
// is parsed with the SVG attribute grammar, and Firefox does not substitute
// var() there — `fill="var(--logo-ink, #fff)"` renders as *nothing*, which on a
// black page is an invisible logo. Inline style is real CSS, where var() works
// everywhere.
//
// The animation is CSS in app/globals.css (`logo-sweep`, `logo-caret`), keyed off
// two class names below. It animates opacity only — no transform, no filter — so
// it cannot reflow or repaint anything around it, and it stops completely under
// `prefers-reduced-motion`. Sizing stays width-based (`className="w-[120px]"`),
// which is how every caller already uses it.
const INK = { fill: "var(--logo-ink, #fff)" };

export const Logo = (props: React.SVGProps<SVGSVGElement>) => (
  <svg
    viewBox="0 0 150 32"
    fill="none"
    role="img"
    aria-label="HYN-view"
    xmlns="http://www.w3.org/2000/svg"
    {...props}
  >
    {/* Three cells, lit in sequence: the mark reads as a signal arriving, which
        is what this product watches. */}
    <rect className="logo-cell" style={INK} x="2" y="5" width="6" height="6" />
    <rect
      className="logo-cell"
      style={{ ...INK, animationDelay: "0.18s" }}
      x="10"
      y="13"
      width="6"
      height="6"
    />
    <rect
      className="logo-cell"
      style={{ ...INK, animationDelay: "0.36s" }}
      x="18"
      y="21"
      width="6"
      height="6"
    />

    {/* The site's own mono face, with a real fallback stack behind it: an SVG
        <text> that names only "monospace" renders in whatever the browser picked
        years ago, and the lockup width shifts with it. */}
    <text
      x="31"
      y="22"
      fontSize="15"
      fontWeight="500"
      letterSpacing="0.02em"
      style={{
        ...INK,
        fontFamily:
          "var(--font-geist-mono), ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
      }}
    >
      HYN
      {/* Dimmed so the name has a hierarchy at 100px wide instead of eight
          identical glyphs. fill-opacity rather than a second colour: it needs no
          colour function, so there is no value a browser can fail to parse and
          leave the text at SVG's default black — invisible on this page. */}
      <tspan style={{ fillOpacity: 0.6 }}>-view</tspan>
    </text>

    {/* Terminal caret. Blinks on a step curve, like the real one. */}
    <rect className="logo-caret" style={INK} x="110" y="11" width="6" height="11" />
  </svg>
);
