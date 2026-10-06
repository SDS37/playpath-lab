package main

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

const webOrigin = "http://127.0.0.1:5173"

var (
	errBadRequest = errors.New("license request is invalid")
	errUnknown    = errors.New("unknown key id")
)

// Server answers a Clear Key license request for one lab key.
// The key stays in this process. The handler does not serve media.
type Server struct {
	kid []byte
	key []byte
}

type labKey struct {
	KeySystem string `json:"keySystem"`
	KeyID     string `json:"keyId"`
	Key       string `json:"key"`
}

type licenseRequest struct {
	Kids []string `json:"kids"`
}

type licenseResponse struct {
	Keys []contentKey `json:"keys"`
	Type string       `json:"type"`
}

type contentKey struct {
	Kty string `json:"kty"`
	K   string `json:"k"`
	Kid string `json:"kid"`
}

// New reads the lab key config. The key id and the key are different 16-byte values.
func New(path string) (*Server, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg labKey
	if err := json.Unmarshal(body, &cfg); err != nil {
		return nil, err
	}
	if cfg.KeySystem != "org.w3.clearkey" {
		return nil, errors.New("lab key config is not org.w3.clearkey")
	}
	kid, err := hex.DecodeString(cfg.KeyID)
	if err != nil || len(kid) != 16 {
		return nil, errors.New("lab key id must be 16 bytes")
	}
	key, err := hex.DecodeString(cfg.Key)
	if err != nil || len(key) != 16 {
		return nil, errors.New("lab key must be 16 bytes")
	}
	if bytes.Equal(kid, key) {
		return nil, errors.New("lab key id and key must differ")
	}
	return &Server{kid: kid, key: key}, nil
}

// ServeHTTP answers POST / with a Clear Key license, or a non-success status.
// The log records the key id. It does not record the key.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.allowWeb(w, r)
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		log.Printf("%s %s %d keyId=-", r.Method, r.URL.Path, http.StatusNotFound)
		return
	}
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		log.Printf("%s %s %d keyId=-", r.Method, r.URL.Path, http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST, OPTIONS")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		log.Printf("%s %s %d keyId=-", r.Method, r.URL.Path, http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<16))
	if err != nil {
		http.Error(w, errBadRequest.Error(), http.StatusBadRequest)
		log.Printf("%s %s %d keyId=-", r.Method, r.URL.Path, http.StatusBadRequest)
		return
	}
	payload, logged, err := s.license(body)
	if err != nil {
		code := http.StatusForbidden
		if errors.Is(err, errBadRequest) {
			code = http.StatusBadRequest
		}
		http.Error(w, err.Error(), code)
		log.Printf("%s %s %d keyId=%s", r.Method, r.URL.Path, code, logged)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write(payload); err != nil {
		log.Printf("write: %s", err.Error())
	}
	log.Printf("%s %s %d keyId=%s", r.Method, r.URL.Path, http.StatusOK, logged)
}

func (s *Server) allowWeb(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Origin") != webOrigin {
		return
	}
	w.Header().Set("Access-Control-Allow-Origin", webOrigin)
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Vary", "Origin")
}

func (s *Server) license(body []byte) ([]byte, string, error) {
	var req licenseRequest
	if err := json.Unmarshal(body, &req); err != nil || len(req.Kids) == 0 {
		return nil, "-", errBadRequest
	}
	logged := s.logID(req.Kids)
	for _, raw := range req.Kids {
		got, ok := decodeKid(raw)
		if ok && bytes.Equal(got, s.kid) {
			payload, err := json.Marshal(licenseResponse{
				Keys: []contentKey{{
					Kty: "oct",
					K:   base64.RawURLEncoding.EncodeToString(s.key),
					Kid: base64.RawURLEncoding.EncodeToString(s.kid),
				}},
				Type: "temporary",
			})
			if err != nil {
				return nil, logged, err
			}
			return append(payload, '\n'), logged, nil
		}
	}
	return nil, logged, errUnknown
}

func (s *Server) logID(kids []string) string {
	var parts []string
	for _, raw := range kids {
		got, ok := decodeKid(raw)
		if !ok || bytes.Equal(got, s.key) {
			continue
		}
		parts = append(parts, hex.EncodeToString(got))
	}
	if len(parts) == 0 {
		return "-"
	}
	return strings.Join(parts, ",")
}

func decodeKid(raw string) ([]byte, bool) {
	raw = strings.TrimSpace(raw)
	if got, err := hex.DecodeString(raw); err == nil && len(got) == 16 {
		return got, true
	}
	for _, enc := range []*base64.Encoding{
		base64.RawURLEncoding,
		base64.URLEncoding,
		base64.RawStdEncoding,
		base64.StdEncoding,
	} {
		got, err := enc.DecodeString(raw)
		if err == nil && len(got) == 16 {
			return got, true
		}
	}
	return nil, false
}
