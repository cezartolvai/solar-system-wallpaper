#!/bin/sh
# solar-wallpaper.sh — Solar System as a live desktop wallpaper.
#
# The WebKit window is pinned below the desktop icons and made click-through,
# so the desktop stays fully usable (icons, right-click menu, drag & drop).
#
#   SOLAR_AREA=    put the canvas in one rectangle, e.g. 1920x1080+1920+0
#                  (use it to keep the region with your desktop icons free;
#                   MATE/caja draws the icons and the background in one opaque
#                   window, so a full-screen canvas always covers them)
#   SOLAR_SPAN=1   one canvas spanning every monitor (default)
#   SOLAR_SPAN=0   one independent canvas per monitor
#   SOLAR_SPEED=   days per second of the simulation (default 0.5 = calm)
#   SOLAR_STACK=   desktop | below | above   (window layer, default desktop)
#
# Stop it with:  pkill -f solar-webkit.py

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
PAGE="$DIR/solar-system-3d.html"
HOST="$DIR/solar-webkit.py"

# ---- settings: config file first, then the environment, then defaults ------
# The installer writes ~/.config/solar-screensaver/wallpaper.conf, so running
# this script with no arguments already does the right thing.  A SOLAR_*
# variable on the command line overrides the file for one run.
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/solar-screensaver/wallpaper.conf"
cfg() { [ -f "$CONF" ] && sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1; }

AREA=${SOLAR_AREA:-$(cfg AREA)}
SPEED=${SOLAR_SPEED:-$(cfg SPEED)}
STACK=${SOLAR_STACK:-$(cfg STACK)}
ORBITS=${SOLAR_ORBITS:-$(cfg ORBITS)}
LABELS=${SOLAR_LABELS:-$(cfg LABELS)}
STARS=${SOLAR_STARS:-$(cfg STARS)}
BELT=${SOLAR_BELT:-$(cfg BELT)}
DELAY=${SOLAR_DELAY:-$(cfg DELAY)}
SPAN=${SOLAR_SPAN:-1}

# built-in defaults (a wallpaper is calmer and cleaner than the interactive view)
SPEED=${SPEED:-0.5}
STACK=${STACK:-desktop}
ORBITS=${ORBITS:-0}
LABELS=${LABELS:-0}
STARS=${STARS:-1}
BELT=${BELT:-1}
DELAY=${DELAY:-0}
EXTRA=""
[ "$ORBITS" = "0" ] && EXTRA="$EXTRA --no-orbits"
[ "$LABELS" = "0" ] && EXTRA="$EXTRA --no-labels"
[ "$STARS"  = "0" ] && EXTRA="$EXTRA --no-stars"
[ "$BELT"   = "0" ] && EXTRA="$EXTRA --no-belt"

[ -f "$PAGE" ] || { echo "solar-wallpaper: missing $PAGE" >&2; exit 1; }
[ -f "$HOST" ] || { echo "solar-wallpaper: missing $HOST" >&2; exit 1; }

# ---- --print: show what would run, start nothing --------------------------
if [ "${1:-}" = "--print" ] || [ -n "${SOLAR_PRINT:-}" ]; then
    echo "config file : $CONF$([ -f "$CONF" ] || echo '  (missing, using defaults)')"
    echo "area        : ${AREA:-<all monitors>}"
    echo "speed       : $SPEED days/s"
    echo "layer       : $STACK"
    echo "orbits      : $ORBITS"
    echo "labels      : $LABELS"
    echo "stars       : $STARS"
    echo "belt        : $BELT"
    echo "start delay : ${DELAY}s"
    echo "command     : python3 $HOST --mode wallpaper --stack $STACK$([ -n "$AREA" ] && echo " --area $AREA") --saver drift --speed $SPEED$EXTRA --url $PAGE"
    exit 0
fi

PIDS=""
cleanup() {
    for p in $PIDS; do kill "$p" 2>/dev/null || true; done
    wait 2>/dev/null || true
    exit 0
}
trap 'cleanup' INT TERM EXIT

start_one() {
    # $1 = monitor index (empty = span all monitors)
    # Wait for the session (file manager desktop) to settle, otherwise caja's
    # desktop window can end up mapped above our canvas.
    if [ "${DELAY:-0}" -gt 0 ] 2>/dev/null; then sleep "$DELAY"; fi
    if [ -n "$1" ]; then
        # shellcheck disable=SC2086
        python3 "$HOST" --mode wallpaper --stack "$STACK" --monitor "$1" \
                --saver drift --speed "$SPEED" $EXTRA --url "$PAGE" &
    else
        python3 "$HOST" --mode wallpaper --stack "$STACK" \
                --saver drift --speed "$SPEED" --url "$PAGE" &
    fi
    PIDS="$PIDS $!"
}

if [ -n "$AREA" ]; then
    # shellcheck disable=SC2086
    python3 "$HOST" --mode wallpaper --stack "$STACK" --area "$AREA" \
            --saver drift --speed "$SPEED" $EXTRA --url "$PAGE" &
    PIDS="$PIDS $!"
elif [ "$SPAN" = "1" ]; then
    start_one ""
else
    N=$(xrandr --listmonitors 2>/dev/null | tail -n +2 | wc -l)
    [ "${N:-0}" -ge 1 ] 2>/dev/null || N=1
    i=0
    while [ "$i" -lt "$N" ]; do
        start_one "$i"
        i=$((i + 1))
    done
fi

wait
