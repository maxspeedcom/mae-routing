#!/usr/bin/env python3
"""Turn a tailscale/tailscale checkout into the MAE Routing client (Windows first).

usage: python3 mae/apply-branding.py .

Every edit must match exactly once (or at least once for EDITS_ALL) so a new upstream version that moved
code fails loudly instead of silently shipping a half-branded build. What changes and why:
- Windows identity (service, named pipe, %ProgramData% dir, registry keys, wintun adapter name + GUID,
  firewall rule names, legacy prefs dir): MAE Routing must never touch or reuse a real Tailscale install.
- Log upload to log.tailscale.com is off by default (and the build also uses ts_omit_logtail).
- Default control URL points at our zone, so a CLI login without --login-server never reaches Tailscale Inc.
"""
import pathlib
import sys

ADAPTER_GUID = '{45f21c2c-054f-40c3-8402-b4ea44933cc2}'   # fixed, unlike Tailscale's {37217669-...}

EDITS = [
    ('cmd/tailscaled/tailscaled_windows.go', 'const serviceName = "Tailscale"', 'const serviceName = "MAERouting"'),
    ('cmd/tailscaled/install_windows.go', 'DisplayName:  serviceName,', 'DisplayName:  "MAE Routing",'),
    ('cmd/tailscaled/install_windows.go', '"Connects this computer to others on the Tailscale network."',
     '"MAE Routing: connects this computer to your organisation\'s private network (routing.maesuaisystem.com)."'),
    ('cmd/tailscaled/tailscaled.go', '\tcase "windows":\n\t\treturn "Tailscale"', '\tcase "windows":\n\t\treturn "MAE Routing"'),
    ('cmd/tailscaled/tailscaled.go', 'flag.BoolVar(&args.disableLogs, "no-logs-no-support", false,',
     'flag.BoolVar(&args.disableLogs, "no-logs-no-support", true,'),
    ('cmd/tailscaled/syspolicy.go', 'filepath.Join(pd, "Tailscale", "syspolicy.json")', 'filepath.Join(pd, "MAERouting", "syspolicy.json")'),
    ('net/tstun/tun_windows.go', 'tun.WintunTunnelType = "Tailscale"', 'tun.WintunTunnelType = "MAE Routing"'),
    ('net/tstun/tun_windows.go', '"{37217669-42da-4657-a55b-0d995d328250}"', f'"{ADAPTER_GUID}"'),
    ('paths/paths.go', 'WindowsProtectedPipePrefix + `Tailscale\\tailscaled`', 'WindowsProtectedPipePrefix + `MAERouting\\maeroutingd`'),
    ('paths/paths.go', 'filepath.Join(os.Getenv("ProgramData"), "Tailscale", "server-state.conf")',
     'filepath.Join(os.Getenv("ProgramData"), "MAERouting", "server-state.conf")'),
    ('paths/paths.go', 'return `\\\\.\\pipe\\tailscale-` + u.Uid', 'return `\\\\.\\pipe\\maerouting-` + u.Uid'),
    ('ipn/auditlog/store.go', 'filepath.Join(os.Getenv("ProgramData"), "Tailscale", "audit-log.json")',
     'filepath.Join(os.Getenv("ProgramData"), "MAERouting", "audit-log.json")'),
    ('ipn/ipnlocal/profiles_windows.go', 'filepath.Join(usr.HomeDir, "AppData", "Local", "Tailscale")',
     'filepath.Join(usr.HomeDir, "AppData", "Local", "MAERouting")'),
    ('util/winutil/winutil_windows.go', 'regBase       = `SOFTWARE\\Tailscale IPN`', 'regBase       = `SOFTWARE\\MAE Routing`'),
    ('util/winutil/winutil_windows.go', 'regPolicyBase = `SOFTWARE\\Policies\\Tailscale`', 'regPolicyBase = `SOFTWARE\\Policies\\MAE Routing`'),
    ('ipn/prefs.go', 'const DefaultControlURL = "https://controlplane.tailscale.com"',
     'const DefaultControlURL = "https://login.routing.maesuaisystem.com"'),
    # Linux / Unix identity: binaries are mae-routing + mae-routingd, never share files with a real tailscaled
    ('paths/paths.go', 'return "/var/run/tailscale/tailscaled.sock"', 'return "/var/run/mae-routing/mae-routingd.sock"'),
    ('paths/paths_unix.go', 'return "/var/lib/tailscale/tailscaled.state"', 'return "/var/lib/mae-routing/mae-routingd.state"'),
    ('cmd/tailscaled/tailscaled.go', 'return "tailscale0,userspace-networking"', 'return "maerouting0,userspace-networking"'),
    ('cmd/tailscaled/tailscaled.go', '\treturn "tailscale0"\n}', '\treturn "maerouting0"\n}'),
    # CLI: name in help, and --org NAME as shorthand for --login-server https://NAME.routing.maesuaisystem.com
    ('cmd/tailscale/cli/cli.go', 'Name:       "tailscale",', 'Name:       "mae-routing",'),
    ('cmd/tailscale/cli/cli.go', 'ShortUsage: "tailscale [flags] <subcommand> [command flags]",',
     'ShortUsage: "mae-routing [flags] <subcommand> [command flags]",'),
    ('cmd/tailscale/cli/cli.go', 'ShortHelp:  "The easiest, most secure way to use WireGuard.",',
     'ShortHelp:  "MAE Routing: your organisation\'s private network (routing.maesuaisystem.com).",'),
    ('cmd/tailscale/cli/up.go',
     '\tupf.StringVar(&upArgs.server, "login-server", ipn.DefaultControlURL, "base URL of control server")\n',
     '\tupf.StringVar(&upArgs.server, "login-server", ipn.DefaultControlURL, "base URL of control server")\n'
     '\tupf.Var(&orgFlag{fs: upf}, "org", "MAE Routing network name; same as --login-server=https://<org>.routing.maesuaisystem.com")\n'),
    ('cmd/tailscale/cli/up.go', 'case "auth-key", "force-reauth", "reset", "qr",', 'case "org", "auth-key", "force-reauth", "reset", "qr",'),
]

