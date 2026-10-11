# Mac broker setup

## Run manually

```sh
cd yaber-l2plus-owner-access
python3 scripts/projector_broker.py --listen-host 0.0.0.0 --listen-port 2325 --run-dir ./runtime/projector_broker
```

In another terminal:

```sh
python3 scripts/projectorctl.py --socket ./runtime/projector_broker/control.sock status
```

## Install as LaunchAgent

Copy the template:

```sh
cp templates/com.projector.broker.plist.template ~/Library/LaunchAgents/com.projector.broker.plist
```

Edit the plist placeholders:

- `REPO_PATH`
- `PYTHON3_PATH`
- `BROKER_PORT`

Then load it:

```sh
uid=$(id -u)
launchctl bootstrap "gui/$uid" ~/Library/LaunchAgents/com.projector.broker.plist
launchctl enable "gui/$uid/com.projector.broker"
```

Restart it later with:

```sh
uid=$(id -u)
launchctl kickstart -k "gui/$uid/com.projector.broker"
```

## Verify

```sh
python3 scripts/projectorctl.py --socket ./runtime/projector_broker/control.sock status
lsof -nP -iTCP:2325 -sTCP:LISTEN
```

For a tighter LAN setup, start the broker with `--allowed-peer PROJECTOR_IP` after you know the projector's current IP address.
