// Command origin serves the protected playpath-bars package.
// Origin A listens on 127.0.0.1:8080. Origin B is the same server on 127.0.0.1:8081.
package main

import (
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "listen address")
	dir := flag.String("dir", "pipeline/protected/playpath-bars", "package directory")
	refuse := flag.Bool("refuse-segments", false, "answer 503 for media segments")
	flag.Parse()

	handler, err := New(*dir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "origin: %s\n", err.Error())
		if errors.Is(err, os.ErrNotExist) {
			fmt.Fprintf(os.Stderr, "run ./pipeline/encrypt.sh from the repository root\n")
		}
		os.Exit(1)
	}
	handler.SetRefuseSegments(*refuse)
	server := &http.Server{
		Addr:              *addr,
		Handler:           logStatus(handler),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("origin listening on http://%s", *addr)
	if err := server.ListenAndServe(); err != nil {
		fmt.Fprintf(os.Stderr, "origin: %s\n", err.Error())
		os.Exit(1)
	}
}

func logStatus(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s %d", r.Method, r.URL.Path, rec.status)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}
