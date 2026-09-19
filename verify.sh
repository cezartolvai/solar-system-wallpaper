#!/bin/sh
# verify.sh — verificare de sănătate pentru Solar System (screensaver + fundal live).
#
# Rulează tot ce se poate verifica fără să deschidă ferestre pe ecran:
# fișiere + checksum-uri, sintaxă, ce e instalat, ce ar porni, randare off-screen
# și geometria reală a ferestrelor. Iese cu cod 0 dacă totul e în regulă.
#
#   ./verify.sh            verificare completă
#   ./verify.sh --quick    sare peste testele care pornesc procese WebKit

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1
FAIL=0
PASS=0

ok()   { PASS=$((PASS+1)); printf '  [ OK ]   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  [FAIL]   %s\n' "$1"; }
info() { printf '  [info]   %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

# ---------------------------------------------------------------- 1. fișiere
head_ "1. Fișierele proiectului"
for f in solar-system-3d.html solar-webkit.py solar-saver.sh solar-wallpaper.sh \
         install-solar-screensaver.sh README.md MANIFEST.md CHANGELOG.md VERSION; do
    if [ -f "$DIR/$f" ]; then ok "$f ($(wc -c < "$DIR/$f") bytes)"; else bad "$f lipsește"; fi
done
if command -v sha256sum >/dev/null 2>&1; then
    info "checksum-uri actuale (compară cu MANIFEST.md):"
    (cd "$DIR" && sha256sum solar-system-3d.html solar-webkit.py \
        solar-saver.sh solar-wallpaper.sh install-solar-screensaver.sh) | sed 's/^/           /'
fi

# ---------------------------------------------------------------- 2. sintaxă
head_ "2. Sintaxă"
if command -v python3 >/dev/null 2>&1; then
    python3 -m py_compile "$DIR/solar-webkit.py" 2>/dev/null && ok "solar-webkit.py (python)" \
        || bad "solar-webkit.py nu compilează"
    rm -rf "$DIR/__pycache__" 2>/dev/null
else
    bad "python3 lipsește — gazda nu poate rula"
fi
for s in solar-saver.sh solar-wallpaper.sh install-solar-screensaver.sh; do
    sh -n "$DIR/$s" 2>/dev/null && ok "$s (shell)" || bad "$s are erori de sintaxă"
done
if command -v node >/dev/null 2>&1; then
    tmp=$(mktemp /tmp/solar-js-XXXXXX.js 2>/dev/null || echo "/tmp/solar-js-$$.js")
    python3 - "$DIR/solar-system-3d.html" "$tmp" <<'PY' 2>/dev/null
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<script>(.*)</script>', src, re.S)
open(sys.argv[2], 'w', encoding='utf-8').write(m.group(1) if m else '')
PY
    node --check "$tmp" 2>/dev/null && ok "solar-system-3d.html (javascript)" \
        || bad "javascript-ul din pagină nu e valid"
    rm -f "$tmp"
else
    info "node lipsește — sărit testul de sintaxă JS (opțional)"
fi

# ---------------------------------------------------------------- 3. instalare
head_ "3. Ce este instalat"
if [ -x "$DIR/install-solar-screensaver.sh" ]; then
    "$DIR/install-solar-screensaver.sh" status 2>/dev/null | sed 's/^/           /'
    if [ -d "$HOME/.local/bin/solar-screensaver" ]; then
        ok "copiile instalate există (~/.local/bin/solar-screensaver)"
        for f in solar-webkit.py solar-system-3d.html solar-wallpaper.sh; do
            if [ -f "$HOME/.local/bin/solar-screensaver/$f" ]; then
                if cmp -s "$DIR/$f" "$HOME/.local/bin/solar-screensaver/$f"; then
                    ok "$f instalat = sursa"
                else
                    bad "$f instalat DIFERĂ de sursă (rulează installerul)"
                fi
            fi
        done
    else
        bad "nu e instalat (rulează ./install-solar-screensaver.sh install)"
    fi
fi

# ------------------------------------------------- 3b. tema de screensaver
head_ "3b. Tema de screensaver (regula din sursa mate-screensaver)"
THEME="$HOME/.local/share/applications/screensavers/solar-system.desktop"
if [ -f "$THEME" ]; then
    exec_line=$(sed -n 's/^Exec=//p' "$THEME" | head -1)
    prog=$(printf '%s' "$exec_line" | awk '{print $1}')
    dir=$(dirname "$prog")
    info "Exec: $exec_line"
    case "$dir" in
        /usr/libexec/mate-screensaver|/usr/libexec/xscreensaver|/usr/lib/xscreensaver)
            if [ -x "$prog" ]; then
                ok "programul e într-un director acceptat de daemon și e executabil"
            else
                bad "$prog nu e executabil"
            fi ;;
        *)
            bad "Exec-ul NU e într-un director acceptat de daemon: $dir"
            info "  mate-screensaver (src/gs-theme-manager.c) acceptă doar:" 
            info "    /usr/libexec/mate-screensaver (SAVERDIR), /usr/libexec/xscreensaver, /usr/lib/xscreensaver"
            info "  remediază: SOLAR_SYSTEM_WIDE=1 ./install-solar-screensaver.sh install" ;;
    esac
