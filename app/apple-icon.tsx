import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

// iOS masks this into a rounded square itself, so it ships as a plain filled
// square here rather than pre-rounding it. Same mark as app/icon.tsx, scaled
// up: three ascending squares in white, matching components/logo.tsx.
export default function AppleIcon() {
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
        <svg width="140" height="140" viewBox="0 0 32 32" fill="none">
          <rect x="2" y="5" width="8" height="8" fill="#ffffff" />
          <rect x="12" y="15" width="8" height="8" fill="#ffffff" fillOpacity="0.85" />
          <rect x="22" y="25" width="8" height="8" fill="#ffffff" fillOpacity="0.7" />
        </svg>
      </div>
    ),
    { ...size }
  );
}
