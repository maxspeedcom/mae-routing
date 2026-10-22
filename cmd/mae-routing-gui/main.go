// Copyright (c) MAE Routing (maesuaisystem.com).

//go:build windows

// Command mae-routing-gui is the MAE Routing tray app for Windows (MAERouting.exe).
//
// It talks to the MAERouting service (maeroutingd.exe) over the LocalAPI named pipe,
// shows the connection state in the notification area, and signs in to an organisation's network by its
// name: <org> becomes the control server https://<org>.routing.maesuaisystem.com.
// Thai labels throughout.
package main

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"log"
	"net/netip"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"

	"fyne.io/systray"
	"github.com/atotto/clipboard"
	"github.com/ncruces/zenity"
	"github.com/toqueteos/webbrowser"
	"golang.org/x/sys/windows"
	"tailscale.com/client/local"
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tailcfg"
	"tailscale.com/version"
)

const (
	appName    = "MAE Routing"
	zone       = "routing.maesuaisystem.com"
	consoleURL = "https://routing.maesuaisystem.com/admin/"
	signupURL  = "https://routing.maesuaisystem.com/signup"
	maxPeers   = 60
)

var (
	//go:embed icons/on.ico
	iconOn []byte
	//go:embed icons/off.ico
	iconOff []byte
	//go:embed icons/warn.ico
	iconWarn []byte

	slugRE = regexp.MustCompile(`^[a-z][a-z0-9-]{1,30}[a-z0-9]$`)
)

type app struct {
	lc  local.Client
	ctx context.Context

	mu        sync.Mutex
	status    *ipnstate.Status
	prefs     *ipn.Prefs
	cur       ipn.LoginProfile
	profiles  []ipn.LoginProfile
	svcErr    error
	signature string // what the menu currently shows; rebuild only when it changes

	rebuildCh  chan struct{}
	menuCancel context.CancelFunc
}

func main() {
	if !singleInstance() {
		return
	}
	setupLog()
	a := &app{ctx: context.Background(), rebuildCh: make(chan struct{}, 1)}
	systray.Run(a.onReady, func() {})
}

// singleInstance keeps one tray icon per Windows session.
func singleInstance() bool {
	name, _ := windows.UTF16PtrFromString(`Local\MAERoutingTray`)
	_, err := windows.CreateMutex(nil, false, name)
	return !errors.Is(err, windows.ERROR_ALREADY_EXISTS)
}

func setupLog() {
	dir := filepath.Join(os.Getenv("LOCALAPPDATA"), "MAERouting")
	if os.MkdirAll(dir, 0o755) != nil {
		return
	}
	path := filepath.Join(dir, "tray.log")
	if fi, err := os.Stat(path); err == nil && fi.Size() > 2<<20 {
		os.Rename(path, path+".old")
	}
	if f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644); err == nil {
		log.SetOutput(f)
	}
}

func (a *app) onReady() {
	systray.SetIcon(iconOff)
	systray.SetTooltip(appName)
	go a.watchIPNBus()
	go func() {
		t := time.NewTicker(15 * time.Second) // peers come and go without a state change
		defer t.Stop()
		for range t.C {
			a.kick()
		}
	}()
	a.kick()
	for range a.rebuildCh {
		a.refresh()
		a.rebuild(false)
	}
}

func (a *app) kick() {
	select {
	case a.rebuildCh <- struct{}{}:
	default:
	}
}

func (a *app) refresh() {
	ctx, cancel := context.WithTimeout(a.ctx, 5*time.Second)
	defer cancel()
	st, err := a.lc.Status(ctx)
	prefs, perr := a.lc.GetPrefs(ctx)
	cur, all, _ := a.lc.ProfileStatus(ctx)
	a.mu.Lock()
	defer a.mu.Unlock()
	a.svcErr = err
	a.status = st
	if perr == nil {
		a.prefs = prefs
	}
	a.cur, a.profiles = cur, all
}

