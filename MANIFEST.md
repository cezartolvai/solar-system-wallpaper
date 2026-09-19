# Manifest — Solar System (screensaver + fundal live)

**Versiune 1.0.0 · 2026-09-19 · Linux Mint 22 (Wilma), MATE, X11, 2 × 1920×1080**

Acest fișier răspunde la o singură întrebare: *ce este instalat unde, de ce, și cum
verific peste 10 ani că încă funcționează.*

---

## 1. Ce este proiectul

O simulare 3D interactivă a sistemului solar, scrisă într-un **singur fișier HTML**
(canvas 2D, fără WebGL, fără librării, fără rețea — rulează offline din `file://`),
împachetată de o gazdă nativă GTK/WebKit ca să poată rula în două roluri:

| rol | cum se comportă |
|---|---|
| **fundal live** (folosit acum) | fereastră în stratul `desktop`, lipită sub ferestrele normale, click-through; desenează sistemul solar pe monitorul 2 |
| **screensaver** ⚠️ *experimental* | temă pentru `mate-screensaver`; desenează în fereastra dată de daemon (`XSCREENSAVER_WINDOW`) sau fullscreen dacă rulează manual. Pe MATE 1.26.2 daemonul nu o lansează încă — vezi secțiunea 7b |

---

## 2. Fișierele proiectului — sursa de adevăr

Rulează `./verify.sh` pentru a compara checksum-urile de mai jos cu fișierele actuale.

| fișier | rol | sha256 (v1.0.0) |
|---|---|---|
| `solar-system-3d.html` | simularea: date astronomice, pipeline 3D scris de mână, interfață, modul `?saver` | `7df1176eabb40193…` |
| `solar-webkit.py` | gazda GTK3 + WebKit2GTK: fereastră fullscreen / fundal / embedding prin reparentare X11, `--selftest`, `--geometry-check`, `--print` | `47e4def8a03c763a…` |
| `solar-wallpaper.sh` | lansatorul de fundal: citește `wallpaper.conf`, pornește fără argumente | `b16b7bdf41dc85b4…` |
| `solar-saver.sh` | lansatorul de screensaver: jurnal, DPMS, robust la mediu minimal | `b87e9ae4907f3dd7…` |
| `install-solar-screensaver.sh` | installer/dezinstaler: copiază în `~/.local`, scrie tema, autostartul și `wallpaper.conf` | `4cd63b9219bfb6f8…` |
| `README.md` | ghidul complet (română): instalare, parametri, capcane, alternativă Wayland | — |
| `MANIFEST.md` | acest fișier | — |
| `CHANGELOG.md` | istoricul deciziilor și al problemelor rezolvate (cu dovezi) | — |
| `verify.sh` | verificare de sănătate într-o comandă | — |
| `VERSION` | versiunea și data | — |

Folderul este **mutabil**: toate scripturile își calculează căile relativ la propria
locație. După mutare rulează din nou installerul, ca să actualizeze copiile instalate
care conțin căi absolute.

---

## 3. Ce s-a instalat pe sistem

| cale | ce este | se regenerează cu |
|---|---|---|
| `~/.local/bin/solar-screensaver/` | copiile care rulează efectiv (`solar-webkit.py`, `solar-system-3d.html`, `solar-saver.sh`, `solar-wallpaper.sh`) | `./install-solar-screensaver.sh install` |
| `~/.config/solar-screensaver/wallpaper.conf` | setările fundalului (arie, viteză, straturi) | idem (din variabilele `SOLAR_WALLPAPER_*`) |
| `~/.config/autostart/solar-wallpaper.desktop` | pornirea automată la login (`Exec=…/solar-wallpaper.sh`) | idem (`SOLAR_WALLPAPER_ENABLE=1`) |
| `~/.local/share/applications/screensavers/solar-system.desktop` | tema de screensaver (vizibilă în preferences) | idem |
| `~/.local/share/applications/screensavers/screensavers-solar-system.desktop` | alias cu numele cerut de ID-ul din `gsettings` (ascuns din listă cu `NoDisplay=true`) | idem |
| `/usr/share/applications/screensavers/solar-system.desktop` + aliasul | copia system-wide, pentru daemon (are nevoie de `sudo`) | `SOLAR_SYSTEM_WIDE=1 ./install-solar-screensaver.sh install` |

Fișierele instalate **nu** sunt link-uri: sunt copii. Modifici sursele în acest folder,
apoi rulezi installerul.

