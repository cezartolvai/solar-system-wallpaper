#!/bin/sh
# try-theme-ids.sh — află care formă de ID de temă este lansată de mate-screensaver.
#
# Context: daemonul ia numele temei din `org.mate.screensaver themes` și, pe acest
# sistem, creează joburile cu comanda NULL („No command set for job"), adică nu
# rezolvă tema. Fereastra de preferințe scrie un ID cu prefix (`screensavers-...`),
# dar nu e sigur că e forma pe care o așteaptă daemonul la lansare.
#
# Scriptul încearcă pe rând câte un ID, repornește daemonul, activează screensaver-ul
# și verifică jurnalul ~/.cache/solar-screensaver.log. La final lasă activ ID-ul care
# a funcționat, sau restaurează valoarea inițială dacă niciunul nu merge.
#
# RULARE: din sesiunea grafică (are nevoie de gsettings + ecran).
#         Ecranul se blochează ~8 secunde pentru fiecare ID încercat (lock-delay=0).

set -u

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/solar-screensaver.log"
CANDIDATES="solar-system screensavers-solar-system"
ORIGINAL=$(gsettings get org.mate.screensaver themes 2>/dev/null || echo "['screensavers-solar-system']")

[ -f "$LOG" ] || : > "$LOG" 2>/dev/null

restart_daemon() {
    mate-screensaver-command --exit >/dev/null 2>&1
    sleep 1
    setsid nohup mate-screensaver >/dev/null 2>&1 < /dev/null &
    sleep 2
}

count_lines() { wc -l < "$LOG" 2>/dev/null | tr -d ' ' || echo 0; }

try_id() {
    id=$1
    printf '\n== încerc ID-ul: %s\n' "$id"
    gsettings set org.mate.screensaver themes "['$id']" 2>/dev/null
    printf '   setat: %s\n' "$(gsettings get org.mate.screensaver themes 2>/dev/null)"
    restart_daemon
    before=$(count_lines)
    mate-screensaver-command -a >/dev/null 2>&1
    printf '   screensaver activat, aștept 6 s...\n'
    sleep 6
    mate-screensaver-command -d >/dev/null 2>&1
    sleep 1
    after=$(count_lines)
    if [ "$after" -gt "$before" ]; then
        printf '   ✅ TEMA A FOST LANSATĂ (%s linii noi în jurnal):\n' "$((after - before))"
        tail -n "$((after - before))" "$LOG" | sed 's/^/      /'
        return 0
    fi
    printf '   ✗ nimic nou în jurnal (tema nu a fost lansată cu acest ID)\n'
    return 1
}

working=""
for c in $CANDIDATES; do
    if try_id "$c"; then working=$c; break; fi
done

printf '\n== rezultat\n'
if [ -n "$working" ]; then
    gsettings set org.mate.screensaver themes "['$working']" 2>/dev/null
    printf '   ID care funcționează: %s (lăsat activ)\n' "$working"
    printf '   Screensaver-ul ar trebui să meargă acum și la activarea normală.\n'
else
    gsettings set org.mate.screensaver themes "$ORIGINAL" 2>/dev/null
    printf '   Niciun ID nu a funcționat. Am restaurat valoarea inițială: %s\n' "$ORIGINAL"
    printf '   Următorul pas: captura debug-ului daemonului în timpul activării\n'
    printf '   (vezi MANIFEST.md, secțiunea „Depanare screensaver").\n'
fi
printf '   daemon: %s\n' "$(pgrep -f 'mate-screensaver$' | head -1 || echo 'nu rulează — pornește-l cu: nohup mate-screensaver >/dev/null 2>&1 &')"
