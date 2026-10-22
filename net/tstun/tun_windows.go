// Copyright (c) Tailscale Inc & contributors
// SPDX-License-Identifier: BSD-3-Clause

package tstun

import (
	"github.com/tailscale/wireguard-go/tun"
	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
)

func init() {
	tun.WintunTunnelType = "MAE Routing"
	guid, err := windows.GUIDFromString("{45f21c2c-054f-40c3-8402-b4ea44933cc2}")
	if err != nil {
		panic(err)
	}
	tun.WintunStaticRequestedGUID = &guid
}

func interfaceName(dev tun.Device) (string, error) {
	guid, err := winipcfg.LUID(dev.(*tun.NativeTun).LUID()).GUID()
	if err != nil {
		return "", err
	}
	return guid.String(), nil
}
