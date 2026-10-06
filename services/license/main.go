// Command license answers Clear Key requests for the playpath-bars lab key.
// It listens on 127.0.0.1:8082. It does not serve media.
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8082", "listen address")
	keyFile := flag.String("key", "services/license/lab-key.json", "lab key config")
	flag.Parse()

	handler, err := New(*keyFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "license: %s\n", err.Error())
		os.Exit(1)
	}
	server := &http.Server{
		Addr:              *addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("license listening on http://%s", *addr)
	if err := server.ListenAndServe(); err != nil {
		fmt.Fprintf(os.Stderr, "license: %s\n", err.Error())
		os.Exit(1)
	}
}
