// Copyright (c) MAE Routing (maesuaisystem.com). Based on Tailscale (BSD-3-Clause).

package cli

import (
	"flag"
	"fmt"
	"regexp"
	"strings"
)

var orgNameRE = regexp.MustCompile(`^[a-z][a-z0-9-]{1,30}[a-z0-9]$`)

// orgFlag implements --org NAME, the MAE Routing shorthand for
// --login-server=https://NAME.routing.maesuaisystem.com. It sets the login-server
// flag itself so the "mention all non-default flags" check sees it as given.
type orgFlag struct {
	fs *flag.FlagSet
	v  string
}

func (o *orgFlag) String() string { return o.v }

func (o *orgFlag) Set(s string) error {
	s = strings.ToLower(strings.TrimSpace(s))
	s = strings.TrimSuffix(strings.TrimPrefix(s, "https://"), ".routing.maesuaisystem.com")
	if !orgNameRE.MatchString(s) {
		return fmt.Errorf("invalid network name %q: use a-z, 0-9 and -, 3-32 characters", s)
	}
	o.v = s
	return o.fs.Set("login-server", "https://"+s+".routing.maesuaisystem.com")
}