// orgOf turns https://acme.routing.maesuaisystem.com into "acme".
func orgOf(controlURL string) string {
	u := strings.TrimSuffix(strings.TrimPrefix(controlURL, "https://"), "/")
	if s, ok := strings.CutSuffix(u, "."+zone); ok {
		return s
	}
	return u
}

func firstIPv4(ips []netip.Addr) string {
	for _, ip := range ips {
		if ip.Is4() {
			return ip.String()
		}
	}
	if len(ips) > 0 {
		return ips[0].String()
	}
	return ""
}

func shortName(p *ipnstate.PeerStatus) string {
	if n, _, ok := strings.Cut(p.DNSName, "."); ok && n != "" {
		return n
	}
	return p.HostName
}

// rebuild redraws the whole menu (fyne systray cannot remove separators), but only when its content changed.
func (a *app) rebuild(force bool) {
	a.mu.Lock()
	st, prefs, cur, profiles, svcErr := a.status, a.prefs, a.cur, a.profiles, a.svcErr
	a.mu.Unlock()

	state := ""
	if st != nil {
		state = st.BackendState
	}
	var peers []*ipnstate.PeerStatus
	if st != nil {
		for _, p := range st.Peer {
			peers = append(peers, p)
		}
	}
	slices.SortFunc(peers, func(x, y *ipnstate.PeerStatus) int {
		if x.Online != y.Online {
			if x.Online {
				return -1
			}
			return 1
		}
		return strings.Compare(shortName(x), shortName(y))
	})

	sig := fmt.Sprint(state, svcErr != nil, cur.ID, len(profiles))
	if prefs != nil {
		sig += fmt.Sprint(prefs.WantRunning, prefs.CorpDNS, prefs.RouteAll, prefs.ShieldsUp, prefs.ForceDaemon,
			prefs.ExitNodeID, prefs.ExitNodeAllowLANAccess)
	}
	if st != nil && st.Self != nil {
		sig += firstIPv4(st.Self.TailscaleIPs)
	}
	for _, p := range peers {
		sig += fmt.Sprint(p.ID, p.Online, p.ExitNodeOption, p.ExitNode, shortName(p))
	}
	a.mu.Lock()
	if sig == a.signature && !force {
		a.mu.Unlock()
		return
	}
	a.signature = sig
	if a.menuCancel != nil {
		a.menuCancel()
	}
	ctx, cancel := context.WithCancel(a.ctx)
	a.menuCancel = cancel
	a.mu.Unlock()

	systray.ResetMenu()
	org := orgOf(cur.ControlURL)
	if prefs != nil && org == "" {
		org = orgOf(prefs.ControlURL)
	}

	// --- status + tray icon
	switch {
	case svcErr != nil:
		systray.SetIcon(iconWarn)
		systray.SetTooltip(appName + " — service not running")
		info(systray.AddMenuItem("MAE Routing service not running", "The MAERouting service is stopped. Restart the computer or reinstall."))
		systray.AddSeparator()
	case state == ipn.Running.String():
		systray.SetIcon(iconOn)
		systray.SetTooltip(fmt.Sprintf("%s — connected (%s)", appName, org))
		info(systray.AddMenuItem("● Connected · "+org, ""))
	case state == ipn.NeedsLogin.String() || state == ipn.NoState.String() || cur.ID == "":
		systray.SetIcon(iconWarn)
		systray.SetTooltip(appName + " — not signed in")
		info(systray.AddMenuItem("Not signed in", ""))
	case state == ipn.NeedsMachineAuth.String():
		systray.SetIcon(iconWarn)
		systray.SetTooltip(appName + " — waiting for approval")
		info(systray.AddMenuItem("Waiting for an admin to approve this machine", ""))
	case state == ipn.Starting.String():
		systray.SetIcon(iconOff)
		systray.SetTooltip(appName + " — connecting…")
		info(systray.AddMenuItem("Connecting… · "+org, ""))
	default:
		systray.SetIcon(iconOff)
		systray.SetTooltip(fmt.Sprintf("%s — disconnected (%s)", appName, org))
		info(systray.AddMenuItem("○ Disconnected · "+org, ""))
	}
	if cur.Name != "" && svcErr == nil {
		info(systray.AddMenuItem("Account: "+cur.Name, ""))
	}
	if svcErr != nil {
		a.addFooter(ctx)
		return
	}
	systray.AddSeparator()

	loggedIn := cur.ID != "" && state != ipn.NeedsLogin.String() && state != ipn.NoState.String()
	if !loggedIn {
		onClick(ctx, systray.AddMenuItem("Sign in…", "Connect this machine to your organisation's network"), a.login)
		onClick(ctx, systray.AddMenuItem("No network yet? Create one free", ""), func() { webbrowser.Open(signupURL) })
		a.addFooter(ctx)
		return
	}

	if prefs != nil && prefs.WantRunning {
		onClick(ctx, systray.AddMenuItem("Disconnect", ""), func() { a.setRunning(false) })
	} else {
		onClick(ctx, systray.AddMenuItem("Connect", ""), func() { a.setRunning(true) })
	}
	systray.AddSeparator()

	// --- this device + peers
	if st != nil && st.Self != nil && len(st.Self.TailscaleIPs) > 0 {
		ip := firstIPv4(st.Self.TailscaleIPs)
		self := systray.AddMenuItem(fmt.Sprintf("This machine: %s (%s)", shortName(st.Self), ip), "Click to copy the IP address")
		onClick(ctx, self, func() { copyIP(shortName(st.Self), ip) })
	}
	devices := systray.AddMenuItem(fmt.Sprintf("Network devices (%d)", len(peers)), "")
	if len(peers) == 0 {
		info(devices.AddSubMenuItem("No other machines yet", ""))
	}
	for i, p := range peers {
		if i == maxPeers {
			more := devices.AddSubMenuItem(fmt.Sprintf("… and %d more (see the admin console)", len(peers)-maxPeers), "")
			onClick(ctx, more, func() { webbrowser.Open(consoleURL) })
			break
		}
		dot := "○ "
		if p.Online {
			dot = "● "
		}
		ip := firstIPv4(p.TailscaleIPs)
		it := devices.AddSubMenuItem(fmt.Sprintf("%s%s    %s", dot, shortName(p), ip), "Click to copy the IP address")
		onClick(ctx, it, func() { copyIP(shortName(p), ip) })
	}

	// --- exit nodes
	exit := systray.AddMenuItem("Exit node", "Send all internet traffic through another machine in the network")
	using := prefs != nil && !prefs.ExitNodeID.IsZero()
	none := exit.AddSubMenuItemCheckbox("None", "", !using)
	onClick(ctx, none, func() { a.setExitNode("") })
	found := false
	for _, p := range peers {
		if !p.ExitNodeOption {
			continue
		}
		found = true
		label := shortName(p)
		if !p.Online {
			label += " (offline)"
		}
		it := exit.AddSubMenuItemCheckbox(label, "", prefs != nil && prefs.ExitNodeID == p.ID)
		onClick(ctx, it, func() { a.setExitNode(p.ID) })
	}
	if !found {
		info(exit.AddSubMenuItem("No exit nodes in this network", ""))
	}
	exit.AddSeparator()
	lan := exit.AddSubMenuItemCheckbox("Allow local network access", "", prefs != nil && prefs.ExitNodeAllowLANAccess)
	onClick(ctx, lan, func() { a.toggle(func(mp *ipn.MaskedPrefs, p *ipn.Prefs) { mp.ExitNodeAllowLANAccess, mp.ExitNodeAllowLANAccessSet = !p.ExitNodeAllowLANAccess, true }) })
	systray.AddSeparator()

	// --- settings
	set := systray.AddMenuItem("Settings", "")
	if prefs != nil {
		dns := set.AddSubMenuItemCheckbox("Use network DNS (MagicDNS)", "", prefs.CorpDNS)
		onClick(ctx, dns, func() { a.toggle(func(mp *ipn.MaskedPrefs, p *ipn.Prefs) { mp.CorpDNS, mp.CorpDNSSet = !p.CorpDNS, true }) })
		routes := set.AddSubMenuItemCheckbox("Use subnet routes", "", prefs.RouteAll)
		onClick(ctx, routes, func() { a.toggle(func(mp *ipn.MaskedPrefs, p *ipn.Prefs) { mp.RouteAll, mp.RouteAllSet = !p.RouteAll, true }) })
		shields := set.AddSubMenuItemCheckbox("Block incoming connections", "", prefs.ShieldsUp)
		onClick(ctx, shields, func() { a.toggle(func(mp *ipn.MaskedPrefs, p *ipn.Prefs) { mp.ShieldsUp, mp.ShieldsUpSet = !p.ShieldsUp, true }) })
		unattended := set.AddSubMenuItemCheckbox("Run unattended", "Keep running when nobody is signed in to Windows (for servers)", prefs.ForceDaemon)
		onClick(ctx, unattended, func() { a.toggle(func(mp *ipn.MaskedPrefs, p *ipn.Prefs) { mp.ForceDaemon, mp.ForceDaemonSet = !p.ForceDaemon, true }) })
	}

	// --- networks (login profiles)
	nets := systray.AddMenuItem("Network: "+org, "")
	for _, pr := range profiles {
		it := nets.AddSubMenuItemCheckbox(fmt.Sprintf("%s  (%s)", orgOf(pr.ControlURL), pr.Name), "", pr.ID == cur.ID)
		onClick(ctx, it, func() {
			if pr.ID != cur.ID {
				a.do("Switch network", func(c context.Context) error { return a.lc.SwitchProfile(c, pr.ID) })
			}
		})
	}
	nets.AddSeparator()
	onClick(ctx, nets.AddSubMenuItem("Sign in to another network…", ""), a.login)
	onClick(ctx, nets.AddSubMenuItem("Sign out of this network", ""), a.logout)
	onClick(ctx, systray.AddMenuItem("Open admin console", consoleURL), func() { webbrowser.Open(consoleURL) })
	a.addFooter(ctx)
}

