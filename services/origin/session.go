package main

import (
	"encoding/json"
	"errors"
	"net/url"
	"os"
	"strings"
)

// PlaybackSession is the backup base URL the player session reads.
// The apps are not built yet. This is the configuration they will use.
type PlaybackSession struct {
	BaseURL       string `json:"baseUrl"`
	BackupBaseURL string `json:"backupBaseUrl"`
}

// LoadSession reads a playback session file and checks both origins.
func LoadSession(path string) (PlaybackSession, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return PlaybackSession{}, err
	}
	var session PlaybackSession
	if err := json.Unmarshal(body, &session); err != nil {
		return PlaybackSession{}, err
	}
	if err := session.validate(); err != nil {
		return PlaybackSession{}, err
	}
	return session, nil
}

func (s PlaybackSession) validate() error {
	base, err := originRoot(s.BaseURL)
	if err != nil {
		return errors.New("base url is not an origin root")
	}
	backup, err := originRoot(s.BackupBaseURL)
	if err != nil {
		return errors.New("backup base url is not an origin root")
	}
	if base.Scheme == backup.Scheme && strings.EqualFold(base.Host, backup.Host) {
		return errors.New("backup base url matches the primary origin")
	}
	return nil
}

// BackupURL returns the same segment path on the backup origin.
// A failed seg_5 stays seg_5. The title does not restart at seg_0.
func (s PlaybackSession) BackupURL(failed string) (string, error) {
	if err := s.validate(); err != nil {
		return "", err
	}
	base, err := originRoot(s.BaseURL)
	if err != nil {
		return "", err
	}
	backup, err := originRoot(s.BackupBaseURL)
	if err != nil {
		return "", err
	}
	raw, err := url.Parse(failed)
	if err != nil || raw.Scheme == "" || raw.Host == "" {
		return "", errors.New("segment url is not on the primary origin")
	}
	if raw.Scheme != base.Scheme || !strings.EqualFold(raw.Host, base.Host) {
		return "", errors.New("segment url is not on the primary origin")
	}
	if raw.Path == "" || raw.Path == "/" || strings.HasSuffix(raw.Path, "/") {
		return "", errors.New("segment url has no file")
	}
	next := *backup
	next.Path = raw.Path
	next.RawQuery = raw.RawQuery
	return next.String(), nil
}

func originRoot(raw string) (*url.URL, error) {
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return nil, errors.New("url is not an origin root")
	}
	if parsed.Path != "" && parsed.Path != "/" {
		return nil, errors.New("url is not an origin root")
	}
	if parsed.RawQuery != "" || parsed.Fragment != "" {
		return nil, errors.New("url is not an origin root")
	}
	parsed.Path = ""
	return parsed, nil
}
