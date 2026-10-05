package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadFallback(t *testing.T) {
	session, err := LoadFallback("session.json")
	if err != nil {
		t.Fatal(err)
	}
	handler := fixture(t)
	if handler.Fallback() != session {
		t.Fatalf("running bases %+v, file %+v", handler.Fallback(), session)
	}
	hls, err := session.CleanMenu(session.StitchedHLS)
	if err != nil {
		t.Fatal(err)
	}
	if hls != "http://127.0.0.1:8080/master.m3u8" {
		t.Fatalf("hls %s", hls)
	}
	dash, err := session.CleanMenu(session.StitchedDASH + "?break=midroll")
	if err != nil {
		t.Fatal(err)
	}
	if dash != "http://127.0.0.1:8080/manifest.mpd" {
		t.Fatalf("dash %s", dash)
	}
	if strings.Contains(hls, "8083") || strings.Contains(dash, "preroll") || strings.Contains(dash, "ssai") {
		t.Fatal("clean menu is still a stitched presentation")
	}
	if _, err := session.CleanMenu("http://127.0.0.1:8083/vast/impression"); err == nil {
		t.Fatal("impression url was treated as a menu")
	}
	other, err := New(handler.filmDir, handler.prerollDir, "http://127.0.0.1:8080", "http://127.0.0.1:9090")
	if err != nil {
		t.Fatal(err)
	}
	if other.Fallback().StitchedHLS != "http://127.0.0.1:9090/ssai/hls/master.m3u8" || other.Fallback().CleanHLS != "http://127.0.0.1:8080/master.m3u8" {
		t.Fatalf("public base %+v", other.Fallback())
	}
}

func TestCleanMenu(t *testing.T) {
	session := FallbackSession{
		StitchedHLS:  "http://127.0.0.1:9090/ssai/hls/master.m3u8",
		StitchedDASH: "http://127.0.0.1:9090/ssai/dash/manifest.mpd",
		CleanHLS:     "http://127.0.0.1:8080/master.m3u8",
		CleanDASH:    "http://127.0.0.1:8080/manifest.mpd",
	}
	tests := []struct {
		name    string
		failed  string
		want    string
		wantErr bool
	}{
		{name: "hls", failed: "http://127.0.0.1:9090/ssai/hls/master.m3u8", want: "http://127.0.0.1:8080/master.m3u8"},
		{name: "dash", failed: "http://127.0.0.1:9090/ssai/dash/manifest.mpd", want: "http://127.0.0.1:8080/manifest.mpd"},
		{name: "impression", failed: "http://127.0.0.1:9090/vast/impression", wantErr: true},
		{name: "clean already", failed: "http://127.0.0.1:8080/master.m3u8", wantErr: true},
		{name: "other host", failed: "http://127.0.0.1:9/ssai/hls/master.m3u8", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := session.CleanMenu(tt.failed)
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

func TestCleanMenuDoesNotRequestImpression(t *testing.T) {
	previous := http.DefaultTransport
	http.DefaultTransport = roundTripper(func(req *http.Request) (*http.Response, error) {
		t.Errorf("fallback requested %s", req.URL)
		return nil, errors.New("blocked")
	})
	t.Cleanup(func() { http.DefaultTransport = previous })
	session, err := LoadFallback("session.json")
	if err != nil {
		t.Fatal(err)
	}
	got, err := session.CleanMenu(session.StitchedHLS)
	if err != nil {
		t.Fatal(err)
	}
	if got != session.CleanHLS {
		t.Fatalf("clean %s", got)
	}
}

type roundTripper func(*http.Request) (*http.Response, error)

func (r roundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	return r(req)
}

func TestStitcherDoesNotRedirectToCleanMenu(t *testing.T) {
	handler := fixture(t)
	if err := os.Remove(filepath.Join(handler.filmDir, "master.m3u8")); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	for _, path := range []string{"/ssai/hls/master.m3u8", "/master.m3u8", "/manifest.mpd"} {
		resp := get(t, srv.URL+path)
		if resp.StatusCode == http.StatusOK {
			t.Fatalf("%s was served by the stitcher", path)
		}
		if resp.Header.Get("Location") != "" {
			t.Fatalf("%s redirected to %s", path, resp.Header.Get("Location"))
		}
		payload, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatal(err)
		}
		body := string(payload)
		if strings.Contains(body, "127.0.0.1:8080") {
			t.Fatalf("%s body named the clean origin: %s", path, body)
		}
	}
	session := handler.Fallback()
	srv.Close()
	got, err := session.CleanMenu(session.StitchedDASH)
	if err != nil {
		t.Fatal(err)
	}
	if got != "http://127.0.0.1:8080/manifest.mpd" {
		t.Fatalf("clean dash %s", got)
	}
}

func TestFallbackFileIsNotAKey(t *testing.T) {
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
		t.Fatal("fallback file contains the content key")
	}
}
