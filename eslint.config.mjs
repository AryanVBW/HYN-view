import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTypescript from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTypescript,
  globalIgnores([
    "node_modules/**",
    ".next/**",
    ".vercel/**",
    "out/**",
    "build/**",
    "app/.well-known/workflow/**",
    "three-effect/**",
    "next-env.d.ts",
  ]),
  {
    // The product's visual language deliberately renders labels such as
    // "// system status". They are text, not accidental JSX comments.
    rules: {
      "react/jsx-no-comment-textnodes": "off",
    },
  },
  {
    files: ["app/account/page.tsx", "app/dashboard/page.tsx"],
    // These are async server pages. Their request-time timestamps do not run
    // in a client render loop, so the client purity warning is a false match.
    rules: {
      "react-hooks/purity": "off",
    },
  },
  {
    files: ["components/gl/**/*.tsx"],
    // The existing imperative WebGL adapter mutates Three.js refs by design.
    // Keep these exceptions local instead of weakening hooks rules elsewhere.
    rules: {
      "@typescript-eslint/ban-ts-comment": "off",
      "react-hooks/immutability": "off",
      "react-hooks/set-state-in-effect": "off",
    },
  },
  {
    files: [
      "components/header.tsx",
      "components/hero.tsx",
      "components/theme-toggle.tsx",
      "components/dashboard-view-toggle.tsx",
      "components/site-cursor-grid.tsx",
    ],
    // These legacy auth/theme hydration guards intentionally synchronize
    // client-only state after mount.
    rules: {
      "react-hooks/set-state-in-effect": "off",
    },
  },
]);

export default eslintConfig;
