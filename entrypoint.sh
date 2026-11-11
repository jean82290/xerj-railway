#!/bin/bash
# Adapts XERJ to Railway, then runs two processes:
#   - XERJ, listening on loopback only (127.0.0.1), never reachable directly;
#   - Caddy, on $PORT, which forwards to XERJ and answers 404 for XERJ's web
#     console (see Caddyfile).
# This shell stays as PID 1: it passes Railway's stop signal to both, so XERJ
# flushes before stopping, and it exits as soon as either one stops, so
# Railway restarts the container.
#
# Variables (all optional except where noted):
#   PORT                       public port Railway routes to (default 9200)
#   XERJ_ADMIN_KEY             64 hex chars; the admin API key. The template
#                              generates one. Empty = XERJ generates its own
#                              in /data/admin.key (read it with `railway ssh`).
#   XERJ_DATA_DIR              where indices live; mount the volume here
#                              (default /data)
#   XERJ_EMBED_MODE            lexical (default) | neural | proxy  (read by XERJ)
#   XERJ_MAX_PROCESS_MEMORY_MB memory cap in MiB, or auto (read by XERJ)
#   XERJ_LOG                   log filter, e.g. info or debug (read by XERJ)
#   XERJ_SHOW_CONSOLE_SETUP_LINK  true = do not hide the console setup token
#                              in the logs (default false)
set -eu

log() { echo "xerj-railway: $*"; }
die() { echo "xerj-railway: ERROR: $*" >&2; exit 1; }

DATA_DIR="${XERJ_DATA_DIR:-/data}"
PORT="${PORT:-9200}"
CONFIG="${XERJ_GENERATED_CONFIG:-/tmp/xerj.toml}"
CADDYFILE="${XERJ_CADDYFILE:-/etc/caddy/Caddyfile}"

case "$PORT" in
  ''|*[!0-9]*) die "PORT must be a number, got '$PORT'" ;;
esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "PORT must be between 1 and 65535, got '$PORT'"

# XERJ's three listeners, on loopback. Keep them out of PORT's way.
XERJ_INTERNAL_PORT=19200
REST_PORT=19280
GRPC_PORT=19281
case "$PORT" in
  19200|19280|19281) XERJ_INTERNAL_PORT=29200; REST_PORT=29280; GRPC_PORT=29281 ;;
esac
export PORT XERJ_INTERNAL_PORT

# XERJ reads these from the environment and they would override the loopback
# bind and fixed ports below (an older version of this template documented
# XERJ_BIND_ADDRESS). Caddy now listens on every interface, IPv4 and IPv6.
for var in XERJ_BIND_ADDRESS XERJ_ALLOW_INSECURE_NETWORK_BIND XERJ_AUTO_PORT; do
  if [ -n "${!var+x}" ]; then
    log "ignoring $var: XERJ listens on loopback only and Caddy serves \$PORT"
    unset "$var"
  fi
done

mkdir -p "$DATA_DIR"

# A Railway volume shows up as a mount point. Without one, every redeploy
# starts from an empty index, so say so loudly.
if ! awk -v d="$DATA_DIR" '$2 == d { found = 1 } END { exit !found }' /proc/mounts 2>/dev/null; then
  log "WARNING: $DATA_DIR is not a mounted volume. Indices will be LOST on every redeploy."
  log "WARNING: attach a Railway volume with mount path $DATA_DIR."
fi

# Admin API key. XERJ adopts a 64-hex-character key written to
# <data_dir>/admin.key as-is, so writing it on every boot also makes rotation
# a matter of changing the variable and redeploying.
if [ -n "${XERJ_ADMIN_KEY:-}" ]; then
  key=$(printf '%s' "$XERJ_ADMIN_KEY" | tr -d '[:space:]' | tr 'A-F' 'a-f')
  [ "${#key}" -eq 64 ] || die "XERJ_ADMIN_KEY must be exactly 64 hex characters (got ${#key})"
  case "$key" in
    *[!0-9a-f]*) die "XERJ_ADMIN_KEY must contain only 0-9 and a-f" ;;
  esac
  ( umask 077 && printf '%s\n' "$key" > "$DATA_DIR/admin.key" )
  log "admin API key taken from XERJ_ADMIN_KEY"
else
  log "XERJ_ADMIN_KEY is empty: XERJ keeps or generates $DATA_DIR/admin.key"
fi

# Loopback bind: nothing outside this container reaches XERJ except through
# Caddy, so XERJ needs neither its own TLS nor allow_insecure_network_bind.
cat > "$CONFIG" <<EOF
[server]
es_compat_port = $XERJ_INTERNAL_PORT
rest_port = $REST_PORT
grpc_port = $GRPC_PORT
bind_address = "127.0.0.1"
data_dir = "$DATA_DIR"

[auth]
enabled = true

[embedding]
model_cache_dir = "$DATA_DIR/.models"
EOF

# Caddy keeps nothing on disk with this config; point its folders at /tmp so
# it never writes into the volume.
export XDG_CONFIG_HOME=/tmp/caddy/config XDG_DATA_HOME=/tmp/caddy/data

log "starting $(xerj -V 2>/dev/null | head -n 1) on 127.0.0.1:$XERJ_INTERNAL_PORT, data in $DATA_DIR"

# Until a console owner exists, XERJ prints a single-use link on every boot
# that claims its web console. Caddy blocks the console, and the link would
# only help someone who can read the logs (for example on a public demo
# project), so its token is hidden in the logs unless asked otherwise.
if [ "${XERJ_SHOW_CONSOLE_SETUP_LINK:-false}" != "true" ]; then
  fifo="${TMPDIR:-/tmp}/xerj-log.$$"
  rm -f "$fifo"
  mkfifo "$fifo"
  sed -u -e 's|\(_xerj-console/setup#token=\)[A-Za-z0-9_-]*|\1[hidden-by-template]|g' < "$fifo" &
  xerj --config "$CONFIG" "$@" > "$fifo" 2>&1 &
else
  xerj --config "$CONFIG" "$@" &
fi
xerj_pid=$!

log "starting $(caddy version 2>/dev/null | cut -d' ' -f1 | sed 's/^/Caddy /') on port $PORT, XERJ console blocked"
caddy run --config "$CADDYFILE" --adapter caddyfile &
caddy_pid=$!

signalled=0
stop() { kill -TERM "$caddy_pid" "$xerj_pid" 2>/dev/null || true; }
on_signal() { signalled=1; trap - TERM INT; stop; }
trap on_signal TERM INT

# Returns when either process exits, or when Railway sends its stop signal.
wait -n "$xerj_pid" "$caddy_pid" || true
if [ "$signalled" = 1 ]; then
  log "stop signal received, stopping XERJ and Caddy"
else
  log "a process stopped on its own; stopping the container so Railway restarts it"
  stop
fi

# Let XERJ finish flushing to the volume before the container ends.
while kill -0 "$xerj_pid" 2>/dev/null; do
  wait "$xerj_pid" || true
done
status=0
wait "$xerj_pid" || status=$?
wait "$caddy_pid" 2>/dev/null || true
# An unexpected stop must look like a failure, or Railway's default
# restart-on-failure policy would leave the service down.
if [ "$signalled" = 0 ] && [ "$status" = 0 ]; then
  status=1
fi
exit "$status"
