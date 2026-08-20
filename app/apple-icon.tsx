import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

// iOS masks this into a rounded square itself, so it ships as a plain filled
// square here rather than pre-rounding it. Same mark as app/icon.tsx, scaled
// up: three ascending squares, no wordmark.
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
        <svg width="128" height="128" viewBox="0 0 32 32" fill="none">
          <path
            d="M2 5h6v6H2V5Zm8 8h6v6h-6v-6Zm8 8h6v6h-6v-6Z"
            fill="#FFC700"
          />
        </svg>
      </div>
    ),
    { ...size }
  );
}
