package main

import (
	"bytes"
	_ "embed"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

//go:embed vast/midroll.xml
var vastMidroll []byte

// vastDocumentBase is the origin written in vast/midroll.xml. Serving replaces it with the configured public base.
const vastDocumentBase = "http://127.0.0.1:8083"

var (
	errNoFilm    = errors.New("film package is missing")
	errNoPreroll = errors.New("pre-roll package is missing")
)

// Server stitches a clear pre-roll in front of the film menus.
// Film bytes stay on the origin. This server does not own that URL.
type Server struct {
	filmDir    string
	prerollDir string
	originBase string
	adsBase    string
	video      float64
	audio      float64
}

// New checks the film package, the pre-roll, and both base URLs.
func New(filmDir, prerollDir, originBase, adsBase string) (*Server, error) {
	film, err := filepath.Abs(filmDir)
	if err != nil {
		return nil, err
	}
	pre, err := filepath.Abs(prerollDir)
	if err != nil {
		return nil, err
	}
	if _, err := os.Stat(filepath.Join(film, "master.m3u8")); err != nil {
		return nil, errNoFilm
	}
	if _, err := os.Stat(filepath.Join(film, "manifest.mpd")); err != nil {
		return nil, errNoFilm
	}
	video, audio, err := readDuration(filepath.Join(pre, "duration.txt"))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, errNoPreroll
		}
		return nil, err
	}
	if _, err := os.Stat(filepath.Join(pre, "creative.mp4")); err != nil {
		if os.IsNotExist(err) {
			return nil, errNoPreroll
		}
		return nil, err
	}
	origin, err := absoluteBase(originBase)
	if err != nil {
		return nil, errors.New("origin url is not an origin root")
	}
	ads, err := absoluteBase(adsBase)
	if err != nil {
		return nil, errors.New("ads url is not an origin root")
	}
	return &Server{
		filmDir:    film,
		prerollDir: pre,
		originBase: origin,
		adsBase:    ads,
		video:      video,
		audio:      audio,
	}, nil
}

// CleanHLS is the film master on the origin. The stitcher does not serve it.
func (s *Server) CleanHLS() string {
	return s.originBase + "/master.m3u8"
}

// CleanDASH is the film MPD on the origin. The stitcher does not serve it.
func (s *Server) CleanDASH() string {
	return s.originBase + "/manifest.mpd"
}

// ServeHTTP returns the stitched menus, the VAST mid-roll, or a pre-roll file.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	switch r.URL.Path {
	case "/master.m3u8", "/manifest.mpd":
		http.NotFound(w, r)
		return
	case "/ssai/hls/master.m3u8":
		s.servePlaylist(w, r, "master.m3u8", "application/vnd.apple.mpegurl", s.stitchMaster)
		return
	case "/ssai/dash/manifest.mpd":
		s.servePlaylist(w, r, "manifest.mpd", "application/dash+xml", s.stitchDASH)
		return
	case "/vast/midroll.xml":
		w.Header().Set("Content-Type", "application/xml")
		http.ServeContent(w, r, "midroll.xml", time.Time{}, bytes.NewReader(s.vastDocument()))
		return
	case "/vast/impression":
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if rendition, ok := strings.CutPrefix(r.URL.Path, "/ssai/hls/"); ok && strings.HasSuffix(rendition, "/media.m3u8") {
		name := strings.TrimSuffix(rendition, "/media.m3u8")
		s.servePlaylist(w, r, filepath.Join(name, "media.m3u8"), "application/vnd.apple.mpegurl", func() (string, error) {
			return s.stitchMedia(name)
		})
		return
	}
	if strings.HasPrefix(r.URL.Path, "/preroll/") {
		s.servePreroll(w, r)
		return
	}
	http.NotFound(w, r)
}

func (s *Server) vastDocument() []byte {
	return bytes.ReplaceAll(vastMidroll, []byte(vastDocumentBase), []byte(s.adsBase))
}

func (s *Server) servePlaylist(w http.ResponseWriter, r *http.Request, filmRel, ctype string, build func() (string, error)) {
	body, err := build()
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	info, err := os.Stat(filepath.Join(s.filmDir, filmRel))
	mod := time.Now()
	if err == nil {
		mod = info.ModTime()
	}
	w.Header().Set("Content-Type", ctype)
	http.ServeContent(w, r, path.Base(filmRel), mod, bytes.NewReader([]byte(body)))
}

