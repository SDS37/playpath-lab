import { createReadStream } from "node:fs";
import { access } from "node:fs/promises";
import http from "node:http";
import path from "node:path";

const port = 5193;
const dist = path.join(import.meta.dirname, "dist");

const types = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".json", "application/json"],
  [".map", "application/json"],
]);

function upstreamUrl(requestUrl) {
  if (requestUrl.startsWith("/origin/")) {
    return "http://127.0.0.1:8080" + requestUrl.slice("/origin".length);
  }
  if (requestUrl.startsWith("/clear/")) {
    return "http://127.0.0.1:8084" + requestUrl.slice("/clear".length);
  }
  if (
    requestUrl === "/license" ||
    requestUrl.startsWith("/license/") ||
    requestUrl.startsWith("/license?")
  ) {
    const rest = requestUrl.slice("/license".length);
    const suffix = rest === "" || rest.startsWith("?") ? `/${rest}` : rest;
    return "http://127.0.0.1:8082" + suffix;
  }
  return null;
}

function rewriteMenus(text) {
  return text
    .replaceAll("http://127.0.0.1:8082/", "/license/")
    .replaceAll("http://127.0.0.1:8080/", "/origin/")
    .replaceAll("http://127.0.0.1:8084/", "/clear/");
}

function rewriteResponse(requestUrl, contentType) {
  const pathOnly = requestUrl.split("?", 1)[0];
  if (
    pathOnly.endsWith(".m3u8") ||
    pathOnly.endsWith(".mpd") ||
    pathOnly.endsWith(".vtt")
  ) {
    return true;
  }
  return (
    contentType.includes("mpegurl") ||
    contentType.includes("dash+xml") ||
    contentType.includes("text/vtt")
  );
}

async function proxy(request, response) {
  const target = upstreamUrl(request.url ?? "/");
  if (target === null) {
    return false;
  }
  const headers = {};
  const contentType = request.headers["content-type"];
  const range = request.headers.range;
  const accept = request.headers.accept;
  if (contentType !== undefined) {
    headers["content-type"] = contentType;
  }
  if (range !== undefined) {
    headers.range = range;
  }
  if (accept !== undefined) {
    headers.accept = accept;
  }
  const upstream = await fetch(target, {
    method: request.method,
    headers,
    body:
      request.method === "GET" || request.method === "HEAD"
        ? undefined
        : request,
    duplex: "half",
  });
  const responseType = upstream.headers.get("content-type") ?? "";
  const out = {
    "content-type": responseType,
  };
  const contentRange = upstream.headers.get("content-range");
  const acceptRanges = upstream.headers.get("accept-ranges");
  if (contentRange !== null) {
    out["content-range"] = contentRange;
  }
  if (acceptRanges !== null) {
    out["accept-ranges"] = acceptRanges;
  }
  if (rewriteResponse(request.url ?? "/", responseType)) {
    const text = rewriteMenus(await upstream.text());
    response.writeHead(upstream.status, out);
    response.end(text);
    return true;
  }
  const bytes = Buffer.from(await upstream.arrayBuffer());
  response.writeHead(upstream.status, out);
  response.end(bytes);
  return true;
}

function fileFor(requestUrl) {
  const pathname = decodeURIComponent((requestUrl ?? "/").split("?", 1)[0]);
  const relative = pathname === "/" ? "index.html" : pathname.slice(1);
  const file = path.normalize(path.join(dist, relative));
  if (file !== dist && !file.startsWith(dist + path.sep)) {
    return null;
  }
  return file;
}

const server = http.createServer(async (request, response) => {
  try {
    if (await proxy(request, response)) {
      return;
    }
  } catch {
    response.writeHead(502);
    response.end("Playback failed.");
    return;
  }
  const file = fileFor(request.url);
  if (file === null) {
    response.writeHead(403);
    response.end();
    return;
  }
  try {
    await access(file);
  } catch {
    response.writeHead(404);
    response.end();
    return;
  }
  const type = types.get(path.extname(file)) ?? "application/octet-stream";
  response.writeHead(200, { "content-type": type });
  if (request.method === "HEAD") {
    response.end();
    return;
  }
  createReadStream(file).pipe(response);
});

server.listen(port, "127.0.0.1");
