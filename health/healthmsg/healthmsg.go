// Copyright (c) Tailscale Inc & contributors
// SPDX-License-Identifier: BSD-3-Clause

// Package healthmsg contains some constants for health messages.
//
// It's a leaf so both the server and CLI can depend on it without bringing too
// much in to the CLI binary.
package healthmsg

const (
	WarnAcceptRoutesOff      = "Some peers are advertising routes but --accept-routes is false"
	TailscaleSSHOnBut        = "MAE Routing SSH enabled, but " // + ... something from caller
	LockedOut                = "this node is locked out; it will not have connectivity until it is signed. For more info, see https://routing.maesuaisystem.com/"
	InMemoryTailnetLockState = "Tailnet Lock state is only being stored in-memory. Set --statedir to store state on disk, which is more secure. See https://routing.maesuaisystem.com/"
)