func (a *app) addFooter(ctx context.Context) {
	systray.AddSeparator()
	onClick(ctx, systray.AddMenuItem("About MAE Routing", ""), about)
	onClick(ctx, systray.AddMenuItem("Exit", "Close this icon (the connection keeps running)"), systray.Quit)
}

func info(it *systray.MenuItem) { it.Disable() }

func onClick(ctx context.Context, it *systray.MenuItem, fn func()) {
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case <-it.ClickedCh:
				fn()
			}
		}
	}()
}

// ---------- actions ----------

func (a *app) do(what string, fn func(context.Context) error) {
	ctx, cancel := context.WithTimeout(a.ctx, 20*time.Second)
	defer cancel()
	if err := fn(ctx); err != nil {
		log.Printf("%s: %v", what, err)
		zenity.Error(fmt.Sprintf("%s failed\n\n%v", what, err), zenity.Title(appName))
	}
	a.kick()
}

func (a *app) setRunning(on bool) {
	a.do("Change connection", func(ctx context.Context) error {
		_, err := a.lc.EditPrefs(ctx, &ipn.MaskedPrefs{Prefs: ipn.Prefs{WantRunning: on}, WantRunningSet: true})
		return err
	})
}

func (a *app) setExitNode(id tailcfg.StableNodeID) {
	a.do("Set exit node", func(ctx context.Context) error {
		_, err := a.lc.EditPrefs(ctx, &ipn.MaskedPrefs{Prefs: ipn.Prefs{ExitNodeID: id}, ExitNodeIDSet: true})
		return err
	})
}

