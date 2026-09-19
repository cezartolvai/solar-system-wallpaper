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

---

## Cum adaugi o versiune nouă

1. Modifică sursele în acest folder.
2. `./verify.sh` — trebuie să iasă tot PASS.
3. Actualizează `VERSION` și adaugă o secțiune aici (data + ce s-a schimbat + dovada).
4. Regenerează tabelul de checksum-uri din `MANIFEST.md`:
   `sha256sum solar-* install-*`
5. `./install-solar-screensaver.sh install` ca să actualizezi copiile instalate.
6. `git add -A && git commit -m "..."` (repo-ul git local din acest folder păstrează istoricul).
