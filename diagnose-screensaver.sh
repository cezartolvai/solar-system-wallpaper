#!/bin/sh
# diagnose-screensaver.sh — de ce nu lansează mate-screensaver tema noastră.
#
# Compară tema noastră cu teme STOCK (care ar trebui să meargă) și citește din
# debug-ul daemonului comanda pe care o rezolvă pentru fiecare. Dovada decisivă e
# linia „[gs_job_set_command] Setting command for job: '...'":
#   - dacă pentru o temă stock apare o comandă reală => daemonul poate lansa teme,
#     deci diferența e la intrarea noastră;
#   - dacă pentru TOATE apare 'NULL' => pe acest sistem daemonul nu lansează nicio
#     temă externă, iar partea de screensaver rămâne WIP (documentat).
#
# Rulează din sesiunea grafică. Dezactivează TEMPORAR blocarea ecranului, ca testul
# să nu-ți ceară parola, și restaurează totul la final.

set -u

PROJ=$(cd "$(dirname "$0")" && pwd)
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/solar-screensaver.log"
OUT="$PROJ/diag"
mkdir -p "$OUT" 2>/dev/null || OUT=/tmp

# tema noastră + două teme stock (cu ambele forme de ID)
CANDIDATES="screensavers-solar-system solar-system screensavers-abstractile abstractile"

ORIG_THEMES=$(gsettings get org.mate.screensaver themes 2>/dev/null || echo "[]")
ORIG_LOCK=$(gsettings get org.mate.screensaver lock-enabled 2>/dev/null || echo "true")

restore_all() {
    gsettings set org.mate.screensaver themes "$ORIG_THEMES" 2>/dev/null
    gsettings set org.mate.screensaver lock-enabled "$ORIG_LOCK" 2>/dev/null
    mate-screensaver-command --exit >/dev/null 2>&1
    sleep 1
    setsid nohup mate-screensaver >/dev/null 2>&1 < /dev/null &
    sleep 2
    printf '\n== restaurat: themes=%s lock-enabled=%s daemon=%s\n' \
        "$ORIG_THEMES" "$ORIG_LOCK" "$(pgrep -f 'mate-screensaver$' | head -1 || echo 'oprit')"
}
trap 'restore_all; exit 0' INT TERM

printf '== diagnostic screensaver\n'
printf '   jurnal nostru: %s\n' "$LOG"
printf '   loguri debug:  %s/ms-<id>.log\n' "$OUT"
[ -f "$LOG" ] || : > "$LOG" 2>/dev/null
lines_of() { wc -l < "$LOG" 2>/dev/null | tr -d ' ' || echo 0; }

printf '\n== dezactivez temporar blocarea (fără parolă la test)\n'
gsettings set org.mate.screensaver lock-enabled false 2>/dev/null
printf '   lock-enabled = %s\n' "$(gsettings get org.mate.screensaver lock-enabled 2>/dev/null)"

printf '\n%-28s %-46s %s\n' 'ID TEMĂ' 'COMANDA REZOLVATĂ DE DAEMON' 'JURNALUL NOSTRU'
printf '%-28s %-46s %s\n' '----------------------------' '----------------------------------------------' '---------------'

for id in $CANDIDATES; do
    gsettings set org.mate.screensaver themes "['$id']" 2>/dev/null
    mate-screensaver-command --exit >/dev/null 2>&1
    sleep 1
    dbg="$OUT/ms-$id.log"
    setsid nohup mate-screensaver --no-daemon --debug > "$dbg" 2>&1 < /dev/null &
    sleep 2
    before=$(lines_of)
    mate-screensaver-command -a >/dev/null 2>&1
    sleep 6
    mate-screensaver-command -d >/dev/null 2>&1
    sleep 1
    after=$(lines_of)

    cmd=$(grep -a "Setting command for job" "$dbg" 2>/dev/null | head -1 | sed "s/.*Setting command for job: //")
    got=$((after - before))
    [ -z "$cmd" ] && cmd="(nu apare linia)"
    case "$cmd" in
        *NULL*) verdict="✗ comandă NULL" ;;
        *solar-saver*) verdict="✅ comanda noastră!" ;;
        *xscreensaver*|*/mate-screensaver/*) verdict="✅ temă stock lansată" ;;
        *) verdict="?" ;;
    esac
    printf '%-28s %-46s %s linii  %s\n' "$id" "$cmd" "$got" "$verdict"

    mate-screensaver-command --exit >/dev/null 2>&1
    sleep 1
done

printf '\n== linii relevante din debug-urile capturate\n'
for f in "$OUT"/ms-*.log; do
    [ -f "$f" ] || continue
    printf -- '-- %s\n' "$(basename "$f")"
    grep -aE "Setting command for job|No command set|gs_job_start|does not appear to be a valid|theme" "$f" 2>/dev/null | head -6 | sed 's/^/     /'
done

restore_all
