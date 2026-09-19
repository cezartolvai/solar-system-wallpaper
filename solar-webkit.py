#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""solar-webkit.py — host `solar-system-3d.html` as a Linux screensaver or a
live desktop wallpaper.

It is a thin GTK3 + WebKit2GTK shell around the single-file simulation: no
browser, no profile, no chrome. Three window roles:

  --saver          full-screen window on top of everything, used as a
                   mate-screensaver / xscreensaver "theme" (the screensaver
                   kills this process the moment you touch the keyboard)
  --wallpaper      window pinned below the desktop icons, mouse clicks pass
                   straight through it, so the desktop stays usable
  --wid ID         embed into an existing X window (xwinwrap and friends)

Extras:
  --monitor N      use one monitor instead of all of them (0 = first)
  --all            span the whole desktop (default)
  --url PATH|URL   default: solar-system-3d.html next to this script
  --selftest       render off-screen, save a PNG and print diagnostics,
                   without ever showing a window (used to verify the setup)
  --out FILE       PNG path for --selftest
  --debug          forward page console messages / JS errors to stderr

Requires: python3-gi, gir1.2-gtk-3.0, gir1.2-webkit2-4.0 (or 4.1), pycairo.
Tested against WebKitGTK 2.52 on X11; X11 is required for --wid/--wallpaper.
"""

import argparse
import ctypes
import ctypes.util
import os
import re
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib, Gio  # noqa: E402

WEBKIT_VERSION = None
for _v in ("4.1", "4.0"):
    try:
        gi.require_version("WebKit2", _v)
        from gi.repository import WebKit2  # noqa: E402
        WEBKIT_VERSION = _v
        break
    except (ValueError, ImportError):
        continue
if WEBKIT_VERSION is None:
    sys.stderr.write("solar-webkit: WebKit2GTK not found (install gir1.2-webkit2-4.0 or -4.1)\n")
    sys.exit(2)

def visual_depth(gdk_window):
    """Depth of a GdkWindow.  GDK 3 does not introspect gdk_window_get_depth in
    this binding, so it is derived from the window's visual."""
    try:
        visual = gdk_window.get_visual()
        return visual.get_best_depth() if visual is not None else "?"
    except Exception:
        return "?"


class XErrorEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("display", ctypes.c_void_p),
                ("resourceid", ctypes.c_ulong), ("serial", ctypes.c_ulong),
                ("error_code", ctypes.c_ubyte), ("request_code", ctypes.c_ubyte),
                ("minor_code", ctypes.c_ubyte)]


X_ERROR_NAMES = {1: "BadRequest", 2: "BadValue", 3: "BadWindow", 4: "BadPixmap",
                 5: "BadAtom", 6: "BadCursor", 7: "BadFont", 8: "BadMatch",
                 9: "BadDrawable", 10: "BadAccess", 11: "BadAlloc",
                 12: "BadColormap", 13: "BadGC", 14: "BadIDChoice", 15: "BadName",
                 16: "BadLength", 17: "BadImplementation"}