func (s *Server) stitchMaster() (string, error) {
	raw, err := os.ReadFile(filepath.Join(s.filmDir, "master.m3u8"))
	if err != nil {
		return "", errors.New("film playlist is missing")
	}
	var b strings.Builder
	for _, line := range strings.Split(string(raw), "\n") {
		trim := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(trim, "#EXT-X-MEDIA:"):
			b.WriteString(rewriteAttrURI(trim, s.adsBase+"/ssai/hls/"))
		case trim != "" && !strings.HasPrefix(trim, "#"):
			b.WriteString(s.adsBase + "/ssai/hls/" + trim)
		default:
			b.WriteString(line)
		}
		b.WriteByte('\n')
	}
	return b.String(), nil
}

func (s *Server) stitchMedia(rendition string) (string, error) {
	if rendition == "" || strings.Contains(rendition, "/") || strings.Contains(rendition, "..") {
		return "", errors.New("film playlist is missing")
	}
	raw, err := os.ReadFile(filepath.Join(s.filmDir, rendition, "media.m3u8"))
	if err != nil {
		return "", errors.New("film playlist is missing")
	}
	if rendition == "subtitles" {
		return s.stitchSubtitles(string(raw)), nil
	}
	mapURI, keyLine, segments, err := parseMedia(string(raw))
	if err != nil {
		return "", err
	}
	lead := s.video
	if rendition == "audio" {
		lead = s.audio
	}
	target := 6
	if ceilSeconds(lead) > target {
		target = ceilSeconds(lead)
	}
	for _, seg := range segments {
		if ceilSeconds(seg.duration) > target {
			target = ceilSeconds(seg.duration)
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-INDEPENDENT-SEGMENTS\n", target)
	fmt.Fprintf(&b, "#EXT-X-MAP:URI=%q\n", s.adsBase+"/preroll/"+rendition+"/init.mp4")
	b.WriteString("#EXT-X-KEY:METHOD=NONE\n")
	fmt.Fprintf(&b, "#EXTINF:%.6f,\n%s\n", lead, s.adsBase+"/preroll/"+rendition+"/seg_0.m4s")
	b.WriteString("#EXT-X-DISCONTINUITY\n")
	fmt.Fprintf(&b, "#EXT-X-MAP:URI=%q\n", s.originJoin(rendition, mapURI))
	if keyLine != "" {
		b.WriteString(keyLine)
		b.WriteByte('\n')
	}
	for _, seg := range segments {
		fmt.Fprintf(&b, "#EXTINF:%.6f,\n%s\n", seg.duration, s.originJoin(rendition, seg.uri))
	}
	b.WriteString("#EXT-X-ENDLIST\n")
	return b.String(), nil
}

func (s *Server) stitchSubtitles(raw string) string {
	_, _, segments, err := parseMedia(raw)
	film := s.originBase + "/subtitles/playpath-bars.vtt"
	filmDur := 60.0
	if err == nil && len(segments) > 0 {
		film = s.originJoin("subtitles", segments[0].uri)
		filmDur = segments[0].duration
	}
	var b strings.Builder
	b.WriteString("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:60\n#EXT-X-PLAYLIST-TYPE:VOD\n")
	fmt.Fprintf(&b, "#EXTINF:%.6f,\n%s\n", s.video, s.adsBase+"/preroll/subtitles/preroll.vtt")
	b.WriteString("#EXT-X-DISCONTINUITY\n")
	fmt.Fprintf(&b, "#EXTINF:%.6f,\n%s\n", filmDur, film)
	b.WriteString("#EXT-X-ENDLIST\n")
	return b.String()
}

func (s *Server) stitchDASH() (string, error) {
	raw, err := os.ReadFile(filepath.Join(s.filmDir, "manifest.mpd"))
	if err != nil {
		return "", errors.New("film playlist is missing")
	}
	mpd := string(raw)
	filmDur, err := presentationDuration(mpd)
	if err != nil {
		return "", err
	}
	if !strings.Contains(mpd, `<Period id="playpath-bars"`) {
		return "", errors.New("film playlist is invalid")
	}
	mpd = absolutizeFilm(mpd, s.originBase)
	start := isoDuration(s.video)
	mpd = periodStart.ReplaceAllString(mpd, `<Period id="playpath-bars" start="`+start+`"$1>`)
	total := isoDuration(filmDur + s.video)
	mpd = presentationAttr.ReplaceAllString(mpd, `mediaPresentationDuration="`+total+`"`)
	bw720 := s.bits(filepath.Join(s.prerollDir, "720p", "seg_0.m4s"), s.video)
	bw1080 := s.bits(filepath.Join(s.prerollDir, "1080p", "seg_0.m4s"), s.video)
	bwAudio := s.bits(filepath.Join(s.prerollDir, "audio", "seg_0.m4s"), s.audio)
	preroll := s.prerollPeriod(bw720, bw1080, bwAudio)
	idx := strings.Index(mpd, `<Period id="playpath-bars"`)
	if idx < 0 {
		return "", errors.New("film playlist is invalid")
	}
	return mpd[:idx] + preroll + mpd[idx:], nil
}

func (s *Server) prerollPeriod(bw720, bw1080, bwAudio int) string {
	videoDur := int(s.video*1000 + 0.5)
	audioDur := int(s.audio*1000 + 0.5)
	base := s.adsBase + "/preroll/"
	return fmt.Sprintf(`  <Period id="preroll" start="PT0S" duration="%s">
    <AdaptationSet contentType="video" mimeType="video/mp4" segmentAlignment="true" startWithSAP="1">
      <Representation id="720p" bandwidth="%d" width="1280" height="720" frameRate="30" codecs="avc1.64001f">
        <SegmentTemplate timescale="1000" duration="%d" startNumber="0" initialization="%s720p/init.mp4" media="%s720p/seg_$Number$.m4s"/>
      </Representation>
      <Representation id="1080p" bandwidth="%d" width="1920" height="1080" frameRate="30" codecs="avc1.640028">
        <SegmentTemplate timescale="1000" duration="%d" startNumber="0" initialization="%s1080p/init.mp4" media="%s1080p/seg_$Number$.m4s"/>
      </Representation>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="en" segmentAlignment="true" startWithSAP="1">
      <Representation id="audio" bandwidth="%d" audioSamplingRate="48000" codecs="mp4a.40.2">
        <AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2"/>
        <SegmentTemplate timescale="1000" duration="%d" startNumber="0" initialization="%saudio/init.mp4" media="%saudio/seg_$Number$.m4s"/>
      </Representation>
    </AdaptationSet>
    <AdaptationSet contentType="text" mimeType="text/vtt" lang="en">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="subtitle"/>
      <Representation id="subs" bandwidth="26">
        <BaseURL>%ssubtitles/preroll.vtt</BaseURL>
      </Representation>
    </AdaptationSet>
  </Period>
`, isoDuration(s.video), bw720, videoDur, base, base, bw1080, videoDur, base, base, bwAudio, audioDur, base, base, base)
}

func (s *Server) servePreroll(w http.ResponseWriter, r *http.Request) {
	rel := strings.TrimPrefix(r.URL.Path, "/preroll/")
	if rel == "" || strings.HasSuffix(r.URL.Path, "/") || strings.Contains(rel, `\`) {
		http.NotFound(w, r)
		return
	}
	cleaned := path.Clean("/" + rel)
	name := strings.TrimPrefix(cleaned, "/")
	if name == "" || path.Base(name) == "duration.txt" || path.Base(name) == "lab-key.json" || path.Base(name) == "playpath-bars.mp4" {
		http.NotFound(w, r)
		return
	}
	full := filepath.Join(s.prerollDir, filepath.FromSlash(name))
	rootRel, err := filepath.Rel(s.prerollDir, full)
	if err != nil || rootRel == ".." || strings.HasPrefix(rootRel, ".."+string(filepath.Separator)) {
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

func (s *Server) originJoin(rendition, uri string) string {
	if strings.Contains(uri, "://") {
		return uri
	}
	return s.originBase + "/" + rendition + "/" + uri
}

func (s *Server) bits(file string, seconds float64) int {
	info, err := os.Stat(file)
	if err != nil || seconds <= 0 {
		return 1
	}
	return int(float64(info.Size()*8)/seconds + 0.5)
}

type segment struct {
	duration float64
	uri      string
}

func parseMedia(raw string) (mapURI, keyLine string, segments []segment, err error) {
	lines := strings.Split(raw, "\n")
	for i := 0; i < len(lines); i++ {
		line := strings.TrimSpace(lines[i])
		switch {
		case strings.HasPrefix(line, "#EXT-X-MAP:"):
			uri, ok := quotedAttr(line, "URI")
			if !ok {
				return "", "", nil, errors.New("film playlist is invalid")
			}
			mapURI = uri
		case strings.HasPrefix(line, "#EXT-X-KEY:"):
			keyLine = line
		case strings.HasPrefix(line, "#EXTINF:"):
			durText := strings.TrimPrefix(line, "#EXTINF:")
			durText = strings.TrimSuffix(durText, ",")
			dur, convErr := strconv.ParseFloat(durText, 64)
			if convErr != nil || i+1 >= len(lines) {
				return "", "", nil, errors.New("film playlist is invalid")
			}
			i++
			uri := strings.TrimSpace(lines[i])
			if uri == "" || strings.HasPrefix(uri, "#") {
				return "", "", nil, errors.New("film playlist is invalid")
			}
			segments = append(segments, segment{duration: dur, uri: uri})
		}
	}
	if len(segments) == 0 {
		return "", "", nil, errors.New("film playlist is invalid")
	}
	return mapURI, keyLine, segments, nil
}

func readDuration(path string) (video, audio float64, err error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0, 0, err
	}
	for _, line := range strings.Split(string(raw), "\n") {
		key, val, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		n, convErr := strconv.ParseFloat(val, 64)
		if convErr != nil {
			return 0, 0, errors.New("pre-roll duration is invalid")
		}
		switch key {
		case "video":
			video = n
		case "audio":
			audio = n
		}
	}
	delta := video - audio
	if delta < 0 {
		delta = -delta
	}
	if video < 4.5 || video > 5.5 || audio <= 0 || delta > 0.04 {
		return 0, 0, errors.New("pre-roll duration is invalid")
	}
	return video, audio, nil
}

func absoluteBase(raw string) (string, error) {
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return "", errors.New("url is not an origin root")
	}
	if parsed.Path != "" && parsed.Path != "/" {
		return "", errors.New("url is not an origin root")
	}
	if parsed.RawQuery != "" || parsed.Fragment != "" {
		return "", errors.New("url is not an origin root")
	}
	parsed.Path = ""
	return strings.TrimRight(parsed.String(), "/"), nil
}

func rewriteAttrURI(line, prefix string) string {
	uri, ok := quotedAttr(line, "URI")
	if !ok || strings.Contains(uri, "://") {
		return line
	}
	return strings.Replace(line, `URI="`+uri+`"`, `URI="`+prefix+uri+`"`, 1)
}

func quotedAttr(line, name string) (string, bool) {
	key := name + `="`
	i := strings.Index(line, key)
	if i < 0 {
		return "", false
	}
	rest := line[i+len(key):]
	j := strings.Index(rest, `"`)
	if j < 0 {
		return "", false
	}
	return rest[:j], true
}

func absolutizeFilm(mpd, origin string) string {
	mpd = attrURI.ReplaceAllStringFunc(mpd, func(match string) string {
		parts := attrURI.FindStringSubmatch(match)
		if len(parts) != 3 || strings.Contains(parts[2], "://") {
			return match
		}
		return parts[1] + `="` + origin + "/" + parts[2] + `"`
	})
	return baseURL.ReplaceAllStringFunc(mpd, func(match string) string {
		parts := baseURL.FindStringSubmatch(match)
		if len(parts) != 2 || strings.Contains(parts[1], "://") {
			return match
		}
		return "<BaseURL>" + origin + "/" + parts[1] + "</BaseURL>"
	})
}

func presentationDuration(mpd string) (float64, error) {
	m := presentationAttr.FindStringSubmatch(mpd)
	if m == nil {
		return 0, errors.New("film playlist is invalid")
	}
	return parseISO(m[1])
}

func parseISO(raw string) (float64, error) {
	if !strings.HasPrefix(raw, "PT") || !strings.HasSuffix(raw, "S") {
		return 0, errors.New("film playlist is invalid")
	}
	n, err := strconv.ParseFloat(strings.TrimSuffix(strings.TrimPrefix(raw, "PT"), "S"), 64)
	if err != nil {
		return 0, errors.New("film playlist is invalid")
	}
	return n, nil
}

func isoDuration(seconds float64) string {
	return fmt.Sprintf("PT%.3fS", seconds)
}

func ceilSeconds(seconds float64) int {
	n := int(seconds)
	if float64(n) < seconds {
		return n + 1
	}
	return n
}

func contentType(name string) string {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".m3u8":
		return "application/vnd.apple.mpegurl"
	case ".mpd":
		return "application/dash+xml"
	case ".m4s", ".mp4":
		if strings.Contains(strings.ToLower(filepath.ToSlash(name)), "/audio/") {
			return "audio/mp4"
		}
		return "video/mp4"
	case ".vtt":
		return "text/vtt"
	default:
		return "application/octet-stream"
	}
}

var (
	attrURI          = regexp.MustCompile(`(initialization|media)="([^"]+)"`)
	baseURL          = regexp.MustCompile(`<BaseURL>([^<]+)</BaseURL>`)
	periodStart      = regexp.MustCompile(`<Period id="playpath-bars"([^>]*)>`)
	presentationAttr = regexp.MustCompile(`mediaPresentationDuration="(PT[^"]+)"`)
)
