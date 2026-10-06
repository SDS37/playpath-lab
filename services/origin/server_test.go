package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResponses(t *testing.T) {
	dir := t.TempDir()
	mustWrite(t, filepath.Join(dir, "master.m3u8"), []byte("#EXTM3U\n"))
	mustWrite(t, filepath.Join(dir, "manifest.mpd"), []byte("<MPD></MPD>\n"))
	mustWrite(t, filepath.Join(dir, "720p", "seg_0.m4s"), []byte("fmp4"))
	mustWrite(t, filepath.Join(dir, "720p", "init_0.mp4"), []byte("init"))
	mustWrite(t, filepath.Join(dir, "audio", "seg_0.m4s"), []byte("audio"))
	mustWrite(t, filepath.Join(dir, "audio", "init_2.mp4"), []byte("ainit"))
	mustWrite(t, filepath.Join(dir, "subtitles", "playpath-bars.vtt"), []byte("WEBVTT\n"))
	mustWrite(t, filepath.Join(dir, "lab-key.json"), []byte(`{"key":"secret"}`))
	mustWrite(t, filepath.Join(dir, "playpath-bars.mp4"), []byte("mezzanine"))

	handler, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}

	tests := []struct {
		method    string
		path      string
		status    int
		ctype     string
		validator bool
	}{
		{method: http.MethodGet, path: "/master.m3u8", status: http.StatusOK, ctype: "application/vnd.apple.mpegurl", validator: true},
		{method: http.MethodGet, path: "/manifest.mpd", status: http.StatusOK, ctype: "application/dash+xml", validator: true},
		{method: http.MethodGet, path: "/720p/seg_0.m4s", status: http.StatusOK, ctype: "video/mp4", validator: true},
		{method: http.MethodGet, path: "/720p/init_0.mp4", status: http.StatusOK, ctype: "video/mp4", validator: true},
		{method: http.MethodGet, path: "/audio/seg_0.m4s", status: http.StatusOK, ctype: "audio/mp4", validator: true},
		{method: http.MethodGet, path: "/audio/init_2.mp4", status: http.StatusOK, ctype: "audio/mp4", validator: true},
		{method: http.MethodGet, path: "/subtitles/playpath-bars.vtt", status: http.StatusOK, ctype: "text/vtt", validator: true},
		{method: http.MethodHead, path: "/master.m3u8", status: http.StatusOK, ctype: "application/vnd.apple.mpegurl", validator: true},
		{method: http.MethodPost, path: "/master.m3u8", status: http.StatusMethodNotAllowed},
		{method: http.MethodGet, path: "/", status: http.StatusNotFound},
		{method: http.MethodGet, path: "/720p/", status: http.StatusNotFound},
		{method: http.MethodGet, path: "/lab-key.json", status: http.StatusNotFound},
		{method: http.MethodGet, path: "/LAB-KEY.JSON", status: http.StatusNotFound},
		{method: http.MethodGet, path: "/720p/lab-key.json", status: http.StatusNotFound},
		{method: http.MethodGet, path: "/playpath-bars.mp4", status: http.StatusNotFound},
		{method: http.MethodGet, path: "/PLAYPATH-BARS.MP4", status: http.StatusNotFound},
		{method: http.MethodGet, path: `/720p\..\lab-key.json`, status: http.StatusNotFound},
		{method: http.MethodGet, path: "/missing.m4s", status: http.StatusNotFound},
		{method: http.MethodGet, path: "/../lab-key.json", status: http.StatusNotFound},
	}

	for _, tt := range tests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, "http://127.0.0.1/", nil)
			req.URL.Path = tt.path
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)
			if rec.Code != tt.status {
				t.Fatalf("status %d, want %d", rec.Code, tt.status)
			}
			if tt.status == http.StatusMethodNotAllowed && rec.Header().Get("Allow") != "GET, HEAD, OPTIONS" {
				t.Fatalf("Allow %q, want %q", rec.Header().Get("Allow"), "GET, HEAD, OPTIONS")
			}
			if tt.ctype != "" && rec.Header().Get("Content-Type") != tt.ctype {
				t.Fatalf("content type %q, want %q", rec.Header().Get("Content-Type"), tt.ctype)
			}
			if tt.validator && rec.Header().Get("ETag") == "" && rec.Header().Get("Last-Modified") == "" {
				t.Fatal("missing ETag and Last-Modified")
			}
			if strings.Contains(rec.Body.String(), "secret") || strings.Contains(rec.Body.String(), "mezzanine") {
				t.Fatal("response included the content key or the mezzanine")
			}
		})
	}
}

func TestWebOriginCanReadAMenu(t *testing.T) {
	dir := t.TempDir()
	mustWrite(t, filepath.Join(dir, "manifest.mpd"), []byte("<MPD></MPD>\n"))
	mustWrite(t, filepath.Join(dir, "lab-key.json"), []byte(`{"key":"secret"}`))
	handler, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}

	preflight := httptest.NewRequest(http.MethodOptions, "http://127.0.0.1:8080/manifest.mpd", nil)
	preflight.Header.Set("Origin", webOrigin)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, preflight)
	if rec.Code != http.StatusNoContent || rec.Header().Get("Access-Control-Allow-Origin") != webOrigin {
		t.Fatalf("preflight %d origin %q", rec.Code, rec.Header().Get("Access-Control-Allow-Origin"))
	}

	get := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:8080/manifest.mpd", nil)
	get.Header.Set("Origin", webOrigin)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, get)
	if rec.Code != http.StatusOK || rec.Header().Get("Access-Control-Allow-Origin") != webOrigin {
		t.Fatalf("get %d origin %q", rec.Code, rec.Header().Get("Access-Control-Allow-Origin"))
	}

	other := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:8080/manifest.mpd", nil)
	other.Header.Set("Origin", "http://example.test")
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, other)
	if rec.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Fatalf("unexpected origin %q", rec.Header().Get("Access-Control-Allow-Origin"))
	}

	hidden := httptest.NewRequest(http.MethodOptions, "http://127.0.0.1:8080/lab-key.json", nil)
	hidden.Header.Set("Origin", webOrigin)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, hidden)
	if rec.Code != http.StatusNotFound || strings.Contains(rec.Body.String(), "secret") {
		t.Fatalf("hidden preflight %d", rec.Code)
	}
}

func TestForbiddenNames(t *testing.T) {
	handler, err := New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{
		"/LAB-KEY.JSON",
		"/720p/Lab-Key.json",
		"/PLAYPATH-BARS.MP4",
		`/a\..\lab-key.json`,
	} {
		if _, ok := handler.file(p); ok {
			t.Fatalf("allowed %s", p)
		}
	}
}

func mustWrite(t *testing.T, name string, body []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(name), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(name, body, 0o644); err != nil {
		t.Fatal(err)
	}
}
