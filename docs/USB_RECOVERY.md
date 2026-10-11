# USB install and recovery payload

The USB payload is intended for a FAT32 flash drive prepared by the device owner.

Build a configured payload first:

```sh
python3 tools/configure_payload.py YOUR_MAC_LAN_IP --broker-port 2325
```

Copy these files from `build/usb-root/` to the root of the USB drive:

```text
sraf_dbg.sh
projector_agent_stable.sh
projector_agent_v2_rollback.sh
SHA256SUMS.txt
```

`manual-projector_agent.sh` is included in the build folder for inspection or manual repair. It is not required at the USB root.

## What the USB script does

When the projector firmware sources `sraf_dbg.sh`, the script:

1. Finds the USB mount.
2. Writes logs under `PROJECTOR_DEBUG_LOGS/` on the USB stick.
3. Validates the selected projector agent with `/bin/sh -n`.
4. Installs the agent to `/data/customer/smcast/projector_agent.sh`.
5. Adds a marked launcher block to `/data/customer/smcast/dst-launcher.sh` if missing.
6. Starts the persistent agent immediately.
7. Opens direct USB recovery callbacks as a fallback.

The launcher block is marked with `OWNER_ACCESS_TOOLKIT_BEGIN` and `OWNER_ACCESS_TOOLKIT_END`. The script writes a backup of the original launcher under `/data/projector_project/` before changing it.

## Recovery behavior

The rescue script prefers files in this order:

1. `projector_agent_stable.sh`
2. `projector_agent_v3_candidate.sh`
3. `projector_agent_v2.sh`
4. `projector_agent_v2_rollback.sh`

Keep the USB stick available after installation. If the no-USB agent stops reconnecting, boot with the USB inserted to repair the installed agent and restart callbacks.
