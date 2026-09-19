#!/bin/sh
# install-solar-screensaver.sh — install / uninstall the Solar System
# screensaver theme and the live-wallpaper autostart entry for the current user.
#
#   ./install-solar-screensaver.sh install     # copy files + menu entries
#   ./install-solar-screensaver.sh uninstall   # remove everything it created
#   ./install-solar-screensaver.sh status      # show what is installed
#
# Nothing outside $HOME is touched unless you run the printed sudo command.

set -u

SRC=$(cd "$(dirname "$0")" && pwd)
DEST="$HOME/.local/bin/solar-screensaver"
THEME_DIR="$HOME/.local/share/applications/screensavers"
AUTOSTART_DIR="$HOME/.config/autostart"
SYS_THEME_DIR="/usr/share/applications/screensavers"

THEME_FILE="$THEME_DIR/solar-system.desktop"
AUTOSTART_FILE="$AUTOSTART_DIR/solar-wallpaper.desktop"

die() { echo "error: $*" >&2; exit 1; }

do_install() {
    [ -f "$SRC/solar-system-3d.html" ] || die "solar-system-3d.html not found next to this script"
    [ -f "$SRC/solar-webkit.py" ] || die "solar-webkit.py not found next to this script"

    echo "==> installing to $DEST"
    mkdir -p "$DEST" || die "cannot create $DEST"
    cp -f "$SRC/solar-system-3d.html" "$SRC/solar-webkit.py" \
          "$SRC/solar-saver.sh" "$SRC/solar-wallpaper.sh" "$DEST/" || die "copy failed"
    chmod 755 "$DEST/solar-webkit.py" "$DEST/solar-saver.sh" "$DEST/solar-wallpaper.sh"
    chmod 644 "$DEST/solar-system-3d.html"

    echo "==> registering the screensaver theme"
    mkdir -p "$THEME_DIR"
    cat > "$THEME_FILE" <<EOF
[Desktop Entry]
Name=Solar System
Comment=Interactive 3D solar system: real orbital elements, computed illumination. Written by hand in Canvas 2D.
# --root mirrors what the working stock themes receive; our launcher accepts
# and ignores it (it draws into the window the daemon gives us, or takes the
# screen itself when none is given)
Exec=$DEST/solar-saver.sh --root
TryExec=$DEST/solar-saver.sh
StartupNotify=false
Terminal=false
Type=Application
Categories=Screensaver;
OnlyShowIn=MATE;
EOF

    # The daemon resolves a theme by taking the id from gsettings (as written
    # by mate-screensaver-preferences, e.g. "screensavers-solar-system") and
    # opening "<id>.desktop" in its theme directories.  Our file is named
    # "solar-system.desktop", so that lookup fails and the screensaver silently
    # does nothing.  Ship an alias under the id-based name as well, hidden from
    # the preferences list so it does not appear twice.
    echo "==> adding the id-based alias (screensavers-solar-system.desktop)"
    sed 's/^Name=Solar System/Name=Solar System\nNoDisplay=true/' "$THEME_FILE" > "$THEME_DIR/screensavers-solar-system.desktop" \
        || die "cannot write the theme alias"

    # ---- live wallpaper autostart, configurable at install time -----------
    #   SOLAR_WALLPAPER_AREA="1920x1080+1920+0"   rectangle to fill
    #   SOLAR_WALLPAPER_ENABLE=1                  start it at login
    #   SOLAR_WALLPAPER_DELAY=8                   wait for the desktop first
    WP_AREA=${SOLAR_WALLPAPER_AREA:-}
    WP_DELAY=${SOLAR_WALLPAPER_DELAY:-8}
    WP_ENABLE=${SOLAR_WALLPAPER_ENABLE:-0}
    if [ "$WP_ENABLE" = "1" ]; then WP_FLAG=true; else WP_FLAG=false; fi
    ENVV=""
    [ -n "$WP_AREA" ] && ENVV="SOLAR_AREA=$WP_AREA "
    [ "$WP_DELAY" != "0" ] && ENVV="${ENVV}SOLAR_DELAY=$WP_DELAY "

    # ---- settings file: keeps the launcher switch-free ---------------------
    WP_SPEED=${SOLAR_WALLPAPER_SPEED:-0.5}
    CFG_DIR="$HOME/.config/solar-screensaver"
    mkdir -p "$CFG_DIR"
    cat > "$CFG_DIR/wallpaper.conf" <<EOF
# Solar System live wallpaper — read by solar-wallpaper.sh on every start.
# Any value can be overridden for a single run with the matching SOLAR_* var.
AREA=$WP_AREA
SPEED=$WP_SPEED
STACK=desktop
ORBITS=0
LABELS=0
STARS=1
BELT=1
DELAY=$WP_DELAY
EOF
    echo "==> wallpaper settings: $CFG_DIR/wallpaper.conf (area=${WP_AREA:-all})"

    echo "==> installing the live-wallpaper autostart entry (enabled=$WP_FLAG${WP_AREA:+, area $WP_AREA})"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Solar System wallpaper
Comment=Animated solar system as a live desktop background
Exec=$DEST/solar-wallpaper.sh
TryExec=$DEST/solar-wallpaper.sh
Terminal=false
NoDisplay=false
X-GNOME-Autostart-enabled=$WP_FLAG
X-MATE-Autostart-enabled=$WP_FLAG
EOF

    # The daemon (unlike the preferences dialog) loads its theme list from the
    # system data dirs at startup, so a user-level entry can end up visible in
    # the preferences but never launched.  SOLAR_SYSTEM_WIDE=1 copies it too.
    if [ "${SOLAR_SYSTEM_WIDE:-0}" = "1" ]; then
        echo "==> copying the theme into $SYS_THEME_DIR (needs sudo)"
        if sudo cp -f "$THEME_FILE" "$THEME_DIR/screensavers-solar-system.desktop" "$SYS_THEME_DIR/"; then
            echo "    ok: $SYS_THEME_DIR/{solar-system,screensavers-solar-system}.desktop"
        else
            echo "    FAILED - copy it by hand:" >&2
            echo "      sudo cp $THEME_FILE $SYS_THEME_DIR/" >&2
        fi
    else
        echo "    note: run with SOLAR_SYSTEM_WIDE=1 to also install the theme"
        echo "          system-wide (the daemon only reads system theme dirs)."
    fi

    echo
    echo "Installed."
    echo "  screensaver theme : $THEME_FILE"
    echo "                      $THEME_DIR/screensavers-solar-system.desktop (alias)"
    echo "  wallpaper entry   : $AUTOSTART_FILE   (enabled=$WP_FLAG${WP_AREA:+, area $WP_AREA})"
    echo
    echo "Next steps"
    echo "  1) Test the screensaver right now, without waiting for the idle timer:"
    echo "       $DEST/solar-saver.sh          # full screen, press Ctrl+C to stop"
    echo "  2) Look for \"Solar System\" in   mate-screensaver-preferences"
    echo "     (it is enabled by ticking the checkbox next to it)."
    echo "     If it is not listed, install it system-wide instead:"
    echo "       sudo cp $THEME_FILE $SYS_THEME_DIR/"
    echo "  2b) Restart the screensaver daemon so it re-reads its theme list"
    echo "      (it is loaded only at daemon start):"
    echo "        mate-screensaver-command --exit ; sleep 2"
    echo "        nohup mate-screensaver >/dev/null 2>&1 &"
    echo "  3) Live wallpaper: run it once with (no arguments needed)"
    echo "       $DEST/solar-wallpaper.sh"
    if [ "$WP_FLAG" = "true" ]; then
        echo "     It is enabled for the next login, filling ${WP_AREA:-all monitors}."
    else
        echo "     To start it automatically at login, re-run this installer with"
        echo "       SOLAR_WALLPAPER_ENABLE=1 SOLAR_WALLPAPER_AREA=\"1920x1080+1920+0\""
    fi
    echo "     Stop it any time with:  pkill -f solar-webkit.py"
    echo
    echo "Note: with 'lock-delay' at 0 the screen locks immediately, so you will"
    echo "see the MATE unlock dialog over the animation. To watch the animation"
    echo "alone:  gsettings set org.mate.screensaver lock-enabled false"
    echo "Display sleep is 30 min by default; the saver already disables DPMS"
    echo "while it runs, so the panel stays lit."
}

