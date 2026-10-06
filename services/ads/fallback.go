package main

import (
	"encoding/json"
	"errors"
	"net/url"
	"os"
	"strings"
)

// FallbackSession is the clean menu loaded when the stitched menu fails.
// The web and Android sessions use these same menus. This choice does not
// request an impression, and the ads service does not serve the clean menu.
type FallbackSession struct {
	StitchedHLS  string `json:"stitchedHls"`
	StitchedDASH string `json:"stitchedDash"`
	CleanHLS     string `json:"cleanHls"`
	CleanDASH    string `json:"cleanDash"`
}

// LoadFallback reads the stitcher fallback file and checks both menus.
func LoadFallback(path string) (FallbackSession, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return FallbackSession{}, err
	}
	var session FallbackSession
	if err := json.Unmarshal(body, &session); err != nil {
		return FallbackSession{}, err
	}
	if err := session.validate(); err != nil {
		return FallbackSession{}, err
	}
	return session, nil
}

// Fallback is the clean menu for the bases this process was given.
func (s *Server) Fallback() FallbackSession {
	return FallbackSession{
		StitchedHLS:  s.adsBase + "/ssai/hls/master.m3u8",
		StitchedDASH: s.adsBase + "/ssai/dash/manifest.mpd",
		CleanHLS:     s.CleanHLS(),
		CleanDASH:    s.CleanDASH(),
	}
}

func (s FallbackSession) validate() error {
	pairs := []struct {
		stitched string
		clean    string
		hls      bool
	}{
		{stitched: s.StitchedHLS, clean: s.CleanHLS, hls: true},
		{stitched: s.StitchedDASH, clean: s.CleanDASH, hls: false},
	}
	for _, pair := range pairs {
		stitched, err := menuURL(pair.stitched)
		if err != nil {
			return errors.New("stitched url is not a menu")
		}
		clean, err := menuURL(pair.clean)
		if err != nil {
			return errors.New("clean url is not a menu")
		}
		if stitched.Scheme == clean.Scheme && strings.EqualFold(stitched.Host, clean.Host) {
			return errors.New("clean url is on the stitcher")
		}
		if pair.hls {
			if stitched.Path != "/ssai/hls/master.m3u8" || clean.Path != "/master.m3u8" {
				return errors.New("hls fallback is not the clean master")
			}
			continue
		}
		if stitched.Path != "/ssai/dash/manifest.mpd" || clean.Path != "/manifest.mpd" {
			return errors.New("dash fallback is not the clean manifest")
		}
	}
	return nil
}

// CleanMenu is the origin menu for a stitched menu that failed.
// It does not request an impression URL and it does not fetch the film.
func (s FallbackSession) CleanMenu(failed string) (string, error) {
	if err := s.validate(); err != nil {
		return "", err
	}
	raw, err := url.Parse(failed)
	if err != nil || (raw.Scheme != "http" && raw.Scheme != "https") || raw.Host == "" {
		return "", errors.New("stitched url is not a menu")
	}
	raw.RawQuery = ""
	raw.Fragment = ""
	switch {
	case sameMenu(raw.String(), s.StitchedHLS):
		return s.CleanHLS, nil
	case sameMenu(raw.String(), s.StitchedDASH):
		return s.CleanDASH, nil
	default:
		return "", errors.New("stitched url is not a menu")
	}
}

func menuURL(raw string) (*url.URL, error) {
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return nil, errors.New("url is not a menu")
	}
	if parsed.RawQuery != "" || parsed.Fragment != "" {
		return nil, errors.New("url is not a menu")
	}
	if parsed.Path == "" || parsed.Path == "/" || strings.HasSuffix(parsed.Path, "/") {
		return nil, errors.New("url is not a menu")
	}
	return parsed, nil
}

func sameMenu(a, b string) bool {
	left, errA := url.Parse(a)
	right, errB := url.Parse(b)
	if errA != nil || errB != nil {
		return false
	}
	return left.Scheme == right.Scheme && strings.EqualFold(left.Host, right.Host) && left.Path == right.Path
}