class X11(object):
    """Raw X11 calls: reparenting into a foreign window, reading its geometry,
    and an error handler that logs instead of killing the process (Xlib's
    default handler calls exit() on any asynchronous error, which would make a
    failed reparent look exactly like "the screensaver shows nothing")."""

    def __init__(self):
        self.available = False
        self.lib = None
        self.dpy = None
        self.errors = []
        try:
            lib = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
            lib.XOpenDisplay.restype = ctypes.c_void_p
            lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
            lib.XReparentWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                            ctypes.c_ulong, ctypes.c_int, ctypes.c_int]
            lib.XMoveResizeWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                              ctypes.c_int, ctypes.c_int,
                                              ctypes.c_uint, ctypes.c_uint]
            lib.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
            lib.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
            lib.XGetGeometry.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                         ctypes.POINTER(ctypes.c_ulong),
                                         ctypes.POINTER(ctypes.c_int),
                                         ctypes.POINTER(ctypes.c_int),
                                         ctypes.POINTER(ctypes.c_uint),
                                         ctypes.POINTER(ctypes.c_uint),
                                         ctypes.POINTER(ctypes.c_uint),
                                         ctypes.POINTER(ctypes.c_uint)]
            lib.XGetGeometry.restype = ctypes.c_int
            handler_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p,
                                            ctypes.POINTER(XErrorEvent))
            self._handler_ref = handler_type(self._on_error)   # keep it alive
            lib.XSetErrorHandler.argtypes = [handler_type]
            lib.XSetErrorHandler.restype = ctypes.c_void_p
            lib.XSetErrorHandler(self._handler_ref)
            dpy = lib.XOpenDisplay(None)
            if not dpy:
                return
            self.lib, self.dpy, self.available = lib, dpy, True
        except Exception:
            self.available = False

    def _on_error(self, _dpy, event):
        try:
            ev = event.contents
            self.errors.append("%s (code %d) on request %d, resource 0x%x"
                               % (X_ERROR_NAMES.get(ev.error_code, "XError"),
                                  ev.error_code, ev.request_code, ev.resourceid))
        except Exception:
            self.errors.append("XError")
        return 0

    def geometry(self, window):
        """(x, y, width, height, depth) of any window, or None."""
        root = ctypes.c_ulong(); x = ctypes.c_int(); y = ctypes.c_int()
        w = ctypes.c_uint(); h = ctypes.c_uint(); bw = ctypes.c_uint(); d = ctypes.c_uint()
        ok = self.lib.XGetGeometry(self.dpy, window, ctypes.byref(root),
                                   ctypes.byref(x), ctypes.byref(y),
                                   ctypes.byref(w), ctypes.byref(h),
                                   ctypes.byref(bw), ctypes.byref(d))
        if not ok:
            return None
        return (x.value, y.value, w.value, h.value, d.value)

    def reparent(self, window, parent):
        self.lib.XReparentWindow(self.dpy, window, parent, 0, 0)
        self.lib.XSync(self.dpy, 0)

    def move_resize(self, window, x, y, w, h):
        self.lib.XMoveResizeWindow(self.dpy, window, x, y, w, h)
        self.lib.XSync(self.dpy, 0)

    def map(self, window):
        self.lib.XMapWindow(self.dpy, window)
        self.lib.XSync(self.dpy, 0)


HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PAGE = os.path.join(HERE, "solar-system-3d.html")


# --------------------------------------------------------------------------
# geometry helpers
# --------------------------------------------------------------------------
def parse_area(text):
    """Parse a X11-style geometry string "WxH+X+Y" (offsets optional)."""
    m = re.match(r"^\s*(\d+)x(\d+)(?:\s*([+-]\d+)\s*([+-]\d+))?\s*$", text or "")
    if not m:
        raise ValueError("expected WxH+X+Y, e.g. 1920x1080+1920+0 (got %r)" % text)
    w, h = int(m.group(1)), int(m.group(2))
    x = int(m.group(3)) if m.group(3) else 0
    y = int(m.group(4)) if m.group(4) else 0
    return (x, y, w, h)


def monitor_geometry(display, monitor_index, area=None):
    """Return (x, y, w, h): an explicit --area, one monitor, or all of them."""
    if area is not None:
        return area
    n = display.get_n_monitors()
    if n == 0:
        return (0, 0, 1920, 1080)                       # headless fallback
    if monitor_index is not None:
        idx = max(0, min(monitor_index, n - 1))
        g = display.get_monitor(idx).get_geometry()
        return (g.x, g.y, g.width, g.height)
    x0 = y0 = 10 ** 9
    x1 = y1 = -10 ** 9
    for i in range(n):
        g = display.get_monitor(i).get_geometry()
        x0, y0 = min(x0, g.x), min(y0, g.y)
        x1, y1 = max(x1, g.x + g.width), max(y1, g.y + g.height)
    return (x0, y0, max(1, x1 - x0), max(1, y1 - y0))


def page_uri(path, query):
    if path.startswith(("http://", "https://", "file://")):
        return path + query
    return Gio.File.new_for_path(os.path.abspath(path)).get_uri() + query


