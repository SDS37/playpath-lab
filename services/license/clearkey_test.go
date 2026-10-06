package main

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestKnownAndUnknownKey(t *testing.T) {
	handler := loadLab(t)
	kid := base64.RawURLEncoding.EncodeToString(handler.kid)
	key := base64.RawURLEncoding.EncodeToString(handler.key)
	hexKid := hex.EncodeToString(handler.kid)

	tests := []struct {
		name   string
		body   string
		status int
		grant  bool
	}{
		{name: "base64url", body: `{"kids":["` + kid + `"],"type":"temporary"}`, status: http.StatusOK, grant: true},
		{name: "hex from the menu", body: `{"kids":["` + hexKid + `"],"type":"temporary"}`, status: http.StatusOK, grant: true},
		{name: "unknown", body: `{"kids":["aaaaaaaaaaaaaaaaaaaaaa"],"type":"temporary"}`, status: http.StatusForbidden},
		{name: "empty", body: `{"kids":[]}`, status: http.StatusBadRequest},
		{name: "not json", body: `not-a-license`, status: http.StatusBadRequest},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := post(t, handler, "/", tt.body, "")
			if rec.Code != tt.status {
				t.Fatalf("status %d, want %d", rec.Code, tt.status)
			}
			if rec.Header().Get("Location") != "" {
				t.Fatalf("redirected to %s", rec.Header().Get("Location"))
			}
			if strings.Contains(rec.Body.String(), "master.m3u8") || strings.Contains(rec.Body.String(), "pipeline/package") {
				t.Fatal("response named the clear package")
			}
			if !tt.grant {
				if strings.Contains(rec.Body.String(), key) || strings.Contains(strings.ToLower(rec.Body.String()), hex.EncodeToString(handler.key)) {
					t.Fatal("error response included the content key")
				}
				return
			}
			if rec.Header().Get("Content-Type") != "application/json" {
				t.Fatalf("content type %s", rec.Header().Get("Content-Type"))
			}
			var doc licenseResponse
			if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
				t.Fatal(err)
			}
			if doc.Type != "temporary" || len(doc.Keys) != 1 || doc.Keys[0].Kty != "oct" {
				t.Fatalf("license %#v", doc)
			}
			if doc.Keys[0].K != key || doc.Keys[0].Kid != kid {
				t.Fatal("license did not name the lab key id and key")
			}
		})
	}
}

func TestDoesNotRedirectOrLogTheKey(t *testing.T) {
	handler := loadLab(t)
	var buf bytes.Buffer
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(os.Stderr) })

	rec := post(t, handler, "/master.m3u8", `{"kids":["aaaaaaaaaaaaaaaaaaaaaa"]}`, "")
	if rec.Code != http.StatusNotFound || rec.Header().Get("Location") != "" {
		t.Fatalf("clear path status %d location %q", rec.Code, rec.Header().Get("Location"))
	}

	kid := base64.RawURLEncoding.EncodeToString(handler.kid)
	rec = post(t, handler, "/", `{"kids":["`+kid+`"]}`, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d", rec.Code)
	}
	keyHex := hex.EncodeToString(handler.key)
	logged := buf.String()
	if !strings.Contains(logged, hex.EncodeToString(handler.kid)) {
		t.Fatal("log omitted the key id")
	}
	if strings.Contains(logged, keyHex) || strings.Contains(logged, base64.RawURLEncoding.EncodeToString(handler.key)) {
		t.Fatal("log included the content key")
	}
}

func TestWebOriginCanReadTheLicense(t *testing.T) {
	handler := loadLab(t)
	kid := base64.RawURLEncoding.EncodeToString(handler.kid)
	preflight := httptest.NewRequest(http.MethodOptions, "http://127.0.0.1:8082/", nil)
	preflight.Header.Set("Origin", webOrigin)
	preflight.Header.Set("Access-Control-Request-Method", "POST")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, preflight)
	if rec.Code != http.StatusNoContent || rec.Header().Get("Access-Control-Allow-Origin") != webOrigin {
		t.Fatalf("preflight %d origin %q", rec.Code, rec.Header().Get("Access-Control-Allow-Origin"))
	}
	got := post(t, handler, "/", `{"kids":["`+kid+`"]}`, webOrigin)
	if got.Code != http.StatusOK || got.Header().Get("Access-Control-Allow-Origin") != webOrigin {
		t.Fatalf("post %d origin %q", got.Code, got.Header().Get("Access-Control-Allow-Origin"))
	}
	other := post(t, handler, "/", `{"kids":["`+kid+`"]}`, "http://example.test")
	if other.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Fatalf("unexpected origin %q", other.Header().Get("Access-Control-Allow-Origin"))
	}
}

func TestMethodNotAllowed(t *testing.T) {
	handler := loadLab(t)
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:8082/", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed || rec.Header().Get("Allow") != "POST, OPTIONS" {
		t.Fatalf("status %d allow %q", rec.Code, rec.Header().Get("Allow"))
	}
}

func loadLab(t *testing.T) *Server {
	t.Helper()
	handler, err := New("lab-key.json")
	if err != nil {
		t.Fatal(err)
	}
	return handler
}

func post(t *testing.T, handler http.Handler, path, body, origin string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:8082"+path, strings.NewReader(body))
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}
