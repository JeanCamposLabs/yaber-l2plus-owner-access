#!/bin/sh
# Owner access toolkit persistent callback agent v3 for owner-controlled Yaber L2 Plus.
# Started by /data/customer/smcast/dst-launcher.sh.
# v3 keeps stale-PID/fallback behavior and uses a non-interactive shell for broker-controlled commands.

BASE_DIR="/data/projector_project"
LOG="$BASE_DIR/projector_agent.log"
PIDFILE="$BASE_DIR/projector_agent.pid"
HOST_FILE="$BASE_DIR/projector_agent_host"
PORT_FILE="$BASE_DIR/projector_agent_port"
DEFAULT_HOST="REPLACE_WITH_MAC_IP"
DEFAULT_PORT="2325"
FALLBACK_PORTS="2325 2324 2323"

log_line() {
  echo "$(/bin/date +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo no-date) $*" >> "$LOG" 2>/dev/null
}

add_word() {
  word="$1"
  list="$2"
  [ -n "$word" ] || { echo "$list"; return; }
  [ "$word" != "REPLACE_WITH_MAC_IP" ] || { echo "$list"; return; }
  case " $list " in
    *" $word "*) echo "$list" ;;
    *) echo "$list $word" ;;
  esac
}

/bin/mkdir -p "$BASE_DIR" 2>/dev/null

if [ -f "$PIDFILE" ]; then
  oldpid="$(/bin/cat "$PIDFILE" 2>/dev/null | /bin/sed -n '1p')"
  if [ -n "$oldpid" ] && /bin/kill -0 "$oldpid" 2>/dev/null; then
    if [ -r "/proc/$oldpid/cmdline" ] && /bin/grep -q 'projector_agent.sh' "/proc/$oldpid/cmdline" 2>/dev/null; then
      log_line "already running verified pid=$oldpid"
      exit 0
    fi
    log_line "stale pidfile active_non_agent_pid=$oldpid; replacing"
  elif [ -n "$oldpid" ]; then
    log_line "stale pidfile dead_pid=$oldpid; replacing"
  else
    log_line "stale pidfile empty; replacing"
  fi
fi

echo $$ > "$PIDFILE" 2>/dev/null
log_line "agent v3 starting pid=$$"

while true; do
  i=0
  while [ "$i" -lt 120 ]; do
    if /bin/route -n 2>/dev/null | /bin/grep -q '^0\.0\.0\.0'; then
      break
    fi
    if [ $((i % 15)) -eq 0 ]; then
      log_line "waiting for default route loop=$i"
    fi
    i=$((i + 1))
    /bin/sleep 2 2>/dev/null || sleep 2
  done

  HOSTS=""
  if [ -s "$HOST_FILE" ]; then
    h="$(/bin/cat "$HOST_FILE" 2>/dev/null | /bin/sed -n '1p')"
    HOSTS="$(add_word "$h" "$HOSTS")"
  fi
  HOSTS="$(add_word "$DEFAULT_HOST" "$HOSTS")"

  PORTS=""
  if [ -s "$PORT_FILE" ]; then
    p="$(/bin/cat "$PORT_FILE" 2>/dev/null | /bin/sed -n '1p')"
    PORTS="$(add_word "$p" "$PORTS")"
  fi
  for p in $DEFAULT_PORT $FALLBACK_PORTS; do
    PORTS="$(add_word "$p" "$PORTS")"
  done

  if [ -z "$HOSTS" ]; then
    log_line "no callback host configured; edit $HOST_FILE or replace DEFAULT_HOST"
    /bin/sleep 20 2>/dev/null || sleep 20
    continue
  fi

  for HOST in $HOSTS; do
    for PORT in $PORTS; do
      log_line "connecting to $HOST:$PORT"
      /bin/bash -c 'exec 5<>/dev/tcp/'"$HOST"'/'"$PORT"' || exit 111; echo "[projector persistent root shell v3 connected host='"$HOST"' port='"$PORT"']" >&5; /bin/whoami >&5 2>&5; /bin/pwd >&5 2>&5; exec /bin/bash <&5 >&5 2>&5' >> "$LOG" 2>&1
      rc=$?
      log_line "connection to $HOST:$PORT ended rc=$rc"
      /bin/sleep 2 2>/dev/null || sleep 2
    done
  done
  /bin/sleep 8 2>/dev/null || sleep 8
done