do_uninstall() {
    echo "==> removing $DEST"
    rm -rf "$DEST"
    rm -f "$THEME_FILE" "$THEME_DIR/screensavers-solar-system.desktop" "$AUTOSTART_FILE"
    # stop anything currently running
    pkill -f "solar-webkit.py" 2>/dev/null || true
    if [ -f "$SYS_THEME_DIR/solar-system.desktop" ]; then
        echo "note: a system-wide copy exists; remove it with:"
        echo "  sudo rm $SYS_THEME_DIR/solar-system.desktop $SYS_THEME_DIR/screensavers-solar-system.desktop"
    fi
    echo "Uninstalled."
}

do_status() {
    echo "screensaver theme : $([ -f "$THEME_FILE" ] && echo present || echo MISSING)  $THEME_FILE"
    echo "wallpaper entry   : $([ -f "$AUTOSTART_FILE" ] && echo present || echo MISSING)  $AUTOSTART_FILE"
    if [ -f "$AUTOSTART_FILE" ]; then
        echo "  autostart state : $(grep -h 'Autostart-enabled' "$AUTOSTART_FILE" | tr '\n' ' ')"
    fi
    echo "installed files   : $([ -d "$DEST" ] && ls "$DEST" | tr '\n' ' ' || echo MISSING)"
    echo "running now       : $(pgrep -fc '[s]olar-webkit.py' 2>/dev/null || echo 0) process(es)"
    echo "system-wide copy  : $([ -f "$SYS_THEME_DIR/solar-system.desktop" ] && echo present || echo none)"
}

case "${1:-install}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    status)    do_status ;;
    *)         echo "usage: $0 [install|uninstall|status]" >&2; exit 2 ;;
esac