---

## 4. Configurația activă (2026-09-19)

`~/.config/solar-screensaver/wallpaper.conf`:

```
AREA=1920x1080+1920+0      # monitorul 2 (toate iconițele sunt pe monitorul 1)
SPEED=0.5                  # zile/secundă — derivă lentă
STACK=desktop              # sub ferestrele normale, deasupra fundalului caja
ORBITS=0                   # fără linii orbitale
LABELS=0                   # fără etichete
STARS=1
BELT=1
DELAY=8                    # la login, așteaptă desktopul înainte de a apărea
```

Setări MATE relevante:

```sh
gsettings get org.mate.screensaver lock-enabled     # true
gsettings get org.mate.screensaver lock-delay       # 0  -> blocare imediată
gsettings get org.mate.screensaver themes           # ['screensavers-solar-system']
gsettings get org.mate.power-manager sleep-display-ac  # 1800 (30 min)
```

---

## 5. Verificare (comenzile care contează)

```sh
cd <acest folder>
./verify.sh                                   # tot, într-o comandă, cu PASS/FAIL

./install-solar-screensaver.sh status         # ce e instalat, ce rulează
./solar-wallpaper.sh --print                  # ce ar porni, fără să deschidă nimic
./solar-webkit.py --selftest                  # randează pagina off-screen, raportează erori JS

# repornire fundal după o modificare:
pkill -f solar-webkit.py ; ~/.local/bin/solar-screensaver/solar-wallpaper.sh &
```

Un fundal sănătos înseamnă: `pgrep -af solar-webkit` arată **un** proces cu
`--area 1920x1080+1920+0`, iar pe monitorul 2 se vede sistemul solar (fără orbite,
fără etichete) peste un fundal negru.

---

## 6. Dependențe

| componentă | versiune la construire | dacă dispare / se schimbă |
|---|---|---|
| Python 3 + PyGObject | 3.12.3 / 3.48.2 | `solar-webkit.py` are nevoie de `python3-gi` |
| GTK 3 | 3.24.41 | GTK 4 ar cere rescrierea ferestrelor (GTK4 nu are `Gtk.Plug`, iar API-ul de ferestre s-a schimbat) |
| WebKit2GTK | 2.52.6 (`gir1.2-webkit2-4.1`) | dacă apare doar 4.2/5.x, se schimbă `gi.require_version` din `solar-webkit.py` (căutat automat 4.1 → 4.0) |
| x11-utils (`xwininfo`), `xrandr`, `xset` | prezente în Mint | folosite doar pentru diagnostic, plasare și DPMS |
| libX11 | sistem | folosit prin `ctypes` pentru reparentare (fără `python3-xlib`) |
| mate-screensaver | 1.26.2 | opțional: rolul de fundal live nu depinde de el |

---

## 7. Dezinstalare completă

```sh
./install-solar-screensaver.sh uninstall        # șterge copiile din ~/.local și intrările
pkill -f solar-webkit.py                        # oprește fundalul care rulează
sudo rm -f /usr/share/applications/screensavers/solar-system.desktop \
           /usr/share/applications/screensavers/screensavers-solar-system.desktop
```

---

## 7b. Depanare screensaver (experimental)

Pe acest sistem tema **nu este lansată** de daemon la activare. Rețeta care scoate la
iveală cauza (are nevoie de ~10 secunde de ecran blocat, dacă nu dezactivezi întâi
blocarea):

```sh
# 1. oprește daemonul normal (altfel --debug refuză: "screensaver already running")
mate-screensaver-command --exit ; sleep 1

# 2. opțional: fără blocare imediată, ca să vezi animația la test
gsettings set org.mate.screensaver lock-enabled false

# 3. pornește daemonul cu debug, în prim-plan, într-un terminal
mate-screensaver --no-daemon --debug 2>&1 | tee /tmp/ms-debug.log

# 4. în ALT terminal: activează și verifică jurnalul nostru
mate-screensaver-command -a ; sleep 4 ; tail -12 ~/.cache/solar-screensaver.log

# 5. revino la normal
gsettings set org.mate.screensaver lock-enabled true
nohup mate-screensaver >/dev/null 2>&1 &
```

Ce se caută în `/tmp/ms-debug.log`: cum rezolvă daemonul ID-ul temei
(`screensavers-solar-system`), dacă apare mesajul
„*%s does not appear to be a valid screensaver theme*", și dacă încearcă vreun
`g_spawn` al comenzii din `Exec`. În jurnalul nostru ar trebui să apară
`start … XSCREENSAVER_WINDOW=0x…` plus liniile `embed:` cu depth/visual/map.

