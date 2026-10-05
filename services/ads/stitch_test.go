package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStitchKeepsFilmTimeline(t *testing.T) {
	handler := fixture(t)
	video, err := handler.stitchMedia("720p")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(video, "http://127.0.0.1:8083/preroll/720p/seg_0.m4s") {
		t.Fatal("pre-roll segment missing")
	}
	pre := strings.Index(video, "/preroll/720p/seg_0.m4s")
	disc := strings.Index(video, "#EXT-X-DISCONTINUITY")
	film0 := strings.Index(video, "http://127.0.0.1:8080/720p/seg_0.m4s")
	film9 := strings.Index(video, "http://127.0.0.1:8080/720p/seg_9.m4s")
	if pre < 0 || disc < pre || film0 < disc || film9 < film0 {
		t.Fatalf("order pre=%d disc=%d film0=%d film9=%d", pre, disc, film0, film9)
	}
	if strings.Contains(video, "METHOD=NONE") == false || !strings.Contains(video, "SAMPLE-AES-CTR") {
		t.Fatal("expected a clear pre-roll and the film key")
	}
	if strings.Contains(video[:film0], "seg_0.m4s\n") && strings.Count(video[:disc], "8080/720p/seg_0") != 0 {
		t.Fatal("film segment appeared before the discontinuity")
	}

	dash, err := handler.stitchDASH()
	if err != nil {
		t.Fatal(err)
	}
	prerollAt := strings.Index(dash, `id="preroll"`)
	filmAt := strings.Index(dash, `id="playpath-bars"`)
	if prerollAt < 0 || filmAt < prerollAt {
		t.Fatal("pre-roll period is not before the film")
	}
	if !strings.Contains(dash, `start="PT5.000S"`) || !strings.Contains(dash, `duration="PT60.000S"`) {
		t.Fatal("film period duration changed")
	}
	if !strings.Contains(dash, `mediaPresentationDuration="PT65.000S"`) {
		t.Fatal("presentation duration is not pre-roll plus film")
	}
	if !strings.Contains(dash, "http://127.0.0.1:8080/720p/seg_$Number$.m4s") {
		t.Fatal("film segments are not on the origin")
	}
	if strings.Contains(dash, "ffefcdab") {
		t.Fatal("stitched menu included the content key")
	}
}

func TestCleanMenuStaysOnOrigin(t *testing.T) {
	handler := fixture(t)
	if handler.CleanHLS() != "http://127.0.0.1:8080/master.m3u8" {
		t.Fatal(handler.CleanHLS())
	}
	if handler.CleanDASH() != "http://127.0.0.1:8080/manifest.mpd" {
		t.Fatal(handler.CleanDASH())
	}
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	for _, path := range []string{"/master.m3u8", "/manifest.mpd", "/"} {
		resp := get(t, srv.URL+path)
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("%s status %d", path, resp.StatusCode)
		}
	}
	stitched := get(t, srv.URL+"/ssai/hls/master.m3u8")
	body, err := io.ReadAll(stitched.Body)
	if err != nil {
		t.Fatal(err)
	}
	if stitched.StatusCode != http.StatusOK {
		t.Fatalf("stitched status %d", stitched.StatusCode)
	}
	if !strings.Contains(string(body), srv.URL+"/ssai/hls/720p/media.m3u8") && !strings.Contains(string(body), "http://127.0.0.1:8083/ssai/hls/720p/media.m3u8") {
		t.Fatalf("master %s", body)
	}
	if strings.Contains(string(body), "http://127.0.0.1:8080/720p/media.m3u8") {
		t.Fatal("stitched master points at the clean media playlist")
	}
	dash := get(t, srv.URL+"/ssai/dash/manifest.mpd")
	if dash.StatusCode != http.StatusOK || dash.Header.Get("Content-Type") != "application/dash+xml" {
		t.Fatalf("dash %d %s", dash.StatusCode, dash.Header.Get("Content-Type"))
	}
}

func TestReadDurationRejectsAudioDrift(t *testing.T) {
	dir := t.TempDir()
	name := filepath.Join(dir, "duration.txt")
	mustWrite(t, name, []byte("video=5.000000\naudio=5.013333\n"))
	if _, _, err := readDuration(name); err != nil {
		t.Fatal(err)
	}
	mustWrite(t, name, []byte("video=5.000000\naudio=5.100000\n"))
	if _, _, err := readDuration(name); err == nil {
		t.Fatal("audio more than 40 ms from video was accepted")
	}
}

func TestNewRejectsBaseURL(t *testing.T) {
	handler := fixture(t)
	got, err := absoluteBase("http://127.0.0.1:8080/")
	if err != nil || got != "http://127.0.0.1:8080" {
		t.Fatalf("%q %v", got, err)
	}
	for _, raw := range []string{"127.0.0.1:8080", "http://127.0.0.1:8080/film", "http://127.0.0.1:8080?x=1", "http://127.0.0.1:8080#frag"} {
		if _, err := New(handler.filmDir, handler.prerollDir, raw, "http://127.0.0.1:8083"); err == nil {
			t.Fatalf("accepted origin %s", raw)
		}
		if _, err := New(handler.filmDir, handler.prerollDir, "http://127.0.0.1:8080", raw); err == nil {
			t.Fatalf("accepted ads %s", raw)
		}
	}
}

