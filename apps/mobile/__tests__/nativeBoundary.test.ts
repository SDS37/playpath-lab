import { readdirSync, readFileSync, statSync } from "fs";
import { join } from "path";

const root = join(__dirname, "..");

function filesUnder(dir: string): string[] {
  const found: string[] = [];
  for (const name of readdirSync(dir)) {
    if (name === "node_modules" || name === "Pods" || name === "build") {
      continue;
    }
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      found.push(...filesUnder(path));
    } else {
      found.push(path);
    }
  }
  return found;
}

test("javascript does not decode and there is no css file", () => {
  const files = [
    ...filesUnder(join(root, "src")),
    ...filesUnder(join(root, "specs")),
    join(root, "App.tsx"),
  ];
  expect(files.some((file) => file.endsWith(".css"))).toBe(false);
  const banned = ["react-native-video", "shaka", "hls.js", "VideoDecoder", "ffefcdab"];
  for (const file of files) {
    const text = readFileSync(file, "utf8");
    for (const word of banned) {
      expect(text.includes(word)).toBe(false);
    }
  }
  const kotlin = readFileSync(
    join(root, "android/app/src/main/java/lab/playpath/mobile/PlaypathPlayerView.kt"),
    "utf8",
  );
  const swift = readFileSync(
    join(root, "ios/PlaypathMobile/PlaypathSession.swift"),
    "utf8",
  );
  expect(kotlin).toContain("androidx.media3.exoplayer.ExoPlayer");
  expect(swift).toContain("AVPlayer");
  expect(kotlin).not.toContain("ffefcdab");
  expect(swift).not.toContain("ffefcdab");
});
