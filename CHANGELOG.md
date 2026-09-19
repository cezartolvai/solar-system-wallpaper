# Istoric — Solar System (screensaver + fundal live)

Tot ce s-a construit, tot ce a eșuat și **de ce**, ca să nu fie nevoie să
redescoperi nimic. Fiecare concluzie are lângă ea dovada care a stabilit-o.

---

## 2026-09-19 — v1.0.0

### 1. Simularea (`solar-system-3d.html`)

Construită ca **un singur fișier**, offline, fără WebGL/librării/CDN: pipeline 3D scris
de mână (world → cameră → proiecție perspectivă → sortare pe adâncime), orbite
kepleriene cu elemente reale J2000, iluminare direcțională de la Soare, inelele lui
Saturn tesselate în 216 quad-uri sortate față/spate de glob, centură de asteroizi cu
rotație diferențială (Kepler III), câmp de stele determinist (PRNG cu seed).

Verificat: perioade siderale reale cu eroare < 0,13 %, echinocțiul din 2024 la ~0,3 zile
(fără precesie), faza corpurilor corectă (cos între „spre Soare" și „spre întuneric"
între −0,96 și −1,00), 60 fps la 1366×768 și 390×844.

**Bug-uri găsite la audit (și reparate):**
- `drawPatch()` aplica stilurile **înainte** de `ctx.restore()`, deci toate
  continentele/craterele/petele se desenau în culoarea de bază — invizibile.
- `drawBand()` compara raza **din lume** (0,8–4,4 unități) cu pragul 3,5, deci
  căpăcelele polare ale Pământului/Marte și benzile lui Uranus/Neptun nu se desenau.
- Sortarea cozii de desenare punea sloturile nefolosite (adâncime `+Infinity`) **primele**,
  așa că bucla de desen se oprea imediat: **niciun corp nu era desenat** (doar stele,
  orbite, etichete). Corectat cu santinelă `-Infinity` și compararea `<=`.
- Algoritmul de calitate adaptivă era un clichet: pragul de revenire (13,5 ms) e
  imposibil pe un ecran de 60 Hz (16,7 ms/frame). Acum pragurile sunt relative la
  cadența reală a ecranului.

### 2. Rolul de screensaver (MATE)

`mate-screensaver` **nu dă argumente** temelor: exportă `XSCREENSAVER_WINDOW=<id>` și
așteaptă ca tema să deseneze în acea fereastră (contractul xscreensaver, găsit cu
`strings /usr/bin/mate-screensaver`).

Încercări și concluzii:
- `Gtk.Plug` **nu merge**: vorbește XEMBED și, cu o fereastră străină, rămâne
  **nemapată** (măsurat: 9×16 px). Corect: reparentare X11 brută prin `ctypes`
  (`XReparentWindow`/`XMoveResizeWindow`/`XMapWindow`), ca la xwinwrap. Verificat:
  fereastră-copil 900×600 `IsViewable`, cu pixeli reali de scenă (culori (124,120,104),
  (3,5,13)) și 2,7 % pixeli schimbați între cadre.
- Ipoteza „depth diferit ⇒ `BadMatch`" a fost **respinsă experimental** (cu o țintă de
  24 biți embedding-ul funcționa). Lecturile GDK ne-au indus în eroare: pentru ferestre
  străine `get_visual()` întoarce **visualul implicit al ecranului**, nu pe cel real.
  Adevărul se citește din X (`xwininfo`). Păstrat totuși fixul de potrivire a
  visualului + handler X non-fatal (Xlib omoară procesul la orice eroare asincronă).
