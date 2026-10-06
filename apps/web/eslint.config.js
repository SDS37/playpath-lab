import js from "@eslint/js";
import { defineConfig } from "eslint/config";
import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";

export default defineConfig(
  { ignores: ["dist/**", "node_modules/**"] },
  js.configs.recommended,
  {
    files: ["src/**/*.{ts,tsx}"],
    extends: [tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: { "react-hooks": reactHooks },
    rules: reactHooks.configs.recommended.rules,
  },
  {
    files: [
      "src/Controls.tsx",
      "src/PlayerScreen.tsx",
      "src/usePlaybackSession.ts",
      "src/main.tsx",
      "src/drmServers.ts",
      "src/protectedMenus.ts",
      "src/clearHlsMenu.ts",
      "src/chooseEngine.ts",
    ],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          paths: [
            {
              name: "shaka-player",
              message: "Only PlaybackSession imports Shaka.",
            },
            {
              name: "hls.js",
              message: "Only PlaybackSession imports hls.js.",
            },
          ],
        },
      ],
    },
  },
);
