# Validation checklist

Use this checklist after installation.

## Mac broker

```sh
python3 scripts/projectorctl.py --socket ./runtime/projector_broker/control.sock status
```

Expected:

- `connected` is `true`
- banner mentions the projector persistent shell
- remote host is the projector LAN address

## Command proof

```sh
python3 scripts/projectorctl.py --socket ./runtime/projector_broker/control.sock cmd 'whoami; pwd; date' --timeout 10
```

Expected:

- `root`
- a valid projector directory such as `/basic`
- current device time after network time has corrected

## No-USB persistence

1. Remove the USB stick.
2. Cold reboot the projector.
3. Wait for Wi-Fi to come up.
4. Run `projectorctl.py status` again.

Expected: the projector reconnects without the USB stick.

## Normal-use check

Open a normal projector app and confirm the background shell remains connected.

## Recovery-stick check

At any later time, boot with the USB inserted and confirm a new log appears under `PROJECTOR_DEBUG_LOGS/`. A successful recovery run should log the agent install or repair step and the callback attempts.
