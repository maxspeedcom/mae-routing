// Copyright (c) MAE Routing (maesuaisystem.com).

//go:build windows

package main

// Self-update. The app asks the website which Windows build is newest (the same /api/versions the download page
// uses), a minute after start and then every hour. When there is a newer one it says so once, adds
// "Update to <version>…" to the menu and mentions it in the icon's tooltip. Choosing it asks
// first, then downloads the installer, checks its SHA-256 against the website, and runs it silently with
// administrator rights (one Windows permission prompt). The installer stops this app and the service, replaces
// the files and starts both again, so the user does not have to download anything by hand.

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/ncruces/zenity"
	"golang.org/x/sys/windows"
	"tailscale.com/version"
)

const (
	versionsURL  = "https://" + zone + "/api/versions"
	updateEvery  = time.Hour   // a new build is noticed within an hour
	firstCheckIn = time.Minute
)

// release is the "windows" entry of /api/versions.
type release struct {
	Version string `json:"version"` // 1.104.2-8
	Base    string `json:"base"`    // 1.104.2
	Build   int    `json:"build"`   // 8
	File    string `json:"file"`    // MAERouting-1.104.2-8-setup.exe
	SHA256  string `json:"sha256"`
}

var (
	maeLongRE   = regexp.MustCompile(`^(\d+\.\d+\.\d+)-mae(\d+)$`)
	installerRE = regexp.MustCompile(`^MAERouting-\d+\.\d+\.\d+-\d+-setup\.exe$`)
	sha256RE    = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

// ourBuild is this app's version, e.g. ("1.104.2", 7); ok is false for a build that is not one of ours.
func ourBuild() (base string, build int, ok bool) {
	m := maeLongRE.FindStringSubmatch(version.Long())
	if m == nil {
		return "", 0, false
	}
	b, err := strconv.Atoi(m[2])
	return m[1], b, err == nil
}

// cmpVersion compares dotted versions such as 1.104.2 and 1.106.0.
func cmpVersion(x, y string) int {
	xs, ys := strings.Split(x, "."), strings.Split(y, ".")
	for i := 0; i < len(xs) || i < len(ys); i++ {
		var a, b int
		if i < len(xs) {
			a, _ = strconv.Atoi(xs[i])
		}
		if i < len(ys) {
			b, _ = strconv.Atoi(ys[i])
		}
		if a != b {
			if a < b {
				return -1
			}
			return 1
		}
	}
	return 0
}

func (r release) newerThanUs() bool {
	base, build, ok := ourBuild()
	if !ok || r.Build == 0 || !installerRE.MatchString(r.File) || !sha256RE.MatchString(strings.ToLower(r.SHA256)) {
		return false
	}
	if c := cmpVersion(r.Base, base); c != 0 {
		return c > 0
	}
	return r.Build > build
}

func fetchLatest(ctx context.Context) (release, error) {
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", versionsURL, nil)
	if err != nil {
		return release{}, err
	}
	req.Header.Set("User-Agent", "MAERouting/"+shownVersion())
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return release{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return release{}, fmt.Errorf("%s: %s", versionsURL, resp.Status)
	}
	var v struct {
		Windows release `json:"windows"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&v); err != nil {
		return release{}, err
	}
	return v.Windows, nil
}

// checkUpdates runs for the life of the app.
func (a *app) checkUpdates() {
	removeOldInstallers()
	time.Sleep(firstCheckIn)
	for {
		r, err := fetchLatest(a.ctx)
		if err != nil {
			log.Printf("update check: %v", err)
		} else {
			a.mu.Lock()
			var told bool
			if r.newerThanUs() {
				told = a.update != nil && a.update.Version == r.Version
				a.update = &r
			} else {
				a.update = nil
			}
			has := a.update != nil
			a.mu.Unlock()
			if has && !told {
				log.Printf("update available: %s", r.Version)
				zenity.Notify(fmt.Sprintf("MAE Routing %s is available. Click the MAE Routing icon and choose \"Update to %s…\".",
					r.Version, r.Version), zenity.Title(appName))
			}
			a.kick()
		}
		time.Sleep(updateEvery)
	}
}

// checkNow is the "Check for updates" menu item.
func (a *app) checkNow() {
	r, err := fetchLatest(a.ctx)
	if err != nil {
		zenity.Error(fmt.Sprintf("Could not check for updates: %v\n\nCheck the internet connection and try again.", err), zenity.Title(appName))
		return
	}
	a.mu.Lock()
	if r.newerThanUs() {
		a.update = &r
	} else {
		a.update = nil
	}
	has := a.update != nil
	a.mu.Unlock()
	a.kick()
	if has {
		a.installUpdate()
		return
	}
	zenity.Info(fmt.Sprintf("You have the latest version of MAE Routing (%s).", shownVersion()), zenity.Title(appName))
}

// installUpdate is the "Update to …" menu item.
func (a *app) installUpdate() {
	a.mu.Lock()
	r := a.update
	if r == nil || a.updating {
		a.mu.Unlock()
		return
	}
	a.updating = true
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		a.updating = false
		a.mu.Unlock()
	}()

	if zenity.Question(fmt.Sprintf("Download and install MAE Routing %s now?\n\nYou are using %s. The connection stops for a few seconds "+
		"while it installs, then MAE Routing starts again by itself.", r.Version, shownVersion()),
		zenity.Title("Update MAE Routing"), zenity.OKLabel("Update"), zenity.CancelLabel("Later")) != nil {
		return
	}
	zenity.Notify(fmt.Sprintf("Downloading MAE Routing %s…", r.Version), zenity.Title(appName))
	path, err := downloadInstaller(a.ctx, *r)
	if err != nil {
		log.Printf("update download: %v", err)
		zenity.Error(fmt.Sprintf("The update could not be downloaded: %v\n\nTry again later, or download it from https://%s/download", err, zone),
			zenity.Title(appName))
		return
	}
	// One Windows permission prompt. The installer (/S = no questions) closes this app, updates, and starts it again.
	if err := runElevated(path, "/S"); err != nil {
		os.Remove(path)
		if errors.Is(err, windows.ERROR_CANCELLED) {
			return // the user said No to the permission prompt
		}
		log.Printf("update install: %v", err)
		zenity.Error(fmt.Sprintf("The update could not be installed: %v", err), zenity.Title(appName))
		return
	}
	log.Printf("installing %s", r.Version)
}

// downloadInstaller saves the installer in the temp folder and checks it against the website's SHA-256.
func downloadInstaller(ctx context.Context, r release) (string, error) {
	if !installerRE.MatchString(r.File) {
		return "", fmt.Errorf("unexpected file name %q", r.File)
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Minute)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", "https://"+zone+"/download/"+r.File, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "MAERouting/"+shownVersion())
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", errors.New(resp.Status)
	}
	f, err := os.Create(filepath.Join(os.TempDir(), r.File))
	if err != nil {
		return "", err
	}
	h := sha256.New()
	_, err = io.Copy(io.MultiWriter(f, h), io.LimitReader(resp.Body, 512<<20))
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil && hex.EncodeToString(h.Sum(nil)) != strings.ToLower(r.SHA256) {
		err = errors.New("the download does not match the checksum on the website")
	}
	if err != nil {
		os.Remove(f.Name())
		return "", err
	}
	return f.Name(), nil
}

func runElevated(path, args string) error {
	verb, _ := windows.UTF16PtrFromString("runas")
	file, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	params, _ := windows.UTF16PtrFromString(args)
	return windows.ShellExecute(0, verb, file, params, nil, windows.SW_SHOWNORMAL)
}

// removeOldInstallers deletes installers left in the temp folder by earlier updates (they have finished by now).
func removeOldInstallers() {
	old, _ := filepath.Glob(filepath.Join(os.TempDir(), "MAERouting-*-setup.exe"))
	for _, p := range old {
		if fi, err := os.Stat(p); err == nil && time.Since(fi.ModTime()) > time.Hour {
			os.Remove(p)
		}
	}
}