func TestVASTMidroll(t *testing.T) {
	handler := fixture(t)
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	resp := get(t, srv.URL+"/vast/midroll.xml")
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	text := string(body)
	if resp.StatusCode != http.StatusOK || resp.Header.Get("Content-Type") != "application/xml" {
		t.Fatalf("status %d type %s", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	if strings.Count(text, "<Linear>") != 1 || strings.Count(text, "<Impression") != 1 {
		t.Fatalf("expected one linear creative and one impression: %s", text)
	}
	if !strings.Contains(text, "http://127.0.0.1:8083/vast/impression") {
		t.Fatal("impression url missing")
	}
	if !strings.Contains(text, `timeOffset="00:00:10.000"`) || !strings.Contains(text, `breakId="midroll"`) {
		t.Fatal("cue is not 10 seconds")
	}
	if !strings.Contains(text, "http://127.0.0.1:8083/preroll/creative.mp4") || strings.Contains(text, "playpath-bars.mp4") {
		t.Fatal("creative is not the progressive pre-roll file")
	}
	if strings.Contains(text, "ffefcdab") {
		t.Fatal("vast document included the content key")
	}
	creative := get(t, srv.URL+"/preroll/creative.mp4")
	creativeBody, err := io.ReadAll(creative.Body)
	if err != nil {
		t.Fatal(err)
	}
	if creative.StatusCode != http.StatusOK || creative.Header.Get("Content-Type") != "video/mp4" || string(creativeBody) != "creative" {
		t.Fatalf("creative status %d type %s", creative.StatusCode, creative.Header.Get("Content-Type"))
	}
	impression := get(t, srv.URL+"/vast/impression")
	if impression.StatusCode != http.StatusNoContent {
		t.Fatalf("impression status %d", impression.StatusCode)
	}
}

func TestPrerollFile(t *testing.T) {
	handler := fixture(t)
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	resp := get(t, srv.URL+"/preroll/720p/seg_0.m4s")
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK || string(body) != "ad" || resp.Header.Get("Content-Type") != "video/mp4" {
		t.Fatalf("status %d type %s body %q", resp.StatusCode, resp.Header.Get("Content-Type"), body)
	}
	missing := get(t, srv.URL+"/preroll/duration.txt")
	if missing.StatusCode != http.StatusNotFound {
		t.Fatalf("duration status %d", missing.StatusCode)
	}
}

func fixture(t *testing.T) *Server {
	t.Helper()
	root := t.TempDir()
	film := filepath.Join(root, "film")
	pre := filepath.Join(root, "preroll")
	mustWrite(t, filepath.Join(film, "master.m3u8"), []byte(`#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720
720p/media.m3u8
`))
	mustWrite(t, filepath.Join(film, "720p", "media.m3u8"), []byte(`#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:6
#EXT-X-MAP:URI="init_0.mp4"
#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,URI="http://127.0.0.1:8082/?keyId=00112233445566778899aabbccddeeff",KEYFORMAT="urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e",KEYFORMATVERSIONS="1"
#EXTINF:6.000000,
seg_0.m4s
#EXTINF:6.000000,
seg_9.m4s
#EXT-X-ENDLIST
`))
	mustWrite(t, filepath.Join(film, "subtitles", "media.m3u8"), []byte("#EXTM3U\n#EXTINF:60.000000,\nplaypath-bars.vtt\n#EXT-X-ENDLIST\n"))
	mustWrite(t, filepath.Join(film, "manifest.mpd"), []byte(`<?xml version="1.0" encoding="UTF-8"?>
<MPD mediaPresentationDuration="PT60.000S">
  <Period id="playpath-bars" duration="PT60.000S">
    <Representation id="720p" bandwidth="1">
      <SegmentTemplate initialization="720p/init_0.mp4" media="720p/seg_$Number$.m4s"/>
    </Representation>
    <BaseURL>subtitles/playpath-bars.vtt</BaseURL>
  </Period>
</MPD>
`))
	mustWrite(t, filepath.Join(pre, "duration.txt"), []byte("video=5.000000\naudio=5.013333\n"))
	mustWrite(t, filepath.Join(pre, "creative.mp4"), []byte("creative"))
	mustWrite(t, filepath.Join(pre, "720p", "seg_0.m4s"), []byte("ad"))
	mustWrite(t, filepath.Join(pre, "720p", "init.mp4"), []byte("init"))
	mustWrite(t, filepath.Join(pre, "1080p", "seg_0.m4s"), []byte("ad"))
	mustWrite(t, filepath.Join(pre, "audio", "seg_0.m4s"), []byte("tone"))
	handler, err := New(film, pre, "http://127.0.0.1:8080", "http://127.0.0.1:8083")
	if err != nil {
		t.Fatal(err)
	}
	return handler
}

func get(t *testing.T, raw string) *http.Response {
	t.Helper()
	resp, err := http.Get(raw)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func mustWrite(t *testing.T, name string, body []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(name), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(name, body, 0o644); err != nil {
		t.Fatal(err)
	}
}
