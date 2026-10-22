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
    # our TUN is "maerouting0" (Linux) / "MAE Routing" (Windows): the code must still treat it as its own interface
    ('net/netmon/state.go', 'return name == "Tailscale" || // as it is on Windows',
     'return name == "Tailscale" || name == "MAE Routing" || strings.HasPrefix(name, "maerouting") || // as it is on Windows'),
    ('net/netmon/interfaces_linux.go', 'if strings.HasPrefix(ifc, "tailscale") ||',
     'if strings.HasPrefix(ifc, "tailscale") || strings.HasPrefix(ifc, "maerouting") ||'),
    # captive-portal checks must not call Tailscale's servers (the DERP nodes of our map are still used)
    ('net/captivedetection/endpoints.go', '\tappendTailscaleEndpoint("http://controlplane.tailscale.com/generate_204")\n\tappendTailscaleEndpoint("http://login.tailscale.com/generate_204")\n',
     '\t_ = appendTailscaleEndpoint // MAE Routing: no calls to Tailscale-hosted endpoints\n'),
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
    # Own address plan so MAE Routing can run next to Tailscale (and NetBird) on one machine:
    # tailnet 10.77.0.0/16 (Tailscale: 100.64.0.0/10), MagicDNS/quad100 10.77.77.77 (100.100.100.100),
    # ULA fd4d:4145:5254::/48 (fd7a:115c:a1e0::/48). The control server (headscale fork) uses the same plan.
    ('net/tsaddr/tsaddr.go', 'mustPrefix(&cgnatRange.v, "100.64.0.0/10")', 'mustPrefix(&cgnatRange.v, "10.77.0.0/16")'),
    ('net/tsaddr/tsaddr.go', 'return netaddr.IPv4(100, 100, 100, 100) // "100.100.100.100" for those grepping',
     'return netaddr.IPv4(10, 77, 77, 77) // "10.77.77.77" for those grepping (MAE Routing)'),
    ('net/tsaddr/tsaddr.go', 'TailscaleServiceIPString   = "100.100.100.100"', 'TailscaleServiceIPString   = "10.77.77.77"'),
    ('client/systray/systray.go', 'webbrowser.Open("http://100.100.100.100/")', 'webbrowser.Open("http://10.77.77.77/")'),
    # Linux kernel objects Tailscale also uses: routing table 52, ip rule priorities 5200-5299 (its cleanup
    # deletes every rule in that band), fwmark bits 0xff0000, iptables/nftables chains and tables "ts-*".
    ('wgengine/router/osrouter/router_linux.go', 'tailscaleRouteTable = newRouteTable("tailscale", 52)',
     'tailscaleRouteTable = newRouteTable("maerouting", 77)'),
    ('wgengine/router/osrouter/router_linux.go', 'ipPolicyPrefBase: 5200,', 'ipPolicyPrefBase: 5700,'),
    ('net/netmon/netmon_linux.go', 'const tsTable = 52', 'const tsTable = 77'),
    ('tsconst/linuxfw.go', 'LinuxFwmarkMask    = "0xff0000"', 'LinuxFwmarkMask    = "0x7f000000"'),
    ('tsconst/linuxfw.go', 'LinuxFwmarkMaskNum = 0xff0000', 'LinuxFwmarkMaskNum = 0x7f000000'),
    ('tsconst/linuxfw.go', 'LinuxSubnetRouteMark    = "0x40000"', 'LinuxSubnetRouteMark    = "0x1000000"'),
    ('tsconst/linuxfw.go', 'LinuxSubnetRouteMarkNum = 0x40000', 'LinuxSubnetRouteMarkNum = 0x1000000'),
    ('tsconst/linuxfw.go', 'LinuxBypassMark    = "0x80000"', 'LinuxBypassMark    = "0x2000000"'),
    ('tsconst/linuxfw.go', 'LinuxBypassMarkNum = 0x80000', 'LinuxBypassMarkNum = 0x2000000'),
    # WireGuard UDP port 41642 (Tailscale uses 41641) so both can listen on one machine
    ('cmd/tailscaled/tailscaled.go', '\tif envknob.GOOS() == "windows" {\n\t\treturn 41641\n\t}',
     '\tif envknob.GOOS() == "windows" {\n\t\treturn 41642\n\t}'),
    # Windows: Tailscale keeps its NRPT (per-domain DNS) rule under this fixed id; ours must not overwrite it
    ('net/dns/nrpt_windows.go', 'nrptSingleRuleID = `{5abe529b-675b-4486-8459-25a634dacc23}`',
     'nrptSingleRuleID = `{0c6ac0b9-349b-40ad-ad78-0aa4fd6029be}`'),
]

# Whole files replaced. The bootstrap-DNS fallback list names Tailscale's DERP servers: when normal DNS
# is slow or broken the client would ask them for our hostnames (seen in container logs). Empty = never.
WRITES = [
    ('net/dnsfallback/dns-fallback-servers.json', '{"Regions": {}}\n'),
]

