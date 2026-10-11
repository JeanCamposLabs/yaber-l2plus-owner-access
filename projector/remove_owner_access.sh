#!/bin/sh
# Reversal helper for an owner-controlled projector.
# Run from an existing root shell on the projector.

BASE_DIR="/data/projector_project"
LAUNCHER_PATH="/data/customer/smcast/dst-launcher.sh"
AGENT_PATH="/data/customer/smcast/projector_agent.sh"
TMP="$BASE_DIR/dst-launcher.remove_owner_access.$$"

/bin/mkdir -p "$BASE_DIR" 2>/dev/null

if [ -f "$LAUNCHER_PATH" ]; then
  /bin/awk '
    /OWNER_ACCESS_TOOLKIT_BEGIN/ {skip=1; next}
    /OWNER_ACCESS_TOOLKIT_END/ {skip=0; next}
    skip != 1 {print}
  ' "$LAUNCHER_PATH" > "$TMP" && /bin/sh -n "$TMP" && /bin/mv -f "$TMP" "$LAUNCHER_PATH"
  /bin/chmod 755 "$LAUNCHER_PATH" 2>/dev/null || true
  /bin/chown srafsvc:srafsvc "$LAUNCHER_PATH" 2>/dev/null || true
  /bin/chcon user_u:object_r:bin_exec "$LAUNCHER_PATH" 2>/dev/null || true
fi

if [ -f "$BASE_DIR/projector_agent.pid" ]; then
  pid="$(/bin/cat "$BASE_DIR/projector_agent.pid" 2>/dev/null | /bin/sed -n '1p')"
  if [ -n "$pid" ] && /bin/kill -0 "$pid" 2>/dev/null; then
    /bin/kill "$pid" 2>/dev/null || true
  fi
fi
for path in "$AGENT_PATH" "$BASE_DIR/projector_agent.pid" "$BASE_DIR/projector_agent_host" "$BASE_DIR/projector_agent_port"; do
  [ -e "$path" ] && /bin/rm "$path" 2>/dev/null || true
done
echo "owner access toolkit hook and agent removed"
