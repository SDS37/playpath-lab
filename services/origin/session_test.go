package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadSession(t *testing.T) {
	session, err := LoadSession("session.json")
	if err != nil {
		t.Fatal(err)
	}
	if session.BaseURL != "http://127.0.0.1:8080" {
		t.Fatalf("base %s", session.BaseURL)
	}
	if session.BackupBaseURL != "http://127.0.0.1:8081" {
		t.Fatalf("backup %s", session.BackupBaseURL)
	}
	got, err := session.BackupURL("http://127.0.0.1:8080/720p/seg_5.m4s")
	if err != nil {
		t.Fatal(err)
	}
	if got != "http://127.0.0.1:8081/720p/seg_5.m4s" {
		t.Fatalf("backup url %s", got)
	}
	if strings.Contains(got, "seg_0") {
		t.Fatalf("backup url restarted the title: %s", got)
	}
}

func TestBackupURL(t *testing.T) {
	session := PlaybackSession{
		BaseURL:       "http://127.0.0.1:8080",
		BackupBaseURL: "http://127.0.0.1:8081",
	}
	tests := []struct {
		name    string
		failed  string
		want    string
		wantErr bool
	}{
		{name: "same segment", failed: "http://127.0.0.1:8080/1080p/seg_5.m4s", want: "http://127.0.0.1:8081/1080p/seg_5.m4s"},
		{name: "audio segment", failed: "http://127.0.0.1:8080/audio/seg_9.m4s", want: "http://127.0.0.1:8081/audio/seg_9.m4s"},
		{name: "other origin", failed: "http://127.0.0.1:9/720p/seg_5.m4s", wantErr: true},
		{name: "directory", failed: "http://127.0.0.1:8080/720p/", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := session.BackupURL(tt.failed)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected an error")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got != tt.want {
				t.Fatalf("got %s, want %s", got, tt.want)
			}
		})
	}
}

func TestSameSegmentOnBackupOrigin(t *testing.T) {
	dir := t.TempDir()
	body := []byte("segment-five")
	mustWrite(t, filepath.Join(dir, "720p", "seg_5.m4s"), body)
	mustWrite(t, filepath.Join(dir, "master.m3u8"), []byte("#EXTM3U\n"))

	primary, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}
	primary.SetRefuseSegments(true)
	backup, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}
	primarySrv := httptest.NewServer(primary)
	t.Cleanup(primarySrv.Close)
	backupSrv := httptest.NewServer(backup)
	t.Cleanup(backupSrv.Close)

	session := PlaybackSession{BaseURL: primarySrv.URL, BackupBaseURL: backupSrv.URL}
	failed := primarySrv.URL + "/720p/seg_5.m4s"
	refused := get(t, failed)
	if refused.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("primary status %d", refused.StatusCode)
	}
	if refused.Header.Get("Location") != "" {
		t.Fatal("primary redirected the segment")
	}
	menu := get(t, primarySrv.URL+"/master.m3u8")
	if menu.StatusCode != http.StatusOK {
		t.Fatalf("menu status %d", menu.StatusCode)
	}

	next, err := session.BackupURL(failed)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(next, "/720p/seg_5.m4s") {
		t.Fatalf("backup path %s", next)
	}
	got := get(t, next)
	if got.StatusCode != http.StatusOK {
		t.Fatalf("backup status %d", got.StatusCode)
	}
	payload, err := io.ReadAll(got.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(payload) != string(body) {
		t.Fatalf("backup body %q", payload)
	}
	primary.SetRefuseSegments(false)
	again := get(t, failed)
	if again.StatusCode != http.StatusOK {
		t.Fatalf("primary after resume %d", again.StatusCode)
	}
	primaryBody, err := io.ReadAll(again.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(primaryBody) != string(payload) {
		t.Fatal("origins serve different bytes")
	}
	if again.Header.Get("Content-Type") != got.Header.Get("Content-Type") {
		t.Fatalf("content type %s, backup %s", again.Header.Get("Content-Type"), got.Header.Get("Content-Type"))
	}
	if again.Header.Get("Last-Modified") == "" || again.Header.Get("Last-Modified") != got.Header.Get("Last-Modified") {
		t.Fatalf("Last-Modified %s, backup %s", again.Header.Get("Last-Modified"), got.Header.Get("Last-Modified"))
	}
}

func get(t *testing.T, raw string) *http.Response {
	t.Helper()
	resp, err := http.Get(raw)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		resp.Body.Close()
	})
	return resp
}

func TestRefuseSegmentsLeavesMenus(t *testing.T) {
	dir := t.TempDir()
	mustWrite(t, filepath.Join(dir, "master.m3u8"), []byte("#EXTM3U\n"))
	mustWrite(t, filepath.Join(dir, "720p", "seg_0.m4s"), []byte("media"))
	mustWrite(t, filepath.Join(dir, "720p", "init_0.mp4"), []byte("init"))
	handler, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}
	handler.SetRefuseSegments(true)
	for _, tt := range []struct {
		path   string
		status int
	}{
		{path: "/master.m3u8", status: http.StatusOK},
		{path: "/720p/init_0.mp4", status: http.StatusOK},
		{path: "/720p/seg_0.m4s", status: http.StatusServiceUnavailable},
	} {
		req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1"+tt.path, nil)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != tt.status {
			t.Fatalf("%s status %d, want %d", tt.path, rec.Code, tt.status)
		}
		if tt.status == http.StatusServiceUnavailable && strings.Contains(rec.Body.String(), "media") {
			t.Fatal("refused response included the segment")
		}
	}
}

func TestSessionFileIsNotAKey(t *testing.T) {
	body, err := os.ReadFile("session.json")
	if err != nil {
		t.Fatal(err)
	}
	key, err := os.ReadFile(filepath.Join("..", "license", "lab-key.json"))
	if err != nil {
		t.Fatal(err)
	}
	var parsed struct {
		Key string `json:"key"`
	}
	if err := json.Unmarshal(key, &parsed); err != nil {
		t.Fatal(err)
	}
	if parsed.Key != "" && strings.Contains(string(body), parsed.Key) {
		t.Fatal("session file contains the content key")
	}
}
