#!/bin/sh
# solar-saver.sh — Solar System as a screensaver theme.
#
# Theme for mate-screensaver (and xscreensaver).  The daemon does not pass
# arguments: it exports XSCREENSAVER_WINDOW with the id of the surface the
# theme must draw into, and the host reparents its own window into it.
#
# Two things this wrapper must survive, because a theme that dies before
# drawing anything leaves no trace at all:
#   * a stripped environment — HOME is resolved from the passwd database when
#     it is missing (the previous version aborted on `set -u`, silently);
#   * its own stderr going nowhere — the host now writes its output into
#     ~/.cache/solar-screensaver.log, trimmed to the last 200 lines.
#
# Any arguments are forwarded to the host; --root and -window-id are accepted
# and ignored, so the same script also works as a classic XScreenSaver hack.

DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
PAGE="$DIR/solar-system-3d.html"
HOST="$DIR/solar-webkit.py"

# ---- log file, resolved without assuming an environment -------------------
# The log path must end up *writable*, not merely plausible: the host is
# started with `>>"$LOG"`, and a redirection that cannot be opened makes sh
# fail the command, so the theme would exit without drawing anything and
# without leaving a trace (measured: read-only $HOME/.cache -> saver never
# started).  Candidates are probed, then /dev/null is the last resort.
HOME_DIR=${HOME:-}
if [ -z "$HOME_DIR" ] && command -v getent >/dev/null 2>&1; then
    HOME_DIR=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)
fi
[ -n "$HOME_DIR" ] || HOME_DIR=/tmp
CACHE_DIR=${XDG_CACHE_HOME:-$HOME_DIR/.cache}

log_writable() {
    _d=$(dirname "$1")
    [ -d "$_d" ] || mkdir -p "$_d" 2>/dev/null || return 1
    ( : >>"$1" ) 2>/dev/null
}

LOG=
for _cand in "$CACHE_DIR/solar-screensaver.log" "/tmp/solar-screensaver.log"; do
    if log_writable "$_cand"; then LOG=$_cand; break; fi
done
[ -n "$LOG" ] || LOG=/dev/null

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || return 0
    if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 400 ] 2>/dev/null; then
        tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
    fi
}

log "start pid=$$ args=[$*] HOME=${HOME:-<unset>} DISPLAY=${DISPLAY:-<unset>} XAUTHORITY=$([ -n "${XAUTHORITY:-}" ] && echo set || echo unset) XSCREENSAVER_WINDOW=${XSCREENSAVER_WINDOW:-<unset>}"

if [ ! -f "$PAGE" ]; then
    log "abort: missing $PAGE"; echo "solar-saver: missing $PAGE" >&2; exit 1
fi
if [ ! -f "$HOST" ]; then
    log "abort: missing $HOST"; echo "solar-saver: missing $HOST" >&2; exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    log "abort: python3 not in PATH"; echo "solar-saver: python3 not found" >&2; exit 1
fi

# ---- remember the X screensaver / DPMS state, then disable blanking -------
DPMS_WAS=$(xset q 2>/dev/null | sed -n 's/.*DPMS is \(Enabled\|Disabled\).*/\1/p')
SS_TIMEOUT_WAS=$(xset q 2>/dev/null | sed -n 's/^ *timeout: *\([0-9]*\).*/\1/p')

restore() {
    if [ "${DPMS_WAS:-Disabled}" = "Enabled" ]; then
        xset +dpms 2>/dev/null || true
    fi
    if [ -n "${SS_TIMEOUT_WAS:-}" ] && [ "${SS_TIMEOUT_WAS:-0}" != "0" ]; then
        xset s "$SS_TIMEOUT_WAS" 2>/dev/null || true
    fi
}
xset s off -dpms 2>/dev/null || true

# ---- run ------------------------------------------------------------------
# always verbose: this log is the only trace a screensaver leaves behind, and
# it stays small (trimmed to 200 lines below)
DEBUG_ARG="--debug"

# One complete copy of the scene per monitor: the host builds one window per
# monitor by itself when neither --area nor --monitor pins a single rectangle.
# Labels are asked for explicitly (the page defaults to on, but a screensaver
# has no UI to switch them back on); orbital paths are switched OFF, they read
# as clutter on a wall-sized screen.  The frame rate is capped so that N
# monitors cost N x 30 fps instead of N x 60: the simulation keeps advancing
# with the real elapsed time, only the drawing is throttled.
SAVER_FPS=${SOLAR_SAVER_FPS:-30}

# shellcheck disable=SC2086
log_writable "$LOG" || LOG=/dev/null   # never let the log break the launch
python3 "$HOST" --mode saver --saver 1 --speed 6 $DEBUG_ARG \
    --no-orbits --with-labels --fps "$SAVER_FPS" --url "$PAGE" "$@" >>"$LOG" 2>&1 &
PID=$!
RC=0

CLEANED=0
cleanup() {
    [ "$CLEANED" = "1" ] && return 0
    CLEANED=1
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    restore
    log "stop  pid=$$ child=$PID rc=$RC"
}
trap 'RC=$?; cleanup; exit 0' INT TERM EXIT

wait "$PID"
RC=$?
restore
log "exit  pid=$$ child=$PID rc=$RC"
exit "$RC"