# Whole files replaced. The bootstrap-DNS fallback list names Tailscale's DERP servers: when normal DNS
# is slow or broken the client would ask them for our hostnames (seen in container logs). Empty = never.
WRITES = [
    ('net/dnsfallback/dns-fallback-servers.json', '{"Regions": {}}\n'),
]

EDITS_ALL = [
    ('wgengine/router/osrouter/router_windows.go', 'Tailscale-In', 'MAERouting-In'),
    ('wgengine/router/osrouter/router_windows.go', 'Tailscale-Process', 'MAERouting-Process'),
]


def edit(root, rel, old, new, all_=False):
    p = root / rel
    s = p.read_text(encoding='utf-8')
    # done if `new` is there; for insertions (`old` inside `new`) only when every `old` already sits in a `new`
    if new in s and (old not in new or s.count(old) == s.count(new)):
        print(f'  = {rel}: already applied')
        return
    n = s.count(old)
    if n == 0:
        if new in s:
            print(f'  = {rel}: already applied')
            return
        sys.exit(f'FAIL {rel}: pattern not found: {old!r}')
    if n > 1 and not all_:
        sys.exit(f'FAIL {rel}: pattern found {n} times: {old!r}')
    p.write_text(s.replace(old, new), encoding='utf-8')
    print(f'  ~ {rel} ({n}x)')


def main():
    root = pathlib.Path(sys.argv[1]).resolve()
    for rel, old, new in EDITS:
        edit(root, rel, old, new)
    for rel, old, new in EDITS_ALL:
        edit(root, rel, old, new, all_=True)
    for rel, content in WRITES:
        p = root / rel
        if p.read_text(encoding='utf-8') != content:
            p.write_text(content, encoding='utf-8')
            print(f'  ~ {rel} (replaced)')


if __name__ == '__main__':
    main()