- Tema nu era lansată deloc: daemonul își încarcă lista de teme **la pornire** și
  rezolvă tema ca `<id>.desktop` (`strings` → `%s.desktop`, „%s does not appear to be a
  valid screensaver theme"). Tema exista doar în `~/.local`, iar daemonul citește
  directoarele de sistem → copie system-wide + alias cu numele din `gsettings` +
  repornirea daemonului.

**Concluzie:** screensaver-ul rămâne o cale secundară, cu capcane de integrare;
fundalul live este calea folosită.

**Stare consemnată (2026-09-19):** screensaver-ul este marcat **experimental / WIP** în
README și MANIFEST. Rămâne în repo pentru că implementarea e reală și verificată izolat
(contractul `XSCREENSAVER_WINDOW`, reparentare X11, potrivire de visual, handler X
non-fatal, fullscreen la rulare manuală), dar integrarea cu daemonul nu e validată:
`mate-screensaver` 1.26.2 își rezolvă temele la activare, iar pe acest sistem nu a
lansat tema. Rețeta de depanare (cu debug-ul daemonului în timpul activării) e în
`MANIFEST.md`, secțiunea 7b — de continuat acolo dacă e vreodată nevoie.

### 3. Rolul de fundal live (calea aleasă)

- Fereastră în stratul `desktop`, `set_pass_through(True)` (click-through), fără focus,
  `X-GNOME-Autostart` la login cu 8 s întârziere (ca desktopul caja să fie sus primul).
- **Descoperire decisivă:** `caja` ține fundalul *și* iconițele într-o singură fereastră
  opacă (24 biți, 3840×1080, fără sub-ferestre) ⇒ nu există „între fundal și iconițe".
  Toate cele 87 de iconițe sunt pe monitorul 1 (x = 64…1000), deci animația a fost
  restrânsă la **monitorul 2** (`1920x1080+1920+0`) — zero suprapuneri.
- **Marco** plasează ferestrele normale pe monitorul cursorului și ignoră poziția cerută;
  `Gtk.Window.resize()` e ignorat pentru ferestre neresizable înainte de mapare
  (simptom: animația apărea doar într-un colț, ~1/8 din ecran). Rezolvat cu
  `set_default_size()` + `move_resize()` la mapare.
- Fără comutatoare: setările stau în `~/.config/solar-screensaver/wallpaper.conf`, iar
  orbitele și etichetele sunt oprite implicit în modul fundal (`?orbits=0&labels=0`).

### 4. Curățenie

- Testele mele au lăsat o **fereastră-fantomă** în lista WM-ului (un id de fereastră rămas în lista WM-ului), plus un
  cadru Marco 960×540 nemapat din prima rulare buggy. Se curăță la logout sau cu
  `marco --replace &`. Lecție: testele nu trebuie să creeze ferestre gestionate de WM
  (folosește opacitate 0 sau `Gtk.OffscreenWindow`).

## 2026-09-19 — v1.0.2

- **Limita de cadre pentru fundal** (`?fps=30` / `--fps` / `FPS=` în `wallpaper.conf`):
  simularea continuă cu dt real, dar desenarea se rarefiază. Verificat comportamental:
  fără limită două capturi la 1 s distanță diferă în 2,09 % din pixeli, cu `fps=0.25`
  diferă în 0,00 % (nu se desenează). Motiv: fundalul consuma ~29 % dintr-un nucleu la
  60 fps non-stop.
- **Curățată fereastra-fantomă din Marco** (`0x4800019`, rămasă de la un test de-al meu
  care a creat o fereastră gestionată de WM): intrarea din `_NET_CLIENT_LIST` a fost
  eliminată cu `marco --replace &` — WM-ul își reconstruiește starea, aplicațiile rămân
  deschise, `wmctrl` funcționează din nou. Lecția e deja în secțiunea 4: testele nu
  creează ferestre gestionate de WM.

## 2026-09-19 — v1.0.3

- **Reparat: installerul suprascria configurația existentă.** Rulat fără
  `SOLAR_WALLPAPER_AREA`, scria `AREA=` (gol) în `wallpaper.conf`, adică „toate
  monitoarele" — iar fundalul a acoperit iconițele de pe monitorul 1. Acum valorile
  din mediu câștigă doar dacă sunt date; altfel se păstrează ce era în fișier; doar
  o instalare nouă folosește valorile implicite. Verificat în trei scenarii
  (instalare nouă / re-instalare fără variabile / re-instalare cu variabilă).
- `verify.sh` avertizează acum dacă `AREA` e gol (fundal peste tot desktopul).
- Lecție pentru viitor: installerul nu are voie să distrugă starea utilizatorului.

## 2026-09-19 — v1.0.4

- **Runtime-ul mutat în directorul de engine al daemonului**
  (`/usr/libexec/mate-screensaver`, cu `SOLAR_SYSTEM_WIDE=1`), pentru că
  `mate-screensaver` refuză orice `Exec` din `$HOME` (regula din sursă: `MANIFEST.md` §7b).
- `verify.sh` verifică acum și directorul din `Exec` (§3b), ca o temă instalată greșit să
  fie prinsă imediat.

## 2026-09-19 — v1.0.5

- **Cauza dovedită din sursa oficială** (`src/gs-theme-manager.c`): `find_command()`
  acceptă un `Exec` doar dacă directorul lui e în `known_engine_locations`
  (`SAVERDIR` = `/usr/libexec/mate-screensaver`, `/usr/libexec/xscreensaver`,
  `/usr/lib/xscreensaver`); altfel `gs_theme_info_get_exec()` întoarce NULL și jurnalul
  arată `Setting command for job: 'NULL'` → `No command set for job.`
- Copia sursei care dovedește regula: `_src/1.26-gs-theme-manager.c`.

## 2026-09-19 — v1.0.6

### Câte o copie pe fiecare monitor (screensaver care își deschide singur ferestrele)

- Gazda construiește **un panou per monitor** (fereastră + WebView, fiecare cu scena lui
  completă). Măsurat pe 2 × 1920×1080: `1920x1080+0+0` și `1920x1080+1920+0`, ambele
  `IsViewable`, ambele cu cerul nocturn (medie RGB (4,6,13), 32 % negri).

### De ce nu se vedea nimic (dovedit prin măsurători, nu presupus)

- O fereastră **gestionată de WM** nu poate fi așezată pe monitorul cerut și nici ținută
  deasupra desktopului: Marco a pus ambele panouri pe monitorul cu cursorul (ignorând
  `--area`) și fereastra „Desktop" a cajei — 3840×1080, adică tot desktopul virtual —
  a rămas deasupra lor. Dovada: `import -window <id>` arăta scena corectă în timp ce
  `import -window root` arăta desktopul, iar în ordinea X fereastra cajei era ultima.
- Soluția: **override-redirect** (`Gdk.Window.set_override_redirect(True)` înainte de
  mapare), exact ca la `xwinwrap`; poziția și stivuirea revin lui X. `--managed` păstrează
  comportamentul vechi pentru comparație. Verificat: ambele monitoare arată scena
  (std 9,6 / 32 % negri, identic pe ambele — două copii).
- Calea de fundal live nu se schimbă (un singur panou, strat `desktop`, gestionat):
  re-verificată după refactor — `load: finished`, conținut propriu std 10,5 / 31,7 %
  negri, animație 1,52 % din pixeli în 3 s.

### Orbite, etichete și ritm în screensaver

- `solar-saver.sh` cere explicit `--with-orbits --with-labels` (screensaver-ul nu are
  interfață) și limitează desenarea la 30 fps (`SOLAR_SAVER_FPS`), fiindcă N monitoare
  înseamnă N randare WebKit. Verificat la nivel de DOM cu URL-ul exact al screensaver-ului:
  `orbits:"true"`, `labels:"true"`, `body:"saver"`, zero erori; cu `orbits=0&labels=0`
  devin `false`.

### Reparat: scriptul putea muri înainte să pornească gazda

- `python3 … >>"$LOG" 2>&1 &` eșua (și scriptul ieșea fără să deseneze nimic) dacă
  `$HOME/.cache` nu era scrisibil — redirecționarea care nu poate fi deschisă face `sh`
  să nu execute comanda. Reproduit în sandbox („cannot create … Read-only file system"):
  fereastră niciuna. Acum se testează scrierea pentru fiecare candidat, apoi `/tmp`, apoi
  `/dev/null`, iar verificarea se repetă chiar înainte de lansare.

### Verificat după refactor

- Calea embedded (contractul `XSCREENSAVER_WINDOW`) re-testată cu codul nou, într-o
  fereastră părinte override-redirect de 640×400: potrivire de visual, `IsViewable`,
  conținut propriu 29,8 % negri, 4,59 % din pixeli schimbați în 2 s (animație vie).

## 2026-09-19 — v1.0.7

- **Screensaverul renunță la orbite, păstrează etichetele.** Lansatorul cere acum
  `--no-orbits --with-labels` (înainte `--with-orbits --with-labels`): liniile orbitale se
  citesc ca agitație pe un ecran mare, etichetele rămân utile ca să știi ce privești.
  Rămâne **câte o instanță pe fiecare monitor**, cu scena ei completă, la 30 fps.
- Verificat la nivel de DOM cu URL-ul exact folosit de screensaver:
  `?saver=1&speed=6.0&fps=30.0&orbits=0&labels=1` → `body:"saver"`, `labels:"true"`,
  `orbits:"false"`, zero erori. Și pe ecran, cu lansatorul real: două ferestre
  (`1920x1080+0+0`, `1920x1080+1920+0`, ambele `IsViewable`), ambele monitoare cu cerul
  nocturn (std 9,3 / 32,6 % negri, respectiv 14,7 / 31,3 %).
- Reamintire: `--no-*` se aplică înaintea `--with-*`, deci `--with-labels` câștigă chiar
  dacă cineva adaugă `--no-labels` la argumentele scriptului.

---

## Cum adaugi o versiune nouă

1. Modifică sursele în acest folder.
2. `./verify.sh` — trebuie să iasă tot PASS.
3. Actualizează `VERSION` și adaugă o secțiune aici (data + ce s-a schimbat + dovada).
4. Regenerează tabelul de checksum-uri din `MANIFEST.md`:
   `sha256sum solar-* install-*`
5. `./install-solar-screensaver.sh install` ca să actualizezi copiile instalate.
6. `git add -A && git commit -m "..."` (repo-ul git local din acest folder păstrează istoricul).
