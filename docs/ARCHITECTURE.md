# Architecture

The projector-side agent opens an outbound TCP connection from the projector to the Mac. The Mac does not need to connect to a projector listener.

The Mac broker has two interfaces:

1. A TCP listener for the projector callback.
2. A local Unix domain socket for local tools and agents.

Keeping the operator interface on a Unix socket avoids exposing a command API to the LAN. Only the projector callback port is reachable on the network.

## Connection lifecycle

1. The Mac broker starts and listens on a configured TCP port, usually `2325`.
2. The projector USB payload installs or repairs the projector agent.
3. The USB payload adds a marked launcher block to `/data/customer/smcast/dst-launcher.sh` if it is not already present.
4. The projector agent waits for a default route.
5. The projector agent tries callback ports in order.
6. Once connected, the broker can send commands through the callback shell.
7. If the connection drops, the projector agent loops and reconnects.
8. If the Mac broker restarts, the projector reconnects on its next loop.

## Persistence model

The projector agent is launched by an existing projector startup script. The added block is marked with `OWNER_ACCESS_TOOLKIT_BEGIN` and `OWNER_ACCESS_TOOLKIT_END` so it can be inspected or removed later.

The agent handles stale PID files by checking whether the PID file points to the actual agent process before exiting.

The Mac broker can be run manually during testing or installed as a macOS LaunchAgent for durable operation.

## Reversal model

Use `projector/remove_owner_access.sh` from an existing projector root shell to remove the marked launcher block and agent files. USB backups are written under `/data/projector_project/` when the installer modifies the launcher.
