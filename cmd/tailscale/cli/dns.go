// Copyright (c) Tailscale Inc & contributors
// SPDX-License-Identifier: BSD-3-Clause

package cli

import (
	"strings"

	"github.com/peterbourgon/ff/v3/ffcli"
)

var dnsCmd = &ffcli.Command{
	Name:      "dns",
	ShortHelp: "Diagnose the internal DNS forwarder",
	LongHelp: strings.TrimSpace(`
The 'mae-routing dns' subcommand provides tools for diagnosing the internal DNS
forwarder (10.77.77.77).

For more information about the DNS functionality built into MAE Routing, refer to
https://routing.maesuaisystem.com/
`),
	ShortUsage: strings.Join([]string{
		dnsStatusCmd.ShortUsage,
		dnsQueryCmd.ShortUsage,
	}, "\n"),
	UsageFunc: usageFuncNoDefaultValues,
	Subcommands: []*ffcli.Command{
		dnsStatusCmd,
		dnsQueryCmd,

		// TODO: implement `tailscale log` here

		// The above work is tracked in https://github.com/tailscale/tailscale/issues/13326
	},
}
