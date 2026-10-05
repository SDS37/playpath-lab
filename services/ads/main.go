// Command ads stitches a pre-roll in front of the protected playpath-bars film.
// The clean film menu stays on origin A. This process does not serve it.
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
	addr := flag.String("addr", "127.0.0.1:8083", "listen address")
	film := flag.String("film", "pipeline/protected/playpath-bars", "protected film package")
	preroll := flag.String("preroll", "pipeline/preroll/playpath-bars", "clear pre-roll package")
	origin := flag.String("origin", "http://127.0.0.1:8080", "origin that serves the clean film")
	public := flag.String("public", "http://127.0.0.1:8083", "base URL of this service")
	flag.Parse()

	handler, err := New(*film, *preroll, *origin, *public)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ads: %s\n", err.Error())
		if errors.Is(err, errNoFilm) {
			fmt.Fprintf(os.Stderr, "run ./pipeline/encrypt.sh from the repository root\n")
		}
		if errors.Is(err, errNoPreroll) {
			fmt.Fprintf(os.Stderr, "run ./pipeline/preroll.sh from the repository root\n")
		}
		os.Exit(1)
	}
	server := &http.Server{
		Addr:              *addr,
		Handler:           logStatus(handler),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("ads listening on http://%s", *addr)
	if err := server.ListenAndServe(); err != nil {
		fmt.Fprintf(os.Stderr, "ads: %s\n", err.Error())
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