## 8. Capcane cunoscute (ca să nu le redescoperi peste 10 ani)

1. **`caja` desenează fundalul ȘI iconițele într-o singură fereastră opacă** (24 biți,
   3840×1080, fără sub-ferestre). Deci o animație pe tot ecranul acoperă obligatoriu
   iconițele, iar una plasată *sub* fereastra desktopului devine invizibilă. Soluția
   folosită: fundalul ocupă doar monitorul 2, care nu are iconițe.
2. **Marco plasează ferestrele normale pe monitorul unde e cursorul** și ignoră poziția
   cerută; doar ferestrele de tip `desktop` (sau cele care nu încap pe un monitor)
   respectă geometria cerută. De aceea fundalul folosește stratul `desktop`.
3. **Screensaver-ul nu pornea** pentru că daemonul își încarcă lista de teme la pornire
   și rezolvă tema ca `<id>.desktop`; tema instalată doar în `~/.local` nu era găsită.
   S-a rezolvat cu copie system-wide + alias `screensavers-solar-system.desktop` +
   repornirea daemonului (`mate-screensaver-command --exit ; nohup mate-screensaver &`).
4. **`lock-delay=0`**: la activare ecranul se blochează imediat, deci tema se vede în
   spatele dialogului de deblocare (comportament normal al MATE).
5. **WebKit forțează uneori un visual RGBA (32 biți)**; reparentarea într-o fereastră de
   24 de biți eșuează cu `BadMatch`, iar Xlib, la eroare asincronă, **termină procesul**
   implicit. Gazda citește acum visualul real al gazdei și instalează un handler X care
   loghează în loc să moară.
6. **`Gtk.Plug` nu e potrivit** pentru `XSCREENSAVER_WINDOW`: vorbește XEMBED și rămâne
   nemapată cu o fereastră străină. Corect este reparentarea X11 brută
   (`XReparentWindow` + `XMoveResizeWindow` + `XMapWindow`), ca la xwinwrap.
7. În `~/.xsession-errors` pot rămâne mesaje `GLib-CRITICAL … Source ID … not found`
   de la `mate-screensaver`: sunt inofensive, apar la fiecare ciclu de activare.

---

## 9. Arhivare și publicare (git / GitHub)

Repo git local în acest folder: branch `main`, tag `v1.0.0`.

```sh
git log --oneline --decorate      # istoric
git tag -l                        # versiuni
git bundle verify solar-system-v1.0.0.bundle    # verifică arhiva de backup
```

**Publicat:** <https://github.com/cezartolvai/solar-system-wallpaper> (public, branch
`main`, tag `v1.0.0`, primul push 2026-09-19). Remote-ul `origin` e deja configurat.

Pentru versiuni viitoare:

```sh
git add -A && git commit -m "v1.0.1 — ..."
git tag -a v1.0.1 -m "v1.0.1"
git push && git push --tags
```

Autentificare: cheie SSH în contul GitHub (Settings → SSH keys, tip *Authentication Key*;
fingerprint-ul cheii de pe această mașină este `SHA256:glIshkrJvgLMD0qP+za0VweT+3dbDf9hwE+Tw97yyjY`)
sau token HTTPS, ori `sudo apt install gh && gh auth login` apoi
`gh repo create <repo> --public --source . --push`.

Arhivele locale (`*.bundle`, `*.tar.gz`) **nu** urcă pe GitHub (vezi `.gitignore`);
`git bundle` rămâne metoda de backup într-un singur fișier.

Fișierele `*.bundle` și `*.tar.gz` din folder sunt excluse din repo (vezi `.gitignore`) —
sunt arhive locale de backup, nu parte din proiect.

---

## 10. Mediu la data construirii

```
Linux Mint 22 (Wilma), kernel 6.8.0-139-generic, x86_64
MATE (mate-screensaver 1.26.2), X11 (nu Wayland)
GTK 3.24.41 · WebKit2GTK 2.52.6 · Python 3.12.3 · PyGObject 3.48.2
Monitoare: 2 × 1920×1080 (virtual 3840×1080), tot ce e în stânga are iconițe
GPU/GL: disponibil (WebKit folosește accelerare hardware; în modul embedded trece pe software)
```
