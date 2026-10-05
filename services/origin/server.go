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
	root           string
	refuseSegments bool
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

// SetRefuseSegments makes media segments (.m4s) return 503.
// Menus and init segments stay available, so a later retry can ask for the same segment.
func (s *Server) SetRefuseSegments(on bool) {
	s.refuseSegments = on
}

// ServeHTTP answers GET and HEAD for a file in the package tree.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
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
	if s.refuseSegments && strings.EqualFold(filepath.Ext(full), ".m4s") {
		http.Error(w, "segment refused", http.StatusServiceUnavailable)
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
	w.Header().Set("Content-Type", s.contentType(full))
	http.ServeContent(w, r, info.Name(), info.ModTime(), f)
}

func (s *Server) file(urlPath string) (string, bool) {
	if urlPath == "" || strings.HasSuffix(urlPath, "/") {
		return "", false
	}
	// Treat a backslash as a separator before the name check, so a Windows
	// path cannot retarget the basename after that check.
	cleaned := path.Clean("/" + strings.ReplaceAll(urlPath, `\`, "/"))
	if cleaned == "/" || cleaned == "." {
		return "", false
	}
	rel := strings.TrimPrefix(cleaned, "/")
	full := filepath.Clean(filepath.Join(s.root, filepath.FromSlash(rel)))
	if !inside(s.root, full) || forbidden(filepath.Base(full)) {
		return "", false
	}
	return full, true
}

func forbidden(name string) bool {
	switch strings.ToLower(name) {
	case "lab-key.json", "playpath-bars.mp4":
		return true
	default:
		return false
	}
}

func inside(root, full string) bool {
	rel, err := filepath.Rel(root, full)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func (s *Server) contentType(full string) string {
	switch strings.ToLower(filepath.Ext(full)) {
	case ".m3u8":
		return "application/vnd.apple.mpegurl"
	case ".mpd":
		return "application/dash+xml"
	case ".m4s", ".mp4":
		if s.audioFile(full) {
			return "audio/mp4"
		}
		return "video/mp4"
	case ".vtt":
		return "text/vtt"
	default:
		return "application/octet-stream"
	}
}

func (s *Server) audioFile(full string) bool {
	rel, err := filepath.Rel(s.root, full)
	if err != nil {
		return false
	}
	for _, part := range strings.Split(filepath.ToSlash(rel), "/") {
		if strings.EqualFold(part, "audio") {
			return true
		}
	}
	return false
}