# --------------------------------------------------------------------------
# the host
# --------------------------------------------------------------------------
class SolarHost(object):
    def __init__(self, args):
        self.args = args
        self.display = Gdk.Display.get_default()
        self.plug = None
        self.embedded = False
        self._parent_xid = 0
        self._parent_gdk = None
        self._xlib_handle = None

        self.webview = WebKit2.WebView()
        # When we draw inside somebody else's window (screensaver themes) the
        # accelerated (GL) compositing path is what makes WebKit insist on an
        # RGBA visual, which then conflicts with a 24-bit host window.  Plain
        # software rendering is a few percent slower and always works.
        self._tune_webview(force_accel=bool(args.hw_accel))

        query = args.query or ""
        if args.saver is not None:
            query = "?saver=" + args.saver
            if args.tour_off:
                query += "&tour=0"
            if args.speed is not None:
                query += "&speed=%s" % args.speed
        # no-* switches are forwarded to the page (it has no UI in these modes)
        for flag, name in (("no_orbits", "orbits"), ("no_labels", "labels"),
                           ("no_stars", "stars"), ("no_belt", "belt")):
            if getattr(args, flag, False):
                query += ("&" if "?" in query else "?") + name + "=0"
        # explicit positives win over a --no-* flag
        for flag, name in (("with_orbits", "orbits"), ("with_labels", "labels"),
                           ("with_stars", "stars"), ("with_belt", "belt")):
            if getattr(args, flag, False):
                query += ("&" if "?" in query else "?") + name + "=1"
        self.uri = page_uri(args.url, query)

        # mate-screensaver / xscreensaver do not pass arguments: they export
        # XSCREENSAVER_WINDOW with the id of the surface the theme must draw
        # into. Ignoring it makes the animation end up behind the daemon's own
        # (opaque) window, i.e. invisible.
        if not args.wid:
            env_wid = os.environ.get("XSCREENSAVER_WINDOW", "").strip()
            if env_wid:
                args.wid = env_wid
                args.mode = "saver"
                if args.debug:
                    sys.stderr.write("using XSCREENSAVER_WINDOW=%s\n" % env_wid)

        if args.wid:
            self._build_plug(args.wid)
        else:
            self._build_window(args)

    # -- setup -------------------------------------------------------------
    def _tune_webview(self, force_accel=False):
        s = self.webview.get_settings()
        for prop, value in (
            ("enable_javascript", True),
            ("enable_webgl", False),            # the page is pure Canvas 2D
            ("enable_media", False),
            ("enable_plugins", False),
            ("enable_page_cache", False),
            ("enable_developer_extras", bool(self.args.debug)),
            ("enable_write_console_messages_to_stdout", bool(self.args.debug)),
            ("allow_file_access_from_file_urls", True),
            ("allow_universal_access_from_file_urls", False),
            ("hardware_acceleration_policy",
             WebKit2.HardwareAccelerationPolicy.ALWAYS if force_accel
             else WebKit2.HardwareAccelerationPolicy.NEVER),
        ):
            if s.find_property(prop.replace("_", "-")) is not None:
                try:
                    s.set_property(prop.replace("_", "-"), value)
                except Exception:
                    pass
        # a screensaver must not offer a context menu
        self.webview.connect("context-menu", lambda *_: True)
        if self.args.debug:
            # WebKitGTK dropped the ::console-message signal in 2.40, so page
            # errors are routed to the console instead and picked up by the
            # enable_write_console_messages_to_stdout setting above.
            hook = ("window.addEventListener('error',function(e){"
                    "console.error('[page error] '+e.message+' @'+e.lineno);});"
                    "window.addEventListener('unhandledrejection',function(){"
                    "console.error('[page rejection]');});")
            self.webview.get_user_content_manager().add_script(
                WebKit2.UserScript.new(hook, WebKit2.UserContentInjectedFrames.TOP_FRAME,
                                       WebKit2.UserScriptInjectionTime.START, None, None))
        self.webview.connect("load-failed", self._on_load_failed)
        self.webview.connect("load-changed", self._on_load_changed)

    def _on_load_failed(self, _view, _event, failing, error):
        sys.stderr.write("solar-webkit: load failed: %s (%s)\n" % (failing, error))
        return False

    def _on_load_changed(self, _view, event):
        if self.args.debug:
            names = {WebKit2.LoadEvent.STARTED: "started",
                     WebKit2.LoadEvent.REDIRECTED: "redirected",
                     WebKit2.LoadEvent.COMMITTED: "committed",
                     WebKit2.LoadEvent.FINISHED: "finished"}
            sys.stderr.write("load: %s %s\n" % (names.get(event, event), self.uri))
        return False

    @staticmethod
    def _apply_stack(win, stack):
        if stack == "normal":
            # plain layer: above the daemon's screensaver window (mapped
            # earlier) but below anything created afterwards, such as the
            # MATE unlock dialog
            win.set_type_hint(Gdk.WindowTypeHint.NORMAL)
        elif stack == "above":
            win.set_type_hint(Gdk.WindowTypeHint.NORMAL)
            win.set_keep_above(True)
        elif stack == "desktop":
            win.set_type_hint(Gdk.WindowTypeHint.DESKTOP)
            win.set_keep_below(False)
        else:                                   # "below" (screensaver default)
            win.set_type_hint(Gdk.WindowTypeHint.NORMAL)
            win.set_keep_below(True)

    def _build_window(self, args):
        win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
        win.set_decorated(False)
        win.set_resizable(False)
        win.set_skip_taskbar_hint(True)
        win.set_skip_pager_hint(True)
        win.set_title("Solar System")
        win.add(self.webview)

        # Layer order on EWMH desktops, bottom to top:
        #     desktop < below < normal < above < dock
        #  * saver   -> "below": covers the desktop and its icons, but every
        #               normal window (the MATE lock dialog above all) stays on
        #               top. This is the equivalent of an xscreensaver hack
        #               drawing on the root window, and it is what keeps the
        #               password prompt reachable when locking is enabled.
        #  * wallpaper -> "desktop": caja paints the icons in a desktop-layer
        #               window, so we join that layer and let the file manager
        #               stay on top of us.
        self._apply_stack(win, args.stack)
        if args.mode == "wallpaper":
            win.set_accept_focus(False)
            win.set_focus_on_map(False)

        self.window = win
        self._apply_geometry()

        if self.args.dry_run:
            x, y, w, h = monitor_geometry(self.display, self.args.monitor, self.args.area_box)
            sys.stdout.write("dry-run : role=%s geometry=%dx%d+%d+%d monitors=%d url=%s\n"
                             % (args.mode, w, h, x, y, self.display.get_n_monitors(), self.uri))
            return
        win.connect("realize", self._on_realize)
        win.connect("map-event", self._on_map)
        win.connect("delete-event", lambda *_: (Gtk.main_quit(), True)[1])
        screen = win.get_screen()
        screen.connect("monitors-changed", lambda *_: self._apply_geometry())
        screen.connect("size-changed", lambda *_: self._apply_geometry())
        win.show_all()

    # ------------------------------------------------------------------
    # embedding into a window owned by somebody else
    # ------------------------------------------------------------------
    # mate-screensaver and xscreensaver do not pass arguments: they export
    # XSCREENSAVER_WINDOW with the id of the surface the theme must draw into.
    # Gtk.Plug is NOT usable for this: it speaks the XEMBED protocol and only
    # maps itself when a GtkSocket handshakes with it, so with a plain foreign
    # window it stays unmapped (nothing appears).  The contract these themes
    # follow is the plain X11 one used by xwinwrap: create a window and
    # reparent it into the given id, then map and size it to the parent.
    def _xlib(self):
        if self._xlib_handle is None:
            self._xlib_handle = X11()
        return self._xlib_handle

    def _build_plug(self, xid):
        try:
            xid_int = int(str(xid), 0)          # accepts 12345 and 0x3039
        except (TypeError, ValueError):
            xid_int = 0
        if xid_int and self._is_root_window(xid_int):
            # xscreensaver-style "draw on the root window": there is no host
            # window to live inside, so take the whole screen ourselves.
            sys.stderr.write("embed: XSCREENSAVER_WINDOW is the root window; "
                             "using a full-screen window instead\n")
            self.args.wid = None
            self.args.mode = "saver"
            self.args.stack = self.args.stack or "normal"
            self._build_window(self.args)
            return
        if xid_int and self._xlib().available:
            self._parent_xid = xid_int
            # a real toplevel is still needed: GTK must have a window to draw
            # into, we simply reparent it before the WM ever sees it.
            win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
            win.set_decorated(False)
            win.set_skip_taskbar_hint(True)
            win.set_skip_pager_hint(True)
            win.set_title("Solar System")
            # Reparenting requires our window to have the SAME visual as the
            # host: a mismatch makes XReparentWindow fail with BadMatch, and
            # Xlib's default error handler then terminates the process before
            # anything is drawn.  WebKit can ask for an RGBA visual of its own
            # when hardware acceleration is on, so the target's visual wins.
            self._match_visual(win, xid_int)
            self.webview.set_hexpand(True)
            self.webview.set_vexpand(True)
            win.add(self.webview)
            self.window = win
            self.embedded = True
            win.connect("realize", self._on_embed_realize)
            win.connect("delete-event", lambda *_: (Gtk.main_quit(), True)[1])
            win.show_all()
            GLib.timeout_add(500, self._sync_embed_size)
            return
        if xid_int:
            sys.stderr.write("solar-webkit: libX11 unavailable, cannot embed into %s\n" % xid)
        self.args.wid = None
        self._build_window(self.args)           # fall back to our own window

    @staticmethod
    def _probe_window(xid_int):
        """(depth, visual_id, width, height) of a window, read through xwininfo
        because GDK reports the screen's default visual for foreign windows."""
        try:
            out = subprocess.run(["xwininfo", "-id", hex(xid_int)],
                                 capture_output=True, text=True, timeout=5).stdout
        except Exception:
            return None
        depth = visual = w = h = None
        state = "?"
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("Depth:"):
                depth = int(line.split(":")[1].strip())
            elif line.startswith("Visual:"):
                visual = int(line.split(":")[1].strip(), 16)
            elif line.startswith("Width:"):
                w = int(line.split(":")[1].strip())
            elif line.startswith("Height:"):
                h = int(line.split(":")[1].strip())
            elif line.startswith("Map State:"):
                state = line.split(":")[1].strip()
        if depth is None:
            return None
        return (depth, visual, w, h, state)

    def _match_visual(self, win, xid_int):
        """Give our window the same visual (depth) as the host window.

        XReparentWindow between windows of different depth fails with BadMatch;
        pairing the depths up front is what makes the embed reliable.  The
        depth is read with XGetGeometry because GDK's own accessor returns the
        screen's default visual for foreign windows."""
        probe = self._probe_window(xid_int)
        if probe is None:
            sys.stderr.write("embed: target unreadable, keeping our default visual\n")
            return
        depth, visual_id, hw, hh, hstate = probe
        sys.stderr.write("embed: host window depth=%s visual=%s %sx%s map=%s\n"
                         % (depth, hex(visual_id) if visual_id else "?", hw, hh, hstate))
        if hstate != "IsViewable":
            sys.stderr.write("embed: WARNING host window is not viewable yet; "
                             "the animation stays invisible until it is mapped\n")
        try:
            from gi.repository import GdkX11
            screen = Gdk.Screen.get_default()
            chosen = None
            if visual_id:
                chosen = GdkX11.X11Screen.lookup_visual(screen, visual_id)
            if chosen is None:
                # fall back to any visual of the same depth
                for vis in screen.list_visuals():
                    try:
                        depth_of = GdkX11.X11Visual.get_xvisual(vis)
                        if depth_of is not None:
                            chosen = vis
                            break
                    except Exception:
                        continue
            if chosen is None:
                sys.stderr.write("embed: no GdkVisual found, keeping our default\n")
                return
            win.set_visual(chosen)
            if depth > 24:
                win.set_app_paintable(True)
            sys.stderr.write("embed: our window will use visual %s (depth %s), palpable=%s\n"
                             % (hex(visual_id) if visual_id else "?", depth, depth > 24))
        except Exception as exc:
            sys.stderr.write("embed: visual matching failed (%s)\n" % exc)

    def _target_info(self):
        """Human-readable description of the window we were told to draw in."""
        try:
            from gi.repository import GdkX11
            w = self._parent_gdk
            if w is None:
                w = GdkX11.X11Window.foreign_new_for_display(
                    Gdk.Display.get_default(), self._parent_xid)
                self._parent_gdk = w
            if w is None:
                return "target %s: window no longer exists" % hex(self._parent_xid)
            g = w.get_geometry()
            probe = self._probe_window(self._parent_xid)
            if probe is not None:
                return "target %s: depth=%s visual=%s %sx%s map=%s" % (
                    hex(self._parent_xid), probe[0],
                    hex(probe[1]) if probe[1] else "?", probe[2] or 0, probe[3] or 0, probe[4])
            return "target %s: %dx%d+%d+%d" % (
                hex(self._parent_xid), g.width, g.height, g.x, g.y)
        except Exception as exc:
            return "target %s: unreadable (%s)" % (hex(self._parent_xid), exc)

    def _is_root_window(self, xid):
        try:
            root = Gdk.get_default_root_window()
            return root is not None and root.get_xid() == xid
        except Exception:
            return False

    def _on_embed_realize(self, win):
        """Runs before the window is mapped: reparent straight away."""
        gw = win.get_window()
        if gw is None:
            return False
        x = self._xlib()
        sys.stderr.write("embed: %s\n" % self._target_info())
        x.reparent(gw.get_xid(), self._parent_xid)
        self._sync_embed_size()
        x.map(gw.get_xid())
        try:
            info = self._probe_window(gw.get_xid())
            if info:
                sys.stderr.write("embed: our window %s depth=%s %sx%s map=%s\n"
                                 % (hex(gw.get_xid()), info[0], info[2], info[3], info[4]))
            else:
                sys.stderr.write("embed: our window %s (unreadable)\n" % hex(gw.get_xid()))
        except Exception as exc:
            sys.stderr.write("embed: cannot describe our window (%s)\n" % exc)
        if x.errors:
            sys.stderr.write("embed: X errors during reparent: %s\n" % "; ".join(x.errors))
        sys.stderr.flush()
        return False

    def _sync_embed_size(self):
        """Mirror the host window's size onto our reparented window (nobody
        else manages it), the same way an xscreensaver hack sizes its child."""
        if not self.embedded:
            return False
        try:
            parent = self._parent_gdk
            if parent is None:
                from gi.repository import GdkX11
                parent = GdkX11.X11Window.foreign_new_for_display(
                    Gdk.Display.get_default(), self._parent_xid)
                self._parent_gdk = parent
            if parent is not None:
                g = parent.get_geometry()
                if g.width > 1 and g.height > 1:
                    gw = self.window.get_window()
                    if gw is not None:
                        cur = gw.get_geometry()
                        if cur.width != g.width or cur.height != g.height:
                            self._xlib().move_resize(gw.get_xid(), 0, 0, g.width, g.height)
                            self.window.resize(g.width, g.height)
                            if self.args.debug:
                                sys.stderr.write("embedded size -> %dx%d\n" % (g.width, g.height))
        except Exception as exc:
            if self.args.debug:
                sys.stderr.write("embed size sync failed: %s\n" % exc)
            return False
        return True

    def _apply_geometry(self):
        if self.embedded:
            return
        """Size and place the window on the selected monitor(s).

        NOTE: `Gtk.Window.resize()` is ignored for a non-resizable window
        before it is mapped — the window then comes up at GTK's default size
        (a few hundred pixels) instead of covering the screen. The reliable
        way is `set_default_size()`, which becomes the size hint used at map
        time, plus a direct `move_resize()` on the Gdk window once it exists.
        """
        x, y, w, h = monitor_geometry(self.display, self.args.monitor, self.args.area_box)
        self.window.set_default_size(w, h)
        self.window.move(x, y)
        gw = self.window.get_window()
        if gw is not None:                     # already realised: force it
            gw.move_resize(x, y, w, h)
        if self.args.debug:
            sys.stderr.write("geometry: target %dx%d+%d+%d -> window %s\n"
                             % (w, h, x, y,
                                self.window.get_window().get_geometry()
                                if self.window.get_window() else "(not realised)"))

    def _on_map(self, win, _event):
        # First pass as soon as the window exists, then one delayed repeat:
        # window managers with pointer-based placement (Marco/Metacity) may
        # honour their own monitor for the initial map but do obey an explicit
        # _NET_MOVERESIZE_WINDOW once the window is fully placed.
        self._apply_geometry()
        GLib.timeout_add(600, self._reapply_geometry)
        return False

    def _reapply_geometry(self):
        self._apply_geometry()
        return False

    def _on_realize(self, win):
        gdkwin = win.get_window()
        if gdkwin is None:
            return
        if self.args.mode == "wallpaper":
            # empty input region => every click lands on the desktop/icons
            try:
                gdkwin.set_pass_through(True)
            except Exception:
                pass
            try:
                win.stick()
            except Exception:
                pass
        # hide the pointer even before the page's CSS takes over
        try:
            blank = Gdk.Cursor.new_for_display(Gdk.Display.get_default(),
                                               Gdk.CursorType.BLANK_CURSOR)
            gdkwin.set_cursor(blank)
        except Exception:
            pass

    # -- run ---------------------------------------------------------------
    def run(self):
        if self.args.delay:
            GLib.timeout_add(int(self.args.delay * 1000), self._load)
        else:
            self._load()
        Gtk.main()

    def _load(self):
        self.webview.load_uri(self.uri)
        return False


