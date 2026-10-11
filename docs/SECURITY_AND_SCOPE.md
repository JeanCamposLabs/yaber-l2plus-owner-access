# Security and scope

This project is for owner-operated devices on a trusted local network.

Do not expose the broker port or control socket to the internet. The intended model is:

- projector callback port reachable only on the local LAN,
- command interface available only through a local Unix socket,
- physical access required for USB installation or recovery,
- owner reviews all commands before using them on their own projector.

## What not to publish

Do not publish device serial numbers, screenshots containing identifiers, packet captures, raw browser logs, private support emails, or machine-specific local paths.

## Network posture

The callback agent initiates an outbound connection from the projector to the Mac. The broker does not create a general LAN command API. Local automation should talk to the broker over the Unix socket.

For tighter setups, start the broker with `--allowed-peer PROJECTOR_IP` after the projector IP is known.

## Recovery posture

Keep a USB rollback path available. If a new agent version fails, use the USB payload to reinstall the last known-good agent or run `projector/remove_owner_access.sh` from an existing root shell.