EDITS_ALL = [
    ('wgengine/router/osrouter/router_windows.go', 'Tailscale-In', 'MAERouting-In'),
    ('wgengine/router/osrouter/router_windows.go', 'Tailscale-Process', 'MAERouting-Process'),
    ('net/tsaddr/tsaddr.go', 'fd7a:115c:a1e0', 'fd4d:4145:5254'),   # ULA, its ::53 service IP, via/4to6/eph6 ranges
    ('util/linuxfw/iptables_runner.go', '"ts-', '"mr-'),
    ('util/linuxfw/iptables.go', '"ts-', '"mr-'),
    ('util/linuxfw/nftables_runner.go', '"ts-', '"mr-'),
]


# ---------- user-visible text: no "Tailscale" in anything a user reads (CLI output, help, health warnings) ----------
import re
import subprocess

TOKENS = re.compile(r'(//[^\n]*|/\*.*?\*/|`[^`]*`|"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\')', re.S)
COMPARE = re.compile(r'==|!=|Contains\(|HasPrefix\(|HasSuffix\(|EqualFold\(|\bcase\s')
SUBCMDS = ('up|down|set|login|logout|status|ip|ping|switch|serve|funnel|cert|file|drive|exit-node|netcheck|version|web|'
           'lock|update|configure|bugreport|debug|whois|dns|nc|ssh|metrics|syspolicy|completion|systray|licenses|'
           'appc-routes|wait|routes|policy')
TEXT_RULES = [
    (re.compile(r'https?://(?:www\.)?tailscale\.com(?:/[^\s"`\'<>)]*)?'), 'https://routing.maesuaisystem.com/'),
    (re.compile(r'(?<![\w/.@-])tailscale\.com/(?:s|kb|docs)/[^\s"`\'<>)]*'), 'routing.maesuaisystem.com'),
    (re.compile(r'\btailscaled\b(?![/\w-]|\.\w)'), 'mae-routingd'),       # not "tailscaled.service" etc.
    (re.compile(r'\bcmd/tailscale\b(?![/\w-])'), 'mae-routing'),
    (re.compile(r'\btailscale (?=(?:' + SUBCMDS + r')\b)'), 'mae-routing '),
    (re.compile(r'github\.com/tailscale/tailscale'), 'github.com/maxspeedcom/mae-routing'),
    (re.compile(r'\bpkgs\.tailscale\.com\b'), 'the upstream package server'),
    (re.compile(r'\b100\.x\.y\.z\b'), '10.77.x.y'),
    (re.compile(r'\b100\.100\.100\.100\b'), '10.77.77.77'),          # help text for the address plan above
    (re.compile(r'\b100\.64\.0\.0/10\b'), '10.77.0.0/16'),
    (re.compile(r'\bTailscale(?![\w-]|\.\w)'), 'MAE Routing'),           # "Tailscale." at a sentence end, not "Tailscale.app"
    (re.compile(r'(?<![\w./-])tailscale(?![\w/-]|\.\w)'), 'mae-routing'),
]


def rebrand_literal(lit):
    if ' ' not in lit or TEXT_NEVER.search(lit):   # identifiers, import paths, names, wire format: leave alone
        return lit
    for rx, rep in TEXT_RULES:
        lit = rx.sub(rep, lit)
    return lit


# Only packages whose strings a user reads. Never protocol code: e.g. control/controlbase's
# "Tailscale Control Protocol v" is hashed into the Noise handshake, renaming it breaks every login.
TEXT_DIRS = [
    'cmd/tailscale/cli', 'cmd/tailscaled', 'cmd/containerboot', 'health', 'health/healthmsg', 'version',
    'client/local', 'ipn/ipnlocal', 'ipn/localapi', 'ipn/ipnserver', 'net/dns', 'wgengine/router/osrouter',
    'control/controlclient', 'util/linuxfw', 'ssh/tailssh',
]
# literals that look like text but are wire format; never rewritten even inside TEXT_DIRS
TEXT_NEVER = re.compile(r'Control Protocol|handshake|-Ingress-|-User-|-Cap\b|prologue', re.I)


def rebrand_text(root):
    files = [f for d in TEXT_DIRS for f in sorted((root / d).glob('*.go'))]
    changed = 0
    for f in files:
        if f.name.endswith('_test.go') or '/mae/' in str(f):
            continue
        src = f.read_text(encoding='utf-8')
        out, pos = [], 0
        for m in TOKENS.finditer(src):
            tok = m.group(0)
            out.append(src[pos:m.start()])
            pos = m.end()
            if tok.startswith(('//', '/*', "'")):
                out.append(tok)
                continue
            line = src[src.rfind('\n', 0, m.start()) + 1: src.find('\n', m.end())]
            if tok.startswith('"') and COMPARE.search(line):
                out.append(tok)
                continue
            out.append(rebrand_literal(tok))
        out.append(src[pos:])
        new = ''.join(out)
        if new != src:
            f.write_text(new, encoding='utf-8')
            changed += 1
    print(f'  text pass: {changed} files changed')


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
    rebrand_text(root)
    for rel, content in WRITES:
        p = root / rel
        if p.read_text(encoding='utf-8') != content:
            p.write_text(content, encoding='utf-8')
            print(f'  ~ {rel} (replaced)')


if __name__ == '__main__':
    main()
