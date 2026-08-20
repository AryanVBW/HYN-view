import { ImageResponse } from "next/og";

export const size = { width: 32, height: 32 };
export const contentType = "image/png";

// Same three ascending squares as components/logo.tsx's <Logo>, at the same
// relative positions and the same white ink -- so the browser tab and the
// navbar show one mark, not two. Colors are fixed (not currentColor/var())
// because a favicon renders standalone, with no page to inherit from.
export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#000000",
        }}
      >
        <svg width="24" height="24" viewBox="0 0 32 32" fill="none">
          <rect x="2" y="5" width="8" height="8" fill="#ffffff" />
          <rect x="12" y="15" width="8" height="8" fill="#ffffff" fillOpacity="0.85" />
          <rect x="22" y="25" width="8" height="8" fill="#ffffff" fillOpacity="0.7" />
        </svg>
      </div>
    ),
    { ...size }
  );
}