func (a *app) toggle(set func(mp *ipn.MaskedPrefs, cur *ipn.Prefs)) {
	a.do("Save settings", func(ctx context.Context) error {
		cur, err := a.lc.GetPrefs(ctx)
		if err != nil {
			return err
		}
		mp := &ipn.MaskedPrefs{}
		set(mp, cur)
		_, err = a.lc.EditPrefs(ctx, mp)
		return err
	})
}

// login asks for the organisation's network name and starts the browser sign-in against
// https://<name>.routing.maesuaisystem.com. The browser shows which device is joining before it is added.
func (a *app) login() {
	last := ""
	a.mu.Lock()
	if a.prefs != nil {
		last = orgOf(a.prefs.ControlURL)
	}
	loggedIn := a.cur.ID != "" && a.status != nil && a.status.BackendState != ipn.NeedsLogin.String()
	a.mu.Unlock()
	if strings.Contains(last, ".") || last == "login" {
		last = ""
	}
	name, err := zenity.Entry("Your network name\n(the first part of name.routing.maesuaisystem.com, e.g. acme)",
		zenity.Title("Sign in to MAE Routing"), zenity.EntryText(last), zenity.OKLabel("Next"), zenity.CancelLabel("Cancel"))
	if err != nil {
		return // cancelled
	}
	name = strings.ToLower(strings.TrimSpace(name))
	name = strings.TrimSuffix(strings.TrimPrefix(strings.TrimPrefix(name, "https://"), "http://"), "/")
	name = strings.TrimSuffix(name, "."+zone)
	if !slugRE.MatchString(name) {
		zenity.Error("Invalid network name. Use a-z, 0-9 and -, 3–32 characters.", zenity.Title(appName))
		return
	}
	controlURL := "https://" + name + "." + zone
	a.do("Sign in", func(ctx context.Context) error {
		if loggedIn {
			// like `tailscale login`: keep the current network as its own profile and add a new one
			if err := a.lc.SwitchToEmptyProfile(ctx); err != nil {
				return err
			}
		}
		prefs := ipn.NewPrefs()
		prefs.ControlURL = controlURL
		prefs.WantRunning = true
		prefs.CorpDNS = true
		prefs.RouteAll = true
		if err := a.lc.Start(ctx, ipn.Options{UpdatePrefs: prefs}); err != nil {
			return err
		}
		return a.lc.StartLoginInteractive(ctx) // the URL arrives on the IPN bus (BrowseToURL)
	})
}

