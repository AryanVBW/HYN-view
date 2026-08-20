import { ImageResponse } from "next/og";

export const size = { width: 32, height: 32 };
export const contentType = "image/png";

// Same three ascending squares as components/logo.tsx, without the wordmark --
// a favicon is too small to read text in, so it is just the mark. Colors are
// fixed (not currentColor) because a favicon renders standalone, with no page
// to inherit from.
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
        <svg width="22" height="22" viewBox="0 0 32 32" fill="none">
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