# --------------------------------------------------------------------------
# off-screen verification: renders the real page, shows nothing
# --------------------------------------------------------------------------
def selftest(args):
    """Render the real page off-screen (no window is ever shown), measure the
    frame rate WebKit achieves, sample the pixels and print a verdict."""
    if not Gtk.init_check([])[0]:
        sys.stderr.write("selftest: no X display\n")
        return 2
    out = args.out or os.path.join(HERE, "_solar-selftest.png")
    uri = page_uri(args.url, "?saver=drift" if args.query is None else args.query)
    errors = []

    win = Gtk.OffscreenWindow()
    win.set_size_request(1920, 1080)
    view = WebKit2.WebView()
    win.add(view)
    # capture any page error regardless of engine quirks
    hook = ("window.__errs=[];"
            "window.addEventListener('error',function(e){window.__errs.push('error: '+e.message+' @'+e.lineno);});"
            "window.addEventListener('unhandledrejection',function(){window.__errs.push('rejection');});")
    view.get_user_content_manager().add_script(
        WebKit2.UserScript.new(hook, WebKit2.UserContentInjectedFrames.TOP_FRAME,
                               WebKit2.UserScriptInjectionTime.START, None, None))
    win.show_all()

    def js(script, label):
        def done(v, res, _u):
            try:
                print("selftest: %-9s %s" % (label, v.evaluate_javascript_finish(res).to_string()))
            except Exception as exc:
                print("selftest: %-9s <failed: %s>" % (label, exc))
            return False
        view.evaluate_javascript(script, -1, None, None, None, done, None)

    def on_load(_v, event):
        if event == WebKit2.LoadEvent.FINISHED:
            GLib.timeout_add(1200, start_probe)
        return False

    def on_fail(_v, _e, failing, err):
        errors.append("%s: %s" % (failing, err))
        return False

    def start_probe():
        js("window.__p={n:0,t0:performance.now(),ms:0};"
           "(function f(){window.__p.n++;window.__p.ms=performance.now()-window.__p.t0;"
           "requestAnimationFrame(f);})(); 'installed'", "probe")
        GLib.timeout_add(3000, read_probe)
        return False

    def read_probe():
        js("JSON.stringify({frames:window.__p.n, elapsed:Math.round(window.__p.ms),"
           " fps:+(window.__p.n/(window.__p.ms/1000)).toFixed(1),"
           " controls:getComputedStyle(document.getElementById('controls')).display,"
           " leftCol:getComputedStyle(document.getElementById('leftCol')).display,"
           " cursor:getComputedStyle(document.getElementById('scene')).cursor,"
           " canvas:document.getElementById('scene').width+'x'+document.getElementById('scene').height,"
           " body:document.body.className,"
           " orbits:document.getElementById('btnOrbits').getAttribute('aria-pressed'),"
           " labels:document.getElementById('btnLabels').getAttribute('aria-pressed'),"
           " stars:document.getElementById('btnStars').getAttribute('aria-pressed'),"
           " belt:document.getElementById('btnBelt').getAttribute('aria-pressed'),"
           " errs:(window.__errs||[]).slice(0,5)})", "dom")
        GLib.timeout_add(700, do_snapshot)
        return False

    def do_snapshot():
        def finish(v, res):
            try:
                surf = v.get_snapshot_finish(res)
            except Exception as exc:
                print("selftest: snapshot failed: %s" % exc)
                surf = None
            if surf is not None:
                surf.write_to_png(out)
                report(surf)
            else:
                print("selftest: verdict   SNAPSHOT FAILED")
            if errors:
                print("selftest: errors    %s" % errors)
            Gtk.main_quit()
            return False
        view.get_snapshot(WebKit2.SnapshotRegion.FULL_DOCUMENT,
                          WebKit2.SnapshotOptions.NONE, None, finish)
        return False

    def report(surf):
        w, h = surf.get_width(), surf.get_height()
        data, stride = surf.get_data(), surf.get_stride()
        lit = dark = total = 0
        for y in range(0, h, max(1, h // 120)):
            row = y * stride
            for x in range(0, w, max(1, w // 200)):
                i = row + x * 4
                b, g, r = data[i], data[i + 1], data[i + 2]
                total += 1
                if r + g + b > 150:
                    lit += 1
                elif r + g + b < 30:
                    dark += 1
        print("selftest: page      %s" % uri)
        print("selftest: webkit    %d.%d" % (WebKit2.get_major_version(), WebKit2.get_minor_version()))
        print("selftest: snapshot  %dx%d -> %s" % (w, h, out))
        print("selftest: pixels    %d samples, lit=%d (%.2f%%), near-black=%.2f%%"
              % (total, lit, 100.0 * lit / total, 100.0 * dark / total))
        print("selftest: verdict   %s" % ("RENDERING OK" if lit > total * 0.002 else "BLANK?"))

    view.connect("load-changed", on_load)
    view.connect("load-failed", on_fail)
    view.load_uri(uri)
    GLib.timeout_add(25000, lambda: (sys.stderr.write("selftest: timeout\n"), Gtk.main_quit(), False)[2])
    Gtk.main()
    return 0


def geometry_check(args):
    """Map the real window with zero opacity and report the geometry the page
    actually gets. Purely diagnostic; requires a compositing manager."""
    if not Gtk.init_check([])[0]:
        sys.stderr.write("geometry-check: no X display\n")
        return 2
    if not Gdk.Screen.get_default().is_composited():
        sys.stderr.write("geometry-check: no compositor, refusing (the test "
                         "window would be visible)\n")
        return 2
    args.dry_run = False
    host = SolarHost(args)
    win = host.window
    win.set_opacity(0.0)

    def measure():
        gw = win.get_window()
        g = gw.get_geometry() if gw else None
        def done(v, res, _u):
            try:
                seen = v.evaluate_javascript_finish(res).to_string()
            except Exception as exc:
                seen = "<%s>" % exc
            print("geometry-check: mode=%-9s stack=%-7s monitor=%-4s -> window %s | page sees %s"
                  % (args.mode, args.stack,
                     args.area or ("all" if args.monitor is None else args.monitor), g, seen))
            Gtk.main_quit()
            return False
        host.webview.evaluate_javascript(
            "window.innerWidth+'x'+window.innerHeight+' dpr='+devicePixelRatio",
            -1, None, None, None, done, None)
        return False

    GLib.timeout_add(2500, measure)
    GLib.timeout_add(15000, lambda: (sys.stderr.write("geometry-check: timeout\n"),
                                     Gtk.main_quit(), False)[2])
    Gtk.main()
    return 0


def main():
    p = argparse.ArgumentParser(description="Solar System screensaver / wallpaper host")
    p.add_argument("--mode", choices=("saver", "wallpaper"), default="saver")
    p.add_argument("--saver", nargs="?", const="1", default=None,
                   help="enable ?saver=<value> (default 1 when the flag is given bare)")
    p.add_argument("--tour-off", action="store_true", help="no automatic body tour")
    p.add_argument("--speed", type=float, default=None, help="starting days/second")
    p.add_argument("--monitor", type=int, default=None, help="single monitor index")
    p.add_argument("--area", default=None, metavar="WxH+X+Y",
                   help="place the window in an explicit rectangle instead of a "
                        "whole monitor; useful to keep a region (for example where "
                        "the desktop icons live) free")
    p.add_argument("--stack", choices=("desktop", "below", "normal", "above"), default=None,
                   help="window layer: screensaver defaults to below (keeps the "
                        "lock dialog visible), wallpaper to desktop (keeps the "
                        "desktop icons visible)")
    p.add_argument("--wid", default=None, help="embed into this X window id")
    p.add_argument("--url", default=DEFAULT_PAGE)
    p.add_argument("--query", default=None,
                   help="query string for the page; pass \"\" for the normal interactive UI")
    p.add_argument("--delay", type=float, default=0.0, help="wait before loading (s)")
    p.add_argument("--debug", action="store_true")
    for _flag, _help in (("--no-orbits", "hide orbital paths"),
                         ("--no-labels", "hide body name labels"),
                         ("--no-stars", "hide the star field"),
                         ("--no-belt", "hide the asteroid belt")):
        p.add_argument(_flag, action="store_true", help=_help)
    for _flag, _help in (("--with-orbits", "force orbital paths on"),
                         ("--with-labels", "force labels on"),
                         ("--with-stars", "force the star field on"),
                         ("--with-belt", "force the asteroid belt on")):
        p.add_argument(_flag, action="store_true", help=_help)
    p.add_argument("--hw-accel", action="store_true",
                   help="force GPU compositing even when embedding (default: "
                        "software rendering while embedded)")
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--geometry-check", action="store_true",
                   help="map the real window invisibly and print its geometry")
    p.add_argument("--dry-run", action="store_true",
                   help="build the window, print its geometry, show nothing")
    p.add_argument("--out", default=None)
    # convenience aliases so the script can also be dropped into an
    # xscreensaver-style launcher that passes --root / -window-id
    p.add_argument("--root", action="store_true", help="accepted and ignored")
    p.add_argument("-window-id", dest="window_id_compat", default=None,
                   help="accepted for xscreensaver compatibility")
    args = p.parse_args()

    if args.window_id_compat and not args.wid:
        args.wid = args.window_id_compat
    if args.wid:
        args.mode = "wallpaper"
    if args.saver is None and args.mode == "saver":
        args.saver = "1"
    if args.area:
        try:
            args.area_box = parse_area(args.area)
        except ValueError as exc:
            sys.stderr.write("solar-webkit: bad --area: %s\n" % exc)
            return 2
    else:
        args.area_box = None

    if args.stack is None:
        if args.mode == "wallpaper":
            # desktop layer: caja paints the icons there, so it stays on top
            args.stack = "desktop"
        elif args.monitor is not None or args.area_box is not None:
            # Marco/Metacity only honours an explicit position for
            # desktop-layer windows: a "below" window is placed on whichever
            # monitor holds the pointer. --monitor therefore implies the
            # desktop layer; the lock dialog (normal layer) still stays above.
            args.stack = "desktop"
        else:
            args.stack = "below"

    if args.selftest:
        return selftest(args)
    if args.geometry_check:
        return geometry_check(args)

    if not Gtk.init_check([])[0]:
        sys.stderr.write("solar-webkit: cannot open the X display\n")
        return 2
    if not os.path.exists(args.url) and not args.url.startswith(("http", "file")):
        sys.stderr.write("solar-webkit: page not found: %s\n" % args.url)
        return 2

    host = SolarHost(args)
    if args.dry_run:
        return 0
    try:
        host.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
