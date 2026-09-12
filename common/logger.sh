#!/system/bin/sh
# FAACC logger.sh
# Format: [TIME] [LEVEL] MESSAGE
# Target : /sdcard/faacc-log/faacc.log + latest.log + archive/
# Independen dari UI. Dipakai CLI, core, dan service.

# Resolve direktori log (prioritas: /sdcard -> /data/media/0 -> persist)
FAACC_LOG_DIR="${FAACC_LOG_DIR:-}"
if [ -z "$FAACC_LOG_DIR" ]; then
  if [ -d "/sdcard" ]; then
    FAACC_LOG_DIR="/sdcard/faacc-log"
  elif [ -d "/data/media/0" ]; then
    FAACC_LOG_DIR="/data/media/0/faacc-log"
  else
    FAACC_LOG_DIR="/data/adb/faacc/log"
  fi
fi
FAACC_LOG_FILE="$FAACC_LOG_DIR/faacc.log"
FAACC_LATEST_LOG="$FAACC_LOG_DIR/latest.log"
FAACC_ARCHIVE_DIR="$FAACC_LOG_DIR/archive"

FAACC_MAX_LOG_SIZE_KB="${FAACC_MAX_LOG_SIZE_KB:-512}"
FAACC_MAX_ARCHIVE="${FAACC_MAX_ARCHIVE:-7}"

_faacc_ensure_logdir() {
  mkdir -p "$FAACC_ARCHIVE_DIR" 2>/dev/null
  [ -f "$FAACC_LOG_FILE" ] || : > "$FAACC_LOG_FILE" 2>/dev/null
  [ -f "$FAACC_LATEST_LOG" ] || : > "$FAACC_LATEST_LOG" 2>/dev/null
}

_faacc_timestamp() {
  date "+%H:%M:%S" 2>/dev/null || echo "??:??:??"
}

_faacc_datestamp() {
  date "+%Y-%m-%d" 2>/dev/null || echo "unknown-date"
}

# Rotasi: jika faacc.log > MAX, pindah ke archive/YYYY-MM-DD_HH-MM-SS.log
faacc_rotate_if_needed() {
  _faacc_ensure_logdir
  [ -f "$FAACC_LOG_FILE" ] || return 0
  size_kb=$(du -k "$FAACC_LOG_FILE" 2>/dev/null | awk '{print $1}')
  case "$size_kb" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$size_kb" -ge "$FAACC_MAX_LOG_SIZE_KB" ]; then
    ts=$(date "+%Y-%m-%d_%H-%M-%S" 2>/dev/null || echo "archive")
    mv "$FAACC_LOG_FILE" "$FAACC_ARCHIVE_DIR/${ts}.log" 2>/dev/null
    : > "$FAACC_LOG_FILE" 2>/dev/null
    # Batasi jumlah arsip
    count=$(ls -1 "$FAACC_ARCHIVE_DIR" 2>/dev/null | wc -l | tr -d ' ')
    if [ -n "$count" ] && [ "$count" -gt "$FAACC_MAX_ARCHIVE" ]; then
      ls -1tr "$FAACC_ARCHIVE_DIR" 2>/dev/null | head -n $((count - FAACC_MAX_ARCHIVE)) | while read -r f; do
        rm -f "$FAACC_ARCHIVE_DIR/$f" 2>/dev/null
      done
    fi
  fi
}

# faacc_log LEVEL MESSAGE
# LEVEL: INFO SCAN CLEAN WARN ERROR
faacc_log() {
  _level="${1:-INFO}"
  shift 2>/dev/null || shift
  _msg="$*"
  [ -z "$_msg" ] && _msg="$1"
  _faacc_ensure_logdir
  faacc_rotate_if_needed
  line="[$(_faacc_timestamp)] [$_level] $_msg"
  echo "$line" >> "$FAACC_LOG_FILE" 2>/dev/null
  echo "$line" >> "$FAACC_LATEST_LOG" 2>/dev/null
  # Batasi latest.log 200 baris terakhir
  if [ -f "$FAACC_LATEST_LOG" ]; then
    lines=$(wc -l < "$FAACC_LATEST_LOG" 2>/dev/null | tr -d ' ')
    case "$lines" in ''|*[!0-9]*) ;; *)
      if [ "$lines" -gt 200 ]; then
        tail -n 200 "$FAACC_LATEST_LOG" > "$FAACC_LATEST_LOG.tmp" 2>/dev/null && \
          mv "$FAACC_LATEST_LOG.tmp" "$FAACC_LATEST_LOG" 2>/dev/null
      fi
    esac
  fi
  # Echo ke stdout hanya untuk WARN/ERROR agar tidak mengotori output --json
  case "$_level" in
    WARN|ERROR) echo "$line" >&2 ;;
  esac
}

faacc_log_info()  { faacc_log "INFO" "$*"; }
faacc_log_scan()  { faacc_log "SCAN" "$*"; }
faacc_log_clean() { faacc_log "CLEAN" "$*"; }
faacc_log_warn()  { faacc_log "WARN" "$*"; }
faacc_log_error() { faacc_log "ERROR" "$*"; }
