package main

import (
	"errors"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// Server serves one package tree over HTTP. It does not list directories
// and it does not serve the lab key.
type Server struct {
	root string
}

// New checks that dir is a directory and returns a server rooted there.
func New(dir string) (*Server, error) {
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(abs)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, errNotDir
	}
	return &Server{root: abs}, nil
}

var errNotDir = errors.New("origin root is not a directory")

// ServeHTTP answers GET and HEAD for a file in the package tree.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	full, ok := s.file(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}
	info, err := os.Stat(full)
	if err != nil || info.IsDir() {
		http.NotFound(w, r)
		return
	}
	f, err := os.Open(full)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer func() {
		if err := f.Close(); err != nil {
			log.Printf("close: %s", err.Error())
		}
	}()
	w.Header().Set("Content-Type", contentType(full))
	http.ServeContent(w, r, info.Name(), info.ModTime(), f)
}

func (s *Server) file(urlPath string) (string, bool) {
	if urlPath == "" || strings.HasSuffix(urlPath, "/") {
		return "", false
	}
	cleaned := path.Clean("/" + urlPath)
	if cleaned == "/" || cleaned == "." {
		return "", false
	}
	base := path.Base(cleaned)
	if base == "lab-key.json" || base == "playpath-bars.mp4" {
		return "", false
	}
	rel := strings.TrimPrefix(cleaned, "/")
	full := filepath.Join(s.root, filepath.FromSlash(rel))
	if !inside(s.root, full) {
		return "", false
	}
	return full, true
}

func inside(root, full string) bool {
	rel, err := filepath.Rel(root, full)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func contentType(name string) string {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".m3u8":
		return "application/vnd.apple.mpegurl"
	case ".mpd":
		return "application/dash+xml"
	case ".m4s", ".mp4":
		return "video/mp4"
	case ".vtt":
		return "text/vtt"
	default:
		return "application/octet-stream"
	}
}
