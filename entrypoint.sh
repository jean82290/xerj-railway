#!/bin/sh
# Adapts XERJ to Railway, then hands the process over to XERJ (exec), so
# Railway's SIGTERM reaches XERJ directly and it flushes before stopping.
#
# Variables (all optional except where noted):
#   PORT                       public port Railway routes to (default 9200)
#   XERJ_ADMIN_KEY             64 hex chars; the admin API key. The template
#                              generates one. Empty = XERJ generates its own
#                              in /data/admin.key (read it with `railway ssh`).
#   XERJ_DATA_DIR              where indices live; mount the volume here
#                              (default /data)
#   XERJ_BIND_ADDRESS          default 0.0.0.0; use :: only in a legacy
#                              IPv6-only Railway environment
#   XERJ_EMBED_MODE            lexical (default) | neural | proxy  (read by XERJ)
#   XERJ_MAX_PROCESS_MEMORY_MB memory cap in MiB, or auto (read by XERJ)
#   XERJ_LOG                   log filter, e.g. info or debug (read by XERJ)
set -eu

log() { echo "xerj-railway: $*"; }
die() { echo "xerj-railway: ERROR: $*" >&2; exit 1; }

DATA_DIR="${XERJ_DATA_DIR:-/data}"
PORT="${PORT:-9200}"
BIND="${XERJ_BIND_ADDRESS:-0.0.0.0}"
CONFIG="${XERJ_GENERATED_CONFIG:-/tmp/xerj.toml}"

case "$PORT" in
  ''|*[!0-9]*) die "PORT must be a number, got '$PORT'" ;;
esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "PORT must be between 1 and 65535, got '$PORT'"

# XERJ also opens its native REST API and gRPC on two more ports (private
# only). Keep them out of PORT's way.
REST_PORT=8080
GRPC_PORT=8081
if [ "$PORT" = "8080" ] || [ "$PORT" = "8081" ]; then
  REST_PORT=18080
  GRPC_PORT=18081
fi

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

# TLS is terminated by Railway's edge, so XERJ serves plain HTTP inside the
# container. allow_insecure_network_bind declares exactly that; auth stays ON.
cat > "$CONFIG" <<EOF
[server]
es_compat_port = $PORT
rest_port = $REST_PORT
grpc_port = $GRPC_PORT
bind_address = "$BIND"
allow_insecure_network_bind = true
data_dir = "$DATA_DIR"

[auth]
enabled = true

[embedding]
model_cache_dir = "$DATA_DIR/.models"
EOF

log "starting $(xerj -V 2>/dev/null | head -n 1) on $BIND:$PORT, data in $DATA_DIR"

# Until a console owner exists, XERJ prints a single-use link on every boot
# that claims its web console (which does not use the API key). Its passkey
# sign-in cannot work behind Railway's domain anyway, so the link only helps
# someone who can read the logs, for example on a public demo project.
# Hide the token in the logs. XERJ still runs as PID 1 (exec), so Railway's
# stop signal reaches it directly.
if [ "${XERJ_SHOW_CONSOLE_SETUP_LINK:-false}" != "true" ]; then
  fifo="${TMPDIR:-/tmp}/xerj-log.$$"
  rm -f "$fifo"
  mkfifo "$fifo"
  sed -u -e 's|\(_xerj-console/setup#token=\)[A-Za-z0-9_-]*|\1[hidden-by-template]|g' < "$fifo" &
  exec xerj --config "$CONFIG" "$@" > "$fifo" 2>&1
fi
exec xerj --config "$CONFIG" "$@"