func (a *app) logout() {
	if zenity.Question("Sign out of this network?\nThis machine will leave the network until you sign in again.",
		zenity.Title(appName), zenity.OKLabel("Sign out"), zenity.CancelLabel("Cancel")) != nil {
		return
	}
	a.do("Sign out", func(ctx context.Context) error { return a.lc.Logout(ctx) })
}

func copyIP(name, ip string) {
	if ip == "" {
		return
	}
	if err := clipboard.WriteAll(ip); err != nil {
		log.Printf("clipboard: %v", err)
		return
	}
	zenity.Notify(fmt.Sprintf("Copied the IP address of %s: %s", name, ip), zenity.Title(appName))
}

func about() {
	zenity.Info(fmt.Sprintf("%s %s\n\nPrivate networks for organisations\nhttps://%s\n\nOpen source licences: THIRD-PARTY-NOTICES.txt in the program folder",
		appName, version.Short(), zone), zenity.Title("About "+appName))
}

// ---------- IPN bus ----------

func (a *app) watchIPNBus() {
	for {
		if err := a.watchOnce(); err != nil {
			log.Printf("ipn bus: %v", err)
		}
		a.kick()
		time.Sleep(3 * time.Second)
	}
}

func (a *app) watchOnce() error {
	w, err := a.lc.WatchIPNBus(a.ctx, ipn.NotifyInitialState)
	if err != nil {
		return err
	}
	defer w.Close()
	for {
		n, err := w.Next()
		if err != nil {
			return err
		}
		if n.BrowseToURL != nil && *n.BrowseToURL != "" {
			log.Printf("opening sign-in page")
			if err := webbrowser.Open(*n.BrowseToURL); err != nil {
				log.Printf("open browser: %v", err)
			}
		}
		if n.LoginFinished != nil {
			zenity.Notify("Signed in. This machine is now on the network.", zenity.Title(appName))
		}
		if n.State != nil || n.Prefs != nil || n.LoginFinished != nil {
			a.kick()
		}
	}
}