fi

# ---------------------------------------------------------------- 4. config
head_ "4. Configurația fundalului"
if [ -x "$DIR/solar-wallpaper.sh" ]; then
    "$DIR/solar-wallpaper.sh" --print 2>/dev/null | sed 's/^/           /'
    out=$("$DIR/solar-wallpaper.sh" --print 2>/dev/null)
    case "$out" in
        *"orbits      : 0"*) ok "orbitele sunt oprite (fundal curat)" ;;
        *) info "orbitele sunt pornite (poate ai setat ORBITS=1)" ;;
    esac
    case "$out" in
        *"area        : <all monitors>"*)
            bad "AREA e gol: fundalul acoperă TOATE monitoarele, inclusiv iconițele"
            info "  remediază: pune AREA=1920x1080+1920+0 în ~/.config/solar-screensaver/wallpaper.conf"
            info "  sau rulează installerul cu SOLAR_WALLPAPER_AREA=\"1920x1080+1920+0\"" ;;
        *) ok "fundalul e limitat la o zonă (nu acoperă tot desktopul)" ;;
    esac
fi

# ---------------------------------------------------------------- 5. randare
if [ "$QUICK" = "0" ]; then
    head_ "5. Randare off-screen (WebKitGTK)"
    if command -v python3 >/dev/null 2>&1 && [ -x "$DIR/solar-webkit.py" ]; then
        res=$(timeout 60 python3 "$DIR/solar-webkit.py" --selftest \
              --query "?saver=drift&orbits=0&labels=0" --out /tmp/solar-verify.png 2>/dev/null)
        echo "$res" | grep -E "selftest: (webkit|snapshot|pixels|verdict|dom)" | sed 's/^/           /'
        echo "$res" | grep -q "RENDERING OK" && ok "pagina se randează" || bad "randarea a eșuat"
        echo "$res" | grep -q '"errs":\[\]' && ok "fără erori JavaScript" || bad "erori JavaScript în pagină"
    fi
    head_ "6. Geometria ferestrelor (invizibil, opacitate 0)"
    if [ -x "$DIR/solar-webkit.py" ]; then
        timeout 60 python3 "$DIR/solar-webkit.py" --geometry-check --mode wallpaper \
            --area "1920x1080+1920+0" 2>/dev/null | grep -E "^geometry-check" | sed 's/^/           /'
        ok "geometry-check a rulat (vezi linia de mai sus)"
    fi
else
    head_ "5-6. Teste de randare și geometrie: sărite (--quick)"
fi

# ---------------------------------------------------------------- 7. procese
head_ "7. Ce rulează acum"
n=$(pgrep -fc '[s]olar-webkit' 2>/dev/null || echo 0)
if [ "$n" -gt 0 ] 2>/dev/null; then
    pgrep -af '[s]olar-webkit' | sed 's/^/           /'
    ok "$n proces(e) de fundal rulează"
else
    info "niciun proces de fundal nu rulează (pornește-l cu solar-wallpaper.sh)"
fi
if [ -f "$HOME/.cache/solar-screensaver.log" ]; then
    info "ultimele linii din jurnalul de screensaver:"
    tail -3 "$HOME/.cache/solar-screensaver.log" | sed 's/^/           /'
fi

# ---------------------------------------------------------------- rezumat
printf '\n== Rezumat: %d verificări trecute, %d eșuate\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] && echo "   Sistemul solar e sănătos." || echo "   Vezi liniile [FAIL] de mai sus."
exit $([ "$FAIL" = "0" ] && echo 0 || echo 1)
