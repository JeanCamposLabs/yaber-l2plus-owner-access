# Troubleshooting

## Broker is not listening

```sh
python3 scripts/projectorctl.py --socket ./runtime/projector_broker/control.sock status
lsof -nP -iTCP:2325 -sTCP:LISTEN
```

If using launchd, restart the LaunchAgent:

```sh
uid=$(id -u)
launchctl kickstart -k "gui/$uid/com.projector.broker"
```

## Projector does not reconnect after reboot

1. Confirm the projector and Mac are on the same LAN.
2. Confirm the Mac IP in the projector agent matches the current Mac IP.
3. Wait for Wi-Fi and network time to come up on the projector.
4. Check `PROJECTOR_DEBUG_LOGS/` on the USB stick if you booted with USB inserted.
5. If it still does not reconnect, rebuild the USB payload with the current Mac IP and boot with the USB inserted.

## Commands are noisy

Use the v3 stable agent. It uses a non-interactive shell for cleaner broker-controlled output.

## Mac IP changed

Rebuild the payload:

```sh
python3 tools/configure_payload.py NEW_MAC_LAN_IP --broker-port 2325
```

Copy the new files to the USB drive and boot with the USB inserted, or edit `/data/projector_project/projector_agent_host` from an existing projector shell.

## Remove the toolkit

From an existing projector root shell, run `projector/remove_owner_access.sh`. It removes the marked launcher block and agent files. If needed, restore one of the launcher backups under `/data/projector_project/`.
