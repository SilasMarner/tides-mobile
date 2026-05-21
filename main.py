#!/usr/bin/env python3
"""Tides — Android NOAA tide dashboard (Kivy)"""

import json
import math
import os
import ssl
import threading
import urllib.request
from datetime import datetime, date, timedelta

_APP_VERSION = "1.0"
_RELEASES_URL = "https://github.com/SilasMarner/tides-mobile/releases"
_RELEASES_API = "https://api.github.com/repos/SilasMarner/tides-mobile/releases/latest"

from kivy.app import App
from kivy.clock import Clock
from kivy.core.text import Label as CoreLabel
from kivy.core.window import Window
from kivy.graphics import Color, Ellipse, Line, Mesh, Rectangle, RoundedRectangle
from kivy.metrics import dp, sp
from kivy.uix.behaviors import ButtonBehavior
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.gridlayout import GridLayout
from kivy.uix.label import Label
from kivy.uix.scrollview import ScrollView
from kivy.uix.popup import Popup
from kivy.uix.screenmanager import Screen, ScreenManager, SlideTransition
from kivy.uix.textinput import TextInput
from kivy.uix.widget import Widget

import tides_data as td

# ── Palette ───────────────────────────────────────────────────────────────────
C_BG      = (0.05, 0.08, 0.14, 1)
C_PANEL   = (0.09, 0.13, 0.22, 1)
C_CARD    = (0.10, 0.15, 0.26, 1)
C_HEADER  = (0.11, 0.19, 0.36, 1)
C_TEXT    = (0.93, 0.95, 0.99, 1)
C_DIM     = (0.52, 0.63, 0.78, 1)
C_CYAN    = (0.22, 0.74, 1.00, 1)
C_YELLOW  = (1.00, 0.85, 0.20, 1)
C_BLUE    = (0.18, 0.52, 1.00, 1)
C_AMBER   = (1.00, 0.72, 0.10, 1)
C_GREEN   = (0.18, 0.82, 0.44, 1)
C_RED     = (1.00, 0.35, 0.35, 1)
C_PURPLE  = (0.65, 0.35, 1.00, 1)
C_BTN     = (0.13, 0.21, 0.38, 1)
C_BTN_HI  = (0.20, 0.32, 0.54, 1)
C_NEARBY  = (0.10, 0.30, 0.20, 1)   # teal-green tint for nearby cards
C_FAV     = (0.20, 0.16, 0.06, 1)   # warm gold tint for favourite cards

_MESH_FMT = [('vPosition', 2, 'float'), ('vTexCoords0', 2, 'float')]


# ── Shared helpers ────────────────────────────────────────────────────────────

def _lbl(text, font_size=14, color=C_TEXT, bold=False,
         halign="left", height=None, **kw):
    l = Label(text=text, font_size=sp(font_size), color=color, bold=bold,
              halign=halign, valign="middle", **kw)
    if height is not None:
        l.size_hint_y = None
        l.height = dp(height)
    l.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
    return l


def _btn(text, on_press=None, font_size=14, height=44,
         bg=C_BTN, bg_hi=C_BTN_HI, radius=8, **kw):
    b = _StyledButton(text=text, font_size=sp(font_size), color=C_TEXT,
                      bg_color=bg, bg_hi_color=bg_hi, radius=radius,
                      size_hint_y=None, height=dp(height), **kw)
    if on_press:
        b.bind(on_press=on_press)
    return b


def _section(title, icon=""):
    """Returns (outer BoxLayout, body BoxLayout) — styled panel."""
    outer = BoxLayout(orientation="vertical", size_hint_y=None, spacing=0)
    outer.bind(minimum_height=outer.setter("height"))

    hdr = _SectionHeader(f"  {icon}  {title}".strip() if icon else f"  {title}")
    outer.add_widget(hdr)

    body = BoxLayout(orientation="vertical", size_hint_y=None,
                     padding=(dp(10), dp(8), dp(10), dp(12)), spacing=dp(6))
    body.bind(minimum_height=body.setter("height"))
    with body.canvas.before:
        Color(*C_PANEL)
        _br = Rectangle(pos=body.pos, size=body.size)
    body.bind(pos=lambda w, v: setattr(_br, "pos", v),
              size=lambda w, v: setattr(_br, "size", v))
    outer.add_widget(body)
    return outer, body


def _row(*widgets, height=36):
    r = BoxLayout(orientation="horizontal", size_hint_y=None, height=dp(height))
    for w in widgets:
        r.add_widget(w)
    return r


# ── Styled widgets ────────────────────────────────────────────────────────────

class _SectionHeader(BoxLayout):
    def __init__(self, title="", **kw):
        super().__init__(size_hint_y=None, height=dp(34), **kw)
        with self.canvas.before:
            Color(*C_HEADER)
            _bg = Rectangle(pos=self.pos, size=self.size)
        self.bind(pos=lambda w, v: setattr(_bg, "pos", v),
                  size=lambda w, v: setattr(_bg, "size", v))
        lbl = Label(text=title.upper(), font_size=sp(10), bold=True,
                    color=C_CYAN, halign="left", padding=(dp(4), 0))
        lbl.bind(size=lambda w, v: setattr(w, "text_size", v))
        self.add_widget(lbl)


class _StyledButton(ButtonBehavior, BoxLayout):
    def __init__(self, text="", font_size=sp(14), color=C_TEXT,
                 bg_color=C_BTN, bg_hi_color=C_BTN_HI, radius=8, **kw):
        super().__init__(**kw)
        self._bg_color    = bg_color
        self._bg_hi_color = bg_hi_color
        self._radius      = radius
        with self.canvas.before:
            self._ci = Color(*bg_color)
            self._ri = RoundedRectangle(pos=self.pos, size=self.size,
                                        radius=[dp(radius)] * 4)
        self.bind(pos=self._upd, size=self._upd)
        lbl = Label(text=text, font_size=font_size, color=color,
                    halign="center", valign="middle")
        lbl.bind(size=lambda w, v: setattr(w, "text_size", v))
        self.add_widget(lbl)
        self._lbl = lbl

    def _upd(self, *_):
        self._ri.pos    = self.pos
        self._ri.size   = self.size
        self._ri.radius = [dp(self._radius)] * 4

    def on_press(self):    self._ci.rgba = self._bg_hi_color
    def on_release(self):  self._ci.rgba = self._bg_color


class _StationCard(ButtonBehavior, BoxLayout):
    """Touch-target station card with optional distance badge and accent stripe."""

    def __init__(self, station, is_fav=False, on_select=None,
                 on_star=None, on_remove=None, accent=C_CYAN, **kw):
        super().__init__(
            orientation="horizontal",
            size_hint_y=None, height=dp(64),
            padding=(0, 0, dp(10), 0),
            spacing=0, **kw,
        )
        self.station  = station
        self._on_sel  = on_select
        self._on_star = on_star
        self._on_rem  = on_remove
        self._accent  = accent

        with self.canvas.before:
            # Card background
            Color(*C_CARD)
            self._bg = RoundedRectangle(pos=self.pos, size=self.size,
                                        radius=[dp(8)] * 4)
            # Left accent stripe
            Color(*accent)
            self._stripe = RoundedRectangle(
                pos=self.pos, size=(dp(4), self.height),
                radius=[dp(8), 0, 0, dp(8)],
            )
        self.bind(pos=self._upd, size=self._upd)

        # Left stripe spacer
        self.add_widget(Widget(size_hint_x=None, width=dp(12)))

        # Icon
        icon_lbl = Label(
            text="*" if is_fav else "~" if "dist" in station else ".",
            font_size=sp(18),
            color=C_YELLOW if is_fav else C_GREEN if "dist" in station else C_DIM,
            size_hint_x=None, width=dp(28),
        )
        self.add_widget(icon_lbl)

        # Name + subtitle
        info = BoxLayout(orientation="vertical", padding=(dp(4), dp(6), 0, dp(6)))
        name_lbl = Label(text=station["name"], font_size=sp(14), color=C_TEXT,
                         halign="left", bold=True)
        name_lbl.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))

        sub_parts = []
        if "dist" in station:
            sub_parts.append(f"{station['dist']:.1f} mi away")
        sub_parts.append(f"Station {station['id']}")
        sub_lbl = Label(text="  -  ".join(sub_parts), font_size=sp(11),
                        color=C_DIM, halign="left")
        sub_lbl.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
        info.add_widget(name_lbl)
        info.add_widget(sub_lbl)
        self.add_widget(info)

        # Right actions
        if is_fav and on_remove:
            rem = Label(text="[x]", font_size=sp(13), color=C_DIM,
                        size_hint_x=None, width=dp(36))
            rem.bind(on_touch_down=self._rem_touch)
            self._rem_lbl = rem
            self.add_widget(rem)
        elif on_star:
            star = Label(text="[+]", font_size=sp(13), color=C_DIM,
                         size_hint_x=None, width=dp(36))
            star.bind(on_touch_down=self._star_touch)
            self.add_widget(star)

    def _upd(self, *_):
        self._bg.pos    = self.pos
        self._bg.size   = self.size
        self._stripe.pos  = self.pos
        self._stripe.size = (dp(4), self.height)

    def _rem_touch(self, w, touch):
        if w.collide_point(*touch.pos) and self._on_rem:
            self._on_rem(self.station["id"]); return True

    def _star_touch(self, w, touch):
        if w.collide_point(*touch.pos) and self._on_star:
            self._on_star(self.station); return True

    def on_press(self):
        with self.canvas.before:
            Color(0.18, 0.28, 0.46, 1)
            RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(8)] * 4)

    def on_release(self):
        self.canvas.before.clear()
        with self.canvas.before:
            Color(*C_CARD)
            self._bg = RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(8)] * 4)
            Color(*self._accent)
            self._stripe = RoundedRectangle(pos=self.pos, size=(dp(4), self.height),
                                            radius=[dp(8), 0, 0, dp(8)])
        if self._on_sel:
            self._on_sel(self.station)


# ── Animated wave header ──────────────────────────────────────────────────────

class WaveHeader(FloatLayout):
    """Dark gradient header with two animated sine waves."""

    def __init__(self, **kw):
        super().__init__(**kw)
        self._phase    = 0.0
        self._ticker   = None
        self._location = ""

        with self.canvas.before:
            # Deep background
            Color(0.03, 0.05, 0.11, 1)
            self._bg0 = Rectangle(pos=self.pos, size=self.size)
            # Mid-level gradient band
            Color(0.06, 0.10, 0.20, 0.9)
            self._bg1 = Rectangle(pos=self.pos, size=self.size)

        # Wave lines (update points each tick — much cheaper than full redraw)
        with self.canvas:
            self._wc1 = Color(0.10, 0.28, 0.55, 0.55)
            self._w1  = Line(width=dp(2))
            self._wc2 = Color(0.15, 0.50, 0.85, 0.75)
            self._w2  = Line(width=dp(2.5))
            self._wc3 = Color(0.22, 0.70, 1.00, 0.45)
            self._w3  = Line(width=dp(1.5))

        self.bind(pos=self._on_resize, size=self._on_resize)

        # Title label (centered)
        self._title = Label(
            text="~ TIDES",
            font_size=sp(34), bold=True,
            color=C_CYAN,
            halign="center", valign="middle",
            size_hint=(1, None), height=dp(54),
            pos_hint={"center_x": 0.5, "top": 0.98},
        )
        self._sub = Label(
            text="Live NOAA Conditions",
            font_size=sp(12),
            color=C_DIM,
            halign="center", valign="middle",
            size_hint=(1, None), height=dp(22),
            pos_hint={"center_x": 0.5, "top": 0.65},
        )
        self._loc_lbl = Label(
            text="",
            font_size=sp(11),
            color=C_GREEN,
            halign="center", valign="middle",
            size_hint=(1, None), height=dp(20),
            pos_hint={"center_x": 0.5, "top": 0.45},
        )
        self.add_widget(self._title)
        self.add_widget(self._sub)
        self.add_widget(self._loc_lbl)

    def set_location(self, city):
        self._loc_lbl.text = f"> {city}" if city else ""

    def start_animation(self):
        if self._ticker is None:
            self._ticker = Clock.schedule_interval(self._tick, 1 / 20)

    def stop_animation(self):
        if self._ticker:
            self._ticker.cancel()
            self._ticker = None

    def _on_resize(self, *_):
        w, h = self.size
        x0, y0 = self.pos
        self._bg0.pos  = (x0, y0)
        self._bg0.size = (w, h)
        self._bg1.pos  = (x0, y0 + h * 0.25)
        self._bg1.size = (w, h * 0.75)
        self._update_waves()

    def _tick(self, dt):
        self._phase += dt * 0.45
        self._update_waves()

    def _update_waves(self):
        w, h = self.size
        x0, y0 = self.pos
        if w < 4:
            return
        n = max(int(w / 4), 8)
        p1, p2, p3 = [], [], []
        for i in range(n + 1):
            t  = i / n
            px = x0 + t * w
            p1 += [px, y0 + h * 0.32 + math.sin(t * 5 * math.pi + self._phase * 0.8) * h * 0.07]
            p2 += [px, y0 + h * 0.22 + math.sin(t * 7 * math.pi + self._phase)       * h * 0.05]
            p3 += [px, y0 + h * 0.12 + math.sin(t * 4 * math.pi + self._phase * 1.3) * h * 0.04]
        self._w1.points = p1
        self._w2.points = p2
        self._w3.points = p3


# ── Search screen ─────────────────────────────────────────────────────────────

class SearchScreen(Screen):
    def __init__(self, **kw):
        super().__init__(**kw)
        self._loc_lat  = None
        self._loc_lon  = None
        self._loc_city = ""
        self._build()

    def _build(self):
        root = BoxLayout(orientation="vertical", spacing=0)
        with root.canvas.before:
            Color(*C_BG)
            _rb = Rectangle(pos=root.pos, size=root.size)
        root.bind(pos=lambda w, v: setattr(_rb, "pos", v),
                  size=lambda w, v: setattr(_rb, "size", v))

        # ── Animated wave header ───────────────────────────────────────────────
        self.wave = WaveHeader(size_hint_y=None, height=dp(150))
        root.add_widget(self.wave)

        # Exit button — transparent, top-right of wave header
        from kivy.uix.button import Button as _KivyBtn
        exit_btn = _KivyBtn(
            text="X", font_size=sp(20), bold=True, color=C_DIM,
            background_color=(0, 0, 0, 0), background_normal="",
            background_down="",
            size_hint=(None, None), width=dp(44), height=dp(44),
        )
        exit_btn.pos_hint = {"right": 1.0, "top": 1.0}
        exit_btn.bind(on_press=self._exit_app)
        self.wave.add_widget(exit_btn)

        # ── Search bar ─────────────────────────────────────────────────────────
        bar = BoxLayout(size_hint_y=None, height=dp(52),
                        padding=(dp(10), dp(6)), spacing=dp(8))
        with bar.canvas.before:
            Color(*C_HEADER)
            _bb = Rectangle(pos=bar.pos, size=bar.size)
        bar.bind(pos=lambda w, v: setattr(_bb, "pos", v),
                 size=lambda w, v: setattr(_bb, "size", v))

        self.search_input = TextInput(
            hint_text="Search by city, station name, or state...",
            multiline=False, font_size=sp(15),
            foreground_color=C_TEXT,
            background_color=(0.08, 0.13, 0.24, 1),
            cursor_color=C_CYAN,
            hint_text_color=C_DIM,
            size_hint_x=0.77,
        )
        self.search_input.bind(on_text_validate=self._do_search)
        bar.add_widget(self.search_input)
        bar.add_widget(_btn("Search", on_press=self._do_search,
                            size_hint_x=0.20, height=40, radius=6))
        bar.add_widget(_btn("i", on_press=self._open_about,
                            size_hint_x=None, width=dp(36), height=40, radius=6,
                            bg=(0.10, 0.18, 0.32, 1), bg_hi=(0.16, 0.28, 0.46, 1)))
        root.add_widget(bar)

        # ── Status strip ───────────────────────────────────────────────────────
        self.status = _lbl("  Detecting your location...", font_size=11,
                           color=C_DIM, size_hint_y=None, height=dp(26))
        root.add_widget(self.status)

        # ── Scrollable list ────────────────────────────────────────────────────
        sv = ScrollView(do_scroll_x=False)
        self.list_box = BoxLayout(orientation="vertical",
                                  size_hint_y=None,
                                  padding=(dp(8), dp(4), dp(8), dp(16)),
                                  spacing=dp(6))
        self.list_box.bind(minimum_height=self.list_box.setter("height"))
        sv.add_widget(self.list_box)
        root.add_widget(sv)

        self.add_widget(root)

    # ── Lifecycle ──────────────────────────────────────────────────────────────

    def on_enter(self):
        self.wave.start_animation()
        self._reload_static()
        threading.Thread(target=self._locate_thread, daemon=True).start()

    def on_leave(self):
        self.wave.stop_animation()

    def _open_about(self, *_):
        App.get_running_app().open_about()

    def _exit_app(self, *_):
        App.get_running_app().stop()

    # ── Location detection ─────────────────────────────────────────────────────

    def _locate_thread(self):
        # Try plyer GPS (Android) first, fall back to IP geolocation
        lat, lon, city = None, None, ""
        try:
            from plyer import gps  # only available on Android
            # Plyer GPS is async; IP geolocation is simpler for now
            raise ImportError
        except ImportError:
            lat, lon, city = td.get_ip_location()

        Clock.schedule_once(lambda dt: self._on_location(lat, lon, city))

    def _on_location(self, lat, lon, city):
        if lat is None:
            self.status.text = "  Could not detect location - search manually"
            return
        self._loc_lat  = lat
        self._loc_lon  = lon
        self._loc_city = city
        self.wave.set_location(city)
        self.status.text = f"  Location: {city}"
        threading.Thread(target=self._nearby_thread,
                         args=(lat, lon), daemon=True).start()

    def _nearby_thread(self, lat, lon):
        stations = td.nearest_stations(lat, lon, n=6)
        Clock.schedule_once(lambda dt: self._show_nearby(stations))

    def _show_nearby(self, stations):
        self._nearby_stations = stations
        self._reload_static()

    # ── List building ─────────────────────────────────────────────────────────

    def _reload_static(self):
        """Rebuild the list: favorites first, then nearby."""
        self.list_box.clear_widgets()
        favs   = td.load_favorites()
        nearby = getattr(self, "_nearby_stations", [])

        if favs:
            self._add_section_header("Favorites", C_YELLOW)
            for f in favs:
                self.list_box.add_widget(
                    _StationCard(f, is_fav=True, accent=C_YELLOW,
                                 on_select=self._select,
                                 on_remove=self._remove_fav))

        if nearby:
            self._add_section_header("Nearby Stations", C_GREEN)
            for s in nearby:
                self.list_box.add_widget(
                    _StationCard(s, accent=C_GREEN, on_select=self._select,
                                 on_star=self._save_fav))

        if not nearby and not favs:
            self.list_box.add_widget(
                _lbl("  Search for a station above to get started.",
                     font_size=13, color=C_DIM, height=48))

    def _add_section_header(self, text, color=C_CYAN):
        hdr = BoxLayout(size_hint_y=None, height=dp(30),
                        padding=(dp(4), dp(4), 0, 0))
        lbl = Label(text=text, font_size=sp(12), bold=True, color=color,
                    halign="left")
        lbl.bind(size=lambda w, v: setattr(w, "text_size", v))
        hdr.add_widget(lbl)
        self.list_box.add_widget(hdr)

    def _do_search(self, *_):
        query = self.search_input.text.strip()
        if not query:
            return
        self.status.text = f"  Searching for \"{query}\"..."
        threading.Thread(target=self._search_thread, args=(query,),
                         daemon=True).start()

    def _search_thread(self, query):
        results = td.search_stations(query)
        Clock.schedule_once(lambda dt: self._show_results(query, results))

    def _show_results(self, query, results):
        favs    = td.load_favorites()
        fav_ids = {f["id"] for f in favs}
        nearby  = getattr(self, "_nearby_stations", [])
        near_ids = {s["id"] for s in nearby}

        self.list_box.clear_widgets()

        # Enrich results with distance if we have a location
        if self._loc_lat is not None:
            for s in results:
                if "dist" not in s:
                    s["dist"] = td.haversine(
                        self._loc_lat, self._loc_lon, s["lat"], s["lon"])

        if not results:
            self.status.text = f"  No stations found for \"{query}\""
            self._reload_static()
            return

        cap = 40
        self.status.text = (f"  {len(results)} station(s) found"
                            + (f" - showing first {cap}" if len(results) > cap else ""))

        self._add_section_header(f"Results for \"{query}\"", C_CYAN)
        for s in results[:cap]:
            is_fav   = s["id"] in fav_ids
            is_near  = s["id"] in near_ids
            accent   = C_YELLOW if is_fav else C_GREEN if is_near else C_CYAN
            self.list_box.add_widget(
                _StationCard(s, is_fav=is_fav, accent=accent,
                             on_select=self._select,
                             on_star=None if is_fav else self._save_fav,
                             on_remove=self._remove_fav if is_fav else None))

        if favs:
            self._add_section_header("Favorites", C_YELLOW)
            for f in favs:
                self.list_box.add_widget(
                    _StationCard(f, is_fav=True, accent=C_YELLOW,
                                 on_select=self._select,
                                 on_remove=self._remove_fav))

    def _select(self, station):
        App.get_running_app().open_station(station)

    def _save_fav(self, station):
        td.add_favorite(station)
        self._reload_static()

    def _remove_fav(self, station_id):
        td.remove_favorite(station_id)
        self._reload_static()


# ── Tide chart widget ─────────────────────────────────────────────────────────

class TideChartWidget(Widget):
    def __init__(self, **kw):
        super().__init__(**kw)
        self.hourly      = {}
        self.hilo        = []
        self.target_date = date.today()
        self.bind(size=self._redraw, pos=self._redraw)

    def update(self, hourly, hilo, target_date):
        self.hourly      = hourly
        self.hilo        = hilo
        self.target_date = target_date
        self._redraw()

    @staticmethod
    def _tex(text, font_size=9, color=C_DIM):
        lbl = CoreLabel(text=text, font_size=sp(font_size), color=color)
        lbl.refresh()
        return lbl.texture

    def _interp(self, fh):
        # Catmull-Rom spline — C1 continuous, no kinks at hourly joints
        h0 = int(fh) % 24
        t  = fh - int(fh)
        def hv(h): return self.hourly.get(h % 24, 0)
        p0, p1, p2, p3 = hv(h0 - 1), hv(h0), hv(h0 + 1), hv(h0 + 2)
        return 0.5 * ((2*p1) + (-p0 + p2)*t +
                      (2*p0 - 5*p1 + 4*p2 - p3)*t**2 +
                      (-p0 + 3*p1 - 3*p2 + p3)*t**3)

    def _redraw(self, *_):
        self.canvas.clear()
        w, h = self.size
        x0, y0 = self.pos
        if w < 20 or h < 20:
            return

        with self.canvas:
            Color(*C_BG)
            Rectangle(pos=self.pos, size=self.size)

        if not self.hourly:
            return

        heights = list(self.hourly.values())
        min_h, max_h = min(heights), max(heights)
        rng = max_h - min_h if max_h != min_h else 1.0

        PL, PR, PT, PB = dp(46), dp(6), dp(6), dp(28)
        cw = w - PL - PR
        ch = h - PT - PB
        cx, cy = x0 + PL, y0 + PB

        with self.canvas:
            Color(0.06, 0.10, 0.18, 1)
            Rectangle(pos=(cx, cy), size=(cw, ch))

            # Grid + Y labels
            for i in range(5):
                frac = i / 4
                v    = min_h + rng * frac
                gy   = cy + frac * ch
                Color(0.13, 0.20, 0.32, 0.9)
                Line(points=[cx, gy, cx + cw, gy], width=0.8)
                tex = self._tex(f"{v:.1f}ft")
                Color(*C_DIM)
                Rectangle(texture=tex,
                          pos=(cx - tex.width - dp(3), gy - tex.height / 2),
                          size=tex.size)

            # Wave interpolation — 600 pts for smooth Catmull-Rom curve
            N, wave = 600, []
            for i in range(N + 1):
                fh = i / N * 23.9999
                v  = self._interp(fh)
                wave.append((cx + (i / N) * cw, cy + ((v - min_h) / rng) * ch))

            # Gradient mesh helper
            def band_mesh(wave_pts, lo_frac, hi_frac, color):
                lo_y = cy + lo_frac * ch
                hi_y = cy + hi_frac * ch
                verts, idxs = [], []
                for i, (px, py) in enumerate(wave_pts):
                    clipped_top = max(lo_y, min(hi_y, py))
                    verts += [px, clipped_top, 0, 1, px, lo_y, 0, 0]
                for i in range(len(wave_pts) - 1):
                    b = i * 2
                    idxs += [b, b+1, b+2, b+1, b+3, b+2]
                Color(*color)
                Mesh(vertices=verts, indices=idxs, mode="triangles", fmt=_MESH_FMT)

            # Lighter blue gradient bands
            band_mesh(wave, 0.00, 0.33, (0.12, 0.30, 0.72, 0.72))  # deep
            band_mesh(wave, 0.33, 0.66, (0.16, 0.46, 0.84, 0.68))  # mid
            band_mesh(wave, 0.66, 1.00, (0.22, 0.62, 0.96, 0.62))  # surface

            # Yellow fill for below-zero tide sections
            if min_h < 0 < max_h:
                zero_y = cy + ((0 - min_h) / rng) * ch
                verts, idxs = [], []
                for i, (px, py) in enumerate(wave):
                    top_y = min(py, zero_y)   # cap at zero line
                    verts += [px, top_y, 0, 1, px, cy, 0, 0]
                for i in range(len(wave) - 1):
                    b = i * 2
                    idxs += [b, b+1, b+2, b+1, b+3, b+2]
                Color(0.95, 0.78, 0.12, 0.68)
                Mesh(vertices=verts, indices=idxs, mode="triangles", fmt=_MESH_FMT)
                # Zero reference line
                Color(0.95, 0.78, 0.12, 0.55)
                Line(points=[cx, zero_y, cx + cw, zero_y], width=dp(1))

            # Wave crest line
            flat = [c for pt in wave for c in pt]
            Color(*C_CYAN)
            Line(points=flat, width=dp(1.5))

            # Current time marker
            if self.target_date == date.today():
                now   = datetime.now()
                nfrac = (now.hour + now.minute / 60) / 24
                nx    = cx + nfrac * cw
                Color(*C_YELLOW)
                Line(points=[nx, cy, nx, cy + ch], width=dp(1.5))
                # NOW label
                tex = self._tex("NOW", 8, C_YELLOW)
                Color(*C_YELLOW)
                Rectangle(texture=tex,
                          pos=(nx - tex.width / 2, cy + ch + dp(2)),
                          size=tex.size)

            # X axis
            Color(0.22, 0.35, 0.52, 1)
            Line(points=[cx, cy, cx + cw, cy], width=1)

            # Hour labels
            for hour in range(0, 24, 3):
                px  = cx + (hour / 24) * cw
                lbl = ("12a" if hour == 0 else "12p" if hour == 12
                       else f"{hour}a" if hour < 12 else f"{hour-12}p")
                tex = self._tex(lbl)
                Color(*C_DIM)
                Rectangle(texture=tex,
                          pos=(px - tex.width / 2, cy - tex.height - dp(3)),
                          size=tex.size)

            # Hi/Lo markers
            for t, val, typ in self.hilo:
                frac = (t.hour + t.minute / 60) / 24
                px   = cx + frac * cw
                py   = cy + ((val - min_h) / rng) * ch
                col  = C_CYAN if typ == "H" else C_AMBER
                Color(*col)
                Ellipse(pos=(px - dp(4), py - dp(4)), size=(dp(8), dp(8)))
                ts   = t.strftime("%I:%M").lstrip("0") + t.strftime(" %p")
                hs   = f"{val:+.2f}ft"
                t_tex = self._tex(ts, 9, C_TEXT)
                h_tex = self._tex(hs, 9, col)
                lx = min(max(px - t_tex.width / 2, cx), cx + cw - t_tex.width)
                if typ == "H":
                    Color(*C_TEXT)
                    Rectangle(texture=t_tex, pos=(lx, py + dp(7)), size=t_tex.size)
                    Color(*col)
                    Rectangle(texture=h_tex,
                              pos=(lx, py + dp(7) + t_tex.height + dp(1)),
                              size=h_tex.size)
                else:
                    Color(*C_TEXT)
                    Rectangle(texture=t_tex,
                              pos=(lx, py - t_tex.height - dp(7)), size=t_tex.size)
                    Color(*col)
                    Rectangle(texture=h_tex,
                              pos=(lx, py - t_tex.height - dp(7) - h_tex.height - dp(1)),
                              size=h_tex.size)


# ── Tide screen ───────────────────────────────────────────────────────────────

class TideScreen(Screen):
    def __init__(self, **kw):
        super().__init__(**kw)
        self._station     = None
        self._target_date = date.today()
        self._week_mode   = False
        self._week_start  = None   # Monday of the displayed week
        self._build()

    def _build(self):
        root = BoxLayout(orientation="vertical")
        with root.canvas.before:
            Color(*C_BG)
            _rb = Rectangle(pos=root.pos, size=root.size)
        root.bind(pos=lambda w, v: setattr(_rb, "pos", v),
                  size=lambda w, v: setattr(_rb, "size", v))

        # Top bar
        bar = BoxLayout(size_hint_y=None, height=dp(52),
                        padding=(dp(6), dp(6)), spacing=dp(6))
        with bar.canvas.before:
            Color(*C_HEADER)
            _bb = Rectangle(pos=bar.pos, size=bar.size)
        bar.bind(pos=lambda w, v: setattr(_bb, "pos", v),
                 size=lambda w, v: setattr(_bb, "size", v))

        bar.add_widget(_btn("< Back", on_press=self._go_back,
                            size_hint_x=None, width=dp(80), height=40, radius=6))
        self.title_lbl = Label(text="", font_size=sp(13), bold=True,
                               color=C_CYAN, halign="center")
        self.title_lbl.bind(size=lambda w, v: setattr(w, "text_size", v))
        bar.add_widget(self.title_lbl)
        bar.add_widget(_btn("Ref", on_press=self._refresh,
                            size_hint_x=None, width=dp(42), height=40, radius=6))
        root.add_widget(bar)

        # Date navigation bar
        nav = BoxLayout(size_hint_y=None, height=dp(40),
                        padding=(dp(4), dp(4)), spacing=dp(4))
        with nav.canvas.before:
            Color(0.08, 0.13, 0.24, 1)
            _nb = Rectangle(pos=nav.pos, size=nav.size)
        nav.bind(pos=lambda w, v: setattr(_nb, "pos", v),
                 size=lambda w, v: setattr(_nb, "size", v))

        nav.add_widget(_btn("<", on_press=self._nav_prev,
                            size_hint_x=None, width=dp(38), height=32, radius=6))
        self.date_lbl = Label(text="", font_size=sp(13), bold=True,
                              color=C_TEXT, halign="center")
        self.date_lbl.bind(size=lambda w, v: setattr(w, "text_size", v))
        nav.add_widget(self.date_lbl)
        self.week_btn = _btn("Week", on_press=self._toggle_week,
                             size_hint_x=None, width=dp(82), height=32, radius=6)
        nav.add_widget(self.week_btn)
        nav.add_widget(_btn(">", on_press=self._nav_next,
                            size_hint_x=None, width=dp(38), height=32, radius=6))
        root.add_widget(nav)

        # Loading state
        self.loading = BoxLayout(orientation="vertical")
        with self.loading.canvas.before:
            Color(*C_BG)
            _lb = Rectangle(pos=self.loading.pos, size=self.loading.size)
        self.loading.bind(pos=lambda w, v: setattr(_lb, "pos", v),
                          size=lambda w, v: setattr(_lb, "size", v))
        self.loading.add_widget(Label(text="", size_hint_y=0.3))
        self._loading_lbl = Label(text="Loading tide data...",
                                  font_size=sp(18), color=C_DIM)
        self.loading.add_widget(self._loading_lbl)
        self.loading.add_widget(Label(text="", size_hint_y=0.7))
        root.add_widget(self.loading)

        # Scroll content
        self._sv = ScrollView(do_scroll_x=False)
        self._content = BoxLayout(orientation="vertical", size_hint_y=None,
                                  padding=(dp(8), dp(6), dp(8), dp(24)),
                                  spacing=dp(8))
        self._content.bind(minimum_height=self._content.setter("height"))
        self._sv.add_widget(self._content)

        self._root = root
        self.add_widget(root)
        self._sync_nav_bar()

    def _go_back(self, *_):
        self.manager.transition = SlideTransition(direction="right")
        self.manager.current = "search"

    def _refresh(self, *_):
        if not self._station:
            return
        self._show_loading()
        if self._week_mode:
            threading.Thread(target=self._fetch_week, daemon=True).start()
        else:
            threading.Thread(target=self._fetch_day, daemon=True).start()

    def load(self, station, target_date=None):
        self._station      = station
        self._week_mode    = False
        self._target_date  = target_date or date.today()
        self._week_start   = td.week_bounds(self._target_date)[0]
        self.title_lbl.text = station["name"]
        self._sync_nav_bar()
        self._show_loading()
        threading.Thread(target=self._fetch_day, daemon=True).start()

    # ── Navigation ────────────────────────────────────────────────────────────

    def _nav_prev(self, *_):
        if self._week_mode:
            self._week_start -= timedelta(weeks=1)
            self._target_date = self._week_start
        else:
            self._target_date -= timedelta(days=1)
            self._week_start = td.week_bounds(self._target_date)[0]
        self._sync_nav_bar()
        self._show_loading()
        if self._week_mode:
            threading.Thread(target=self._fetch_week, daemon=True).start()
        else:
            threading.Thread(target=self._fetch_day, daemon=True).start()

    def _nav_next(self, *_):
        if self._week_mode:
            self._week_start += timedelta(weeks=1)
            self._target_date = self._week_start
        else:
            self._target_date += timedelta(days=1)
            self._week_start = td.week_bounds(self._target_date)[0]
        self._sync_nav_bar()
        self._show_loading()
        if self._week_mode:
            threading.Thread(target=self._fetch_week, daemon=True).start()
        else:
            threading.Thread(target=self._fetch_day, daemon=True).start()

    def _toggle_week(self, *_):
        self._week_mode = not self._week_mode
        self._week_start = td.week_bounds(self._target_date)[0]
        self._sync_nav_bar()
        self._show_loading()
        if self._week_mode:
            threading.Thread(target=self._fetch_week, daemon=True).start()
        else:
            threading.Thread(target=self._fetch_day, daemon=True).start()

    def _sync_nav_bar(self):
        if self._week_mode:
            end = self._week_start + timedelta(days=6)
            self.date_lbl.text = (
                f"{self._week_start.strftime('%b %d')} - {end.strftime('%b %d, %Y')}")
            self.week_btn._lbl.text = "Day"
        else:
            today = date.today()
            if self._target_date == today:
                self.date_lbl.text = "Today"
            elif self._target_date == today - timedelta(days=1):
                self.date_lbl.text = "Yesterday"
            elif self._target_date == today + timedelta(days=1):
                self.date_lbl.text = "Tomorrow"
            else:
                self.date_lbl.text = self._target_date.strftime("%a, %b %d %Y")
            self.week_btn._lbl.text = "Week"

    # ── Data fetching ─────────────────────────────────────────────────────────

    def _fetch_day(self):
        station = self._station
        d       = self._target_date
        data    = td.fetch_all_data(station["id"], station["lat"], station["lon"],
                                    target_date=d)
        Clock.schedule_once(lambda dt: self._on_day_ready(data))

    def _fetch_week(self):
        station = self._station
        start   = self._week_start
        end     = start + timedelta(days=6)
        hilo    = td.fetch_week_hilo(station["id"], start, end)
        Clock.schedule_once(lambda dt: self._on_week_ready(hilo, start, end))

    def _on_day_ready(self, data):
        self._data = data
        self._rebuild()
        self._show_content()

    def _on_week_ready(self, hilo, start, end):
        self._rebuild_week(hilo, start, end)
        self._show_content()

    def _show_loading(self):
        if self._sv.parent:
            self._root.remove_widget(self._sv)
        if not self.loading.parent:
            self._root.add_widget(self.loading)

    def _show_content(self):
        if self.loading.parent:
            self._root.remove_widget(self.loading)
        if not self._sv.parent:
            self._root.add_widget(self._sv)

    # ── Content ───────────────────────────────────────────────────────────────

    def _rebuild(self):
        self._content.clear_widgets()
        d, s = self._data, self._station

        # Station info header
        info_box = BoxLayout(orientation="vertical", size_hint_y=None,
                             padding=(dp(10), dp(4), dp(10), dp(2)), spacing=dp(2))
        info_box.bind(minimum_height=info_box.setter("height"))
        info_box.add_widget(_lbl(
            d["target_date"].strftime("%A, %B %d, %Y"),
            font_size=12, color=C_DIM, height=26))
        dist_str = (f"  -  {s['dist']:.1f} mi away" if "dist" in s else "")
        info_box.add_widget(_lbl(f"Station {s['id']}{dist_str}",
                                 font_size=11, color=C_DIM, height=22))

        # Save favorite button if not yet saved
        favs = td.load_favorites()
        if not any(f["id"] == s["id"] for f in favs):
            info_box.add_widget(_btn(
                "Save to favorites",
                on_press=lambda *_: self._save_and_rebuild(),
                height=36, radius=6,
                bg=(0.10, 0.20, 0.12, 1), bg_hi=(0.15, 0.30, 0.18, 1)))
        self._content.add_widget(info_box)

        self._content.add_widget(self._build_conditions(d))
        self._content.add_widget(self._build_chart(d))
        self._content.add_widget(self._build_sunmoon(d))
        self._content.add_widget(self._build_solunar(d))
        self._content.add_widget(self._build_fishing(d))

    def _save_and_rebuild(self):
        td.add_favorite(self._station)
        self._rebuild()

    def _rebuild_week(self, hilo, start, end):
        self._content.clear_widgets()
        today = date.today()

        # Group hi/lo events by date
        by_date = {}
        for t, val, typ in hilo:
            by_date.setdefault(t.date(), []).append((t, val, typ))

        cur = start
        while cur <= end:
            phase_name, _, emoji = td.moon_phase(cur)
            is_today = (cur == today)

            # Day card
            day_card = BoxLayout(orientation="vertical",
                                 size_hint_y=None,
                                 padding=(dp(10), dp(8), dp(10), dp(8)),
                                 spacing=dp(4))
            day_card.bind(minimum_height=day_card.setter("height"))
            with day_card.canvas.before:
                Color(*C_CARD)
                _dc = RoundedRectangle(pos=day_card.pos, size=day_card.size,
                                       radius=[dp(8)] * 4)
                # Left accent — gold for today, dim otherwise
                Color(*(C_YELLOW if is_today else (0.20, 0.30, 0.50, 1)))
                _ds = RoundedRectangle(pos=day_card.pos,
                                       size=(dp(4), day_card.height),
                                       radius=[dp(8), 0, 0, dp(8)])
            day_card.bind(
                pos=lambda w, v, dc=_dc, ds=_ds: (
                    setattr(dc, "pos", v), setattr(ds, "pos", v)),
                size=lambda w, v, dc=_dc, ds=_ds: (
                    setattr(dc, "size", v), setattr(ds, "size", (dp(4), v[1]))),
            )

            # Day header row
            day_str = cur.strftime("%A, %b %d")
            hdr_row = _row(height=30)
            day_col = C_YELLOW if is_today else C_TEXT
            hdr_row.add_widget(_lbl(
                (">  " if is_today else "   ") + day_str,
                font_size=14, bold=True, color=day_col))
            hdr_row.add_widget(Label(
                text=f"{phase_name}",
                font_size=sp(11), color=C_DIM,
                halign="right", size_hint_x=0.45))
            day_card.add_widget(hdr_row)

            # Hi/Lo rows
            events = sorted(by_date.get(cur, []), key=lambda x: x[0])
            if events:
                for t, val, typ in events:
                    ts   = t.strftime("%I:%M").lstrip("0") + t.strftime(" %p")
                    col  = C_CYAN if typ == "H" else C_AMBER
                    icon = "^ HI" if typ == "H" else "v LO"
                    r    = _row(height=28)
                    r.add_widget(Widget(size_hint_x=None, width=dp(16)))
                    r.add_widget(_lbl(icon, font_size=12, bold=True,
                                      color=col, size_hint_x=0.22))
                    r.add_widget(_lbl(ts, font_size=12,
                                      color=C_TEXT, size_hint_x=0.32))
                    r.add_widget(_lbl(f"{val:+.2f} ft", font_size=12,
                                      bold=True, color=col))
                    day_card.add_widget(r)
            else:
                day_card.add_widget(
                    _lbl("    No data", font_size=12, color=C_DIM, height=26))

            self._content.add_widget(day_card)
            # Small gap between days
            self._content.add_widget(Widget(size_hint_y=None, height=dp(6)))
            cur += timedelta(days=1)

    # ── Conditions ────────────────────────────────────────────────────────────

    def _build_conditions(self, d):
        outer, body = _section("Conditions", "")
        c, n = d["conditions"], d["nws"]

        def val(v, fmt="{}", unit="", na="N/A"):
            return fmt.format(v) + unit if v is not None else na

        def kv_row(pairs, height=32):
            r = _row(height=height)
            for label, value, color in pairs:
                col_box = BoxLayout(orientation="vertical")
                col_box.add_widget(_lbl(label, font_size=10, color=C_DIM, height=13))
                col_box.add_widget(_lbl(value, font_size=14, bold=True, color=color))
                r.add_widget(col_box)
            return r

        at_col = C_RED    if (c["air_temp"]   or 0) > 95 else \
                 C_YELLOW if (c["air_temp"]   or 0) > 85 else C_TEXT
        wt_col = C_CYAN   if (c["water_temp"] or 0) < 70 else \
                 C_GREEN  if (c["water_temp"] or 0) < 80 else C_YELLOW
        wl_col = C_BLUE   if abs(c["water_level"] or 0) < 0.5 else C_YELLOW
        ws     = c.get("wind_speed") or 0
        wc     = C_GREEN if ws < 10 else C_YELLOW if ws < 15 else C_RED

        pt     = c.get("pressure_trend", 0)
        p_arrow = " ↑" if pt > 0 else " ↓" if pt < 0 else ""
        p_col   = C_GREEN if pt > 0 else C_AMBER if pt < 0 else C_TEXT
        p_str   = val(c["pressure"], "{:.1f}", " mb") + p_arrow

        body.add_widget(kv_row([
            ("Air Temp",    val(c["air_temp"],    "{:.0f}", "F"), at_col),
            ("Water Temp",  val(c["water_temp"],  "{:.1f}", "F"), wt_col),
            ("Pressure",    p_str,                                p_col),
            ("Water Level", val(c["water_level"], "{:+.2f}", " ft"), wl_col),
        ], height=44))

        wind_str = "N/A"
        if c["wind_speed"] is not None:
            wind_str = (f"{c['wind_dir_str']} {c['wind_speed']:.0f} mph"
                        + (f"  (gusts {c['wind_gust']:.0f})"
                           if c["wind_gust"] and c["wind_gust"] > c["wind_speed"] + 3 else "")
                        + f"  -  {c['beaufort_str']}")
        r = _row(height=30)
        r.add_widget(_lbl("Wind", font_size=10, color=C_DIM,
                          size_hint_x=None, width=dp(50)))
        r.add_widget(_lbl(wind_str, font_size=13, bold=True, color=wc))
        body.add_widget(r)

        if n and "condition" in n:
            cc  = n["condition"]
            ccol = (C_YELLOW if any(w in cc for w in ("Sunny", "Clear", "Fair"))
                    else C_RED if any(w in cc for w in ("Storm", "Thunder", "Rain"))
                    else C_CYAN if "Cloud" in cc else C_TEXT)
            r2 = _row(height=30)
            r2.add_widget(_lbl("NWS", font_size=10, color=C_DIM,
                               size_hint_x=None, width=dp(50)))
            r2.add_widget(_lbl(
                f"{cc}  -  {n.get('temp','')}F  -  Rain {n.get('rain_pct',0)}%",
                font_size=13, bold=True, color=ccol))
            body.add_widget(r2)

            if n.get("periods"):
                body.add_widget(_btn(
                    "View Full NWS Forecast  >",
                    on_press=lambda *_, _n=n: self._show_nws_popup(_n),
                    height=34, radius=6,
                    bg=(0.10, 0.18, 0.32, 1), bg_hi=(0.16, 0.28, 0.46, 1)))
        return outer

    def _show_nws_popup(self, nws):
        content = BoxLayout(orientation="vertical", spacing=dp(8),
                            padding=(dp(10), dp(10), dp(10), dp(10)))
        with content.canvas.before:
            Color(*C_BG)
            _pb = Rectangle(pos=content.pos, size=content.size)
        content.bind(pos=lambda w, v: setattr(_pb, "pos", v),
                     size=lambda w, v: setattr(_pb, "size", v))

        sv = ScrollView(do_scroll_x=False)
        inner = BoxLayout(orientation="vertical", size_hint_y=None,
                          spacing=dp(12), padding=(0, dp(4), 0, dp(8)))
        inner.bind(minimum_height=inner.setter("height"))

        for p in (nws.get("periods") or []):
            card = BoxLayout(orientation="vertical", size_hint_y=None,
                             padding=(dp(10), dp(10), dp(10), dp(10)), spacing=dp(6))
            with card.canvas.before:
                Color(*C_PANEL)
                _cr = RoundedRectangle(pos=card.pos, size=card.size, radius=[dp(8)]*4)
            card.bind(pos=lambda w, v, r=_cr: setattr(r, "pos", v),
                      size=lambda w, v, r=_cr: setattr(r, "size", v))
            card.bind(minimum_height=card.setter("height"))

            name_lbl = Label(text=p["name"], font_size=sp(15), bold=True,
                             color=C_YELLOW, size_hint_y=None, halign="left")
            name_lbl.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
            name_lbl.bind(texture_size=lambda w, v: setattr(w, "height", v[1] + dp(2)))

            detail_lbl = Label(text=p["detail"], font_size=sp(14), color=C_TEXT,
                               size_hint_y=None, halign="left")
            detail_lbl.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
            detail_lbl.bind(texture_size=lambda w, v: setattr(w, "height", v[1] + dp(4)))

            card.add_widget(name_lbl)
            card.add_widget(detail_lbl)
            inner.add_widget(card)

        sv.add_widget(inner)
        content.add_widget(sv)

        close_btn = _btn("Close", height=44, radius=8)
        content.add_widget(close_btn)

        popup = Popup(
            title="NWS Forecast",
            title_size=sp(15),
            content=content,
            size_hint=(0.93, 0.82),
            background_color=(*C_HEADER[:3], 1),
            title_color=C_CYAN,
            separator_color=C_CYAN,
        )
        close_btn.bind(on_press=popup.dismiss)
        popup.open()

    # ── Chart ─────────────────────────────────────────────────────────────────

    def _build_chart(self, d):
        outer, body = _section("Tide Chart", "")
        chart = TideChartWidget(size_hint_y=None, height=dp(220))
        chart.update(d["hourly"], d["hilo"], d["target_date"])
        body.add_widget(chart)

        body.add_widget(_lbl("High / Low Tides", font_size=11, bold=True,
                             color=C_DIM, height=28))
        for t, val, typ in d["hilo"]:
            ts   = t.strftime("%I:%M").lstrip("0") + t.strftime(" %p")
            col  = C_CYAN if typ == "H" else C_AMBER
            icon = "^ HI" if typ == "H" else "v LO"
            r    = _row(height=34)
            r.add_widget(_lbl(icon, font_size=13, bold=True, color=col,
                              size_hint_x=0.22))
            r.add_widget(_lbl(ts,   font_size=13, color=C_TEXT, size_hint_x=0.30))
            r.add_widget(_lbl(f"{val:+.2f} ft", font_size=13, bold=True,
                              color=col, size_hint_x=0.30))
            r.add_widget(Label(size_hint_x=0.18))
            body.add_widget(r)

        leg = _row(height=22)
        leg.add_widget(_lbl("Legend:", font_size=10, color=C_DIM,
                            size_hint_x=None, width=dp(56)))
        for txt, col in [("* Deep", C_BLUE), ("* Mid", C_CYAN),
                         ("* Surface", (0.4, 0.75, 1, 1)), ("| Now", C_YELLOW)]:
            leg.add_widget(_lbl(txt, font_size=10, color=col))
        body.add_widget(leg)
        return outer

    # ── Sun & Moon ────────────────────────────────────────────────────────────

    def _build_sunmoon(self, d):
        outer, body = _section("Sun & Moon", "")
        sun, moon = d["sun"], d["moon"]

        grid = GridLayout(cols=4, size_hint_y=None, height=dp(52), spacing=dp(8))
        for label, val in [("Sunrise", sun["sunrise"]), ("Noon", sun["noon"]),
                            ("Sunset", sun["sunset"]),  ("Golden", sun["golden"])]:
            col_box = BoxLayout(orientation="vertical")
            col_box.add_widget(_lbl(label, font_size=10, color=C_DIM, height=18,
                                    halign="center"))
            col_box.add_widget(_lbl(val, font_size=12, bold=True, color=C_YELLOW,
                                    halign="center"))
            grid.add_widget(col_box)
        body.add_widget(grid)

        body.add_widget(_lbl(
            f"{moon['phase']}  -  {moon['pct']}% illuminated",
            font_size=14, color=C_TEXT, height=32))
        return outer

    # ── Solunar ───────────────────────────────────────────────────────────────

    def _build_solunar(self, d):
        outer, body = _section("Solunar Feeding Periods", "")
        sol      = d["solunar"]
        now_h    = datetime.now().hour + datetime.now().minute / 60
        is_today = d["is_today"]

        def period_str(start, dur):
            end = (start + dur) % 24
            return f"{td.hhmm(start)} - {td.hhmm(end)}"

        def in_p(start, dur):
            end = (start + dur) % 24
            return (start <= now_h < end) if start < end else (now_h >= start or now_h < end)

        for label, key, dur, col in [
            ("MAJOR", "major1", 2, C_CYAN),
            ("MAJOR", "major2", 2, C_CYAN),
            ("minor", "minor1", 1, C_DIM),
            ("minor", "minor2", 1, C_DIM),
        ]:
            active = is_today and in_p(sol[key], dur)
            r = _row(height=32)
            r.add_widget(_lbl(label, font_size=13, bold=(dur == 2),
                              color=col, size_hint_x=0.25))
            r.add_widget(_lbl(period_str(sol[key], dur), font_size=13, color=C_TEXT))
            if active:
                r.add_widget(_lbl("< NOW", font_size=12, bold=True,
                                  color=C_GREEN, size_hint_x=0.22))
            body.add_widget(r)
        return outer

    # ── Fishing ───────────────────────────────────────────────────────────────

    def _build_fishing(self, d):
        outer, body = _section("Fishing Conditions", "")
        stars, label = d["fishing"]["stars"], d["fishing"]["label"]

        col = (C_GREEN  if stars >= 4 else
               C_YELLOW if stars >= 3 else
               C_AMBER  if stars >= 2 else C_DIM)

        filled = "*" * stars + "-" * (5 - stars)
        r = _row(height=52)
        r.add_widget(_lbl(filled, font_size=28, color=col, size_hint_x=0.48))
        lv = BoxLayout(orientation="vertical")
        lv.add_widget(_lbl(label, font_size=18, bold=True, color=col))
        lv.add_widget(_lbl("Current conditions" if d["is_today"]
                           else "Rating available for today only",
                           font_size=10, color=C_DIM))
        r.add_widget(lv)
        body.add_widget(r)
        return outer


# ── About screen ─────────────────────────────────────────────────────────────

_LICENSES = [
    ("Python 3",              "PSF License 2.0",   "python.org"),
    ("Kivy",                  "MIT License",        "kivy.org"),
    ("python-for-android",    "MIT License",        "github.com/kivy/python-for-android"),
    ("SDL2",                  "zlib License",       "libsdl.org"),
    ("OpenSSL",               "Apache License 2.0", "openssl.org"),
    ("certifi",               "MPL-2.0",            "certifi.io"),
    ("urllib3",               "MIT License",        "urllib3.readthedocs.io"),
    ("requests",              "Apache License 2.0", "python-requests.org"),
    ("NOAA CO-OPS API",       "U.S. Public Domain", "tidesandcurrents.noaa.gov"),
    ("NWS / weather.gov API", "U.S. Public Domain", "weather.gov"),
]

class AboutScreen(Screen):
    def __init__(self, **kw):
        super().__init__(**kw)
        root = BoxLayout(orientation="vertical")
        with root.canvas.before:
            Color(*C_BG)
            _rb = Rectangle(pos=root.pos, size=root.size)
        root.bind(pos=lambda w, v: setattr(_rb, "pos", v),
                  size=lambda w, v: setattr(_rb, "size", v))

        # Top bar
        bar = BoxLayout(size_hint_y=None, height=dp(52),
                        padding=(dp(6), dp(6)), spacing=dp(6))
        with bar.canvas.before:
            Color(*C_HEADER)
            _bb = Rectangle(pos=bar.pos, size=bar.size)
        bar.bind(pos=lambda w, v: setattr(_bb, "pos", v),
                 size=lambda w, v: setattr(_bb, "size", v))
        bar.add_widget(_btn("< Back", on_press=self._go_back,
                            size_hint_x=None, width=dp(80), height=40, radius=6))
        bar.add_widget(Label(text="About", font_size=sp(15), bold=True,
                             color=C_CYAN, halign="center"))
        root.add_widget(bar)

        sv = ScrollView(do_scroll_x=False)
        body = BoxLayout(orientation="vertical", size_hint_y=None,
                         padding=(dp(16), dp(16), dp(16), dp(32)), spacing=dp(10))
        body.bind(minimum_height=body.setter("height"))

        def hdg(text, color=C_CYAN):
            l = Label(text=text, font_size=sp(13), bold=True, color=color,
                      size_hint_y=None, height=dp(30), halign="left")
            l.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
            return l

        def row(text, color=C_TEXT, size=12):
            l = Label(text=text, font_size=sp(size), color=color,
                      size_hint_y=None, halign="left")
            l.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
            l.bind(texture_size=lambda w, v: setattr(w, "height", v[1] + dp(4)))
            return l

        def divider():
            w = Widget(size_hint_y=None, height=dp(1))
            with w.canvas:
                Color(0.15, 0.22, 0.38, 1)
                _d = Rectangle(pos=w.pos, size=w.size)
            w.bind(pos=lambda ww, v: setattr(_d, "pos", v),
                   size=lambda ww, v: setattr(_d, "size", v))
            return w

        # App identity
        body.add_widget(hdg("~ TIDES", C_CYAN))
        body.add_widget(row(f"Version {_APP_VERSION}  -  Live NOAA tide data for Android",
                            C_DIM, 11))

        # Release link row
        body.add_widget(row(f"Releases:  {_RELEASES_URL}", C_BLUE, 11))
        body.add_widget(Widget(size_hint_y=None, height=dp(4)))

        # Update check
        self._upd_status = row("", C_DIM, 11)
        upd_row = BoxLayout(size_hint_y=None, height=dp(40), spacing=dp(8))
        self._upd_btn = _btn("Check for Updates", on_press=self._check_updates,
                             height=38, radius=6,
                             bg=(0.10, 0.20, 0.34, 1), bg_hi=(0.16, 0.30, 0.48, 1))
        upd_row.add_widget(self._upd_btn)
        body.add_widget(upd_row)
        body.add_widget(self._upd_status)
        body.add_widget(Widget(size_hint_y=None, height=dp(4)))

        # Developer
        body.add_widget(divider())
        body.add_widget(hdg("Developer"))
        body.add_widget(row("Matt Bettinger"))
        body.add_widget(row("tides-mobile.human695@passmail.com", C_DIM, 11))
        body.add_widget(Widget(size_hint_y=None, height=dp(6)))

        # Data sources + licenses
        body.add_widget(divider())
        body.add_widget(hdg("Open Source Software & Data Sources"))
        body.add_widget(Widget(size_hint_y=None, height=dp(4)))

        for name, lic, url in _LICENSES:
            card = BoxLayout(orientation="vertical", size_hint_y=None,
                             padding=(dp(10), dp(8), dp(10), dp(8)), spacing=dp(2))
            with card.canvas.before:
                Color(*C_PANEL)
                _cr = RoundedRectangle(pos=card.pos, size=card.size, radius=[dp(6)]*4)
            card.bind(pos=lambda w, v, r=_cr: setattr(r, "pos", v),
                      size=lambda w, v, r=_cr: setattr(r, "size", v))
            card.bind(minimum_height=card.setter("height"))
            name_lbl = Label(text=name, font_size=sp(13), bold=True,
                             color=C_TEXT, size_hint_y=None, height=dp(22),
                             halign="left")
            name_lbl.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
            lic_lbl = Label(text=f"{lic}  -  {url}", font_size=sp(10),
                            color=C_DIM, size_hint_y=None, halign="left")
            lic_lbl.bind(size=lambda w, v: setattr(w, "text_size", (v[0], None)))
            lic_lbl.bind(texture_size=lambda w, v: setattr(w, "height", v[1] + dp(2)))
            card.add_widget(name_lbl)
            card.add_widget(lic_lbl)
            body.add_widget(card)

        body.add_widget(Widget(size_hint_y=None, height=dp(8)))
        body.add_widget(divider())
        body.add_widget(row(
            "Data provided by NOAA CO-OPS and the National Weather Service.\n"
            "All government data is in the public domain.",
            C_DIM, 10))

        sv.add_widget(body)
        root.add_widget(sv)
        self.add_widget(root)

    def _go_back(self, *_):
        self.manager.transition = SlideTransition(direction="right")
        self.manager.current = "search"

    def _check_updates(self, *_):
        self._upd_btn._lbl.text = "Checking..."
        self._upd_status.text = ""
        threading.Thread(target=self._update_thread, daemon=True).start()

    def _update_thread(self):
        try:
            ctx = ssl.create_default_context()
            try:
                import certifi
                ctx = ssl.create_default_context(cafile=certifi.where())
            except Exception:
                pass
            req = urllib.request.Request(
                _RELEASES_API,
                headers={"User-Agent": "tides-android/1.0"})
            with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
                data = json.loads(resp.read().decode())
            latest = data.get("tag_name", "").lstrip("v")
            if latest == _APP_VERSION:
                msg = f"You are up to date  (v{_APP_VERSION})"
                col = C_GREEN
            elif latest:
                msg = f"Update available: v{latest}  -  {_RELEASES_URL}"
                col = C_YELLOW
            else:
                msg = "Could not determine latest version"
                col = C_DIM
        except Exception:
            msg = "Could not reach update server"
            col = C_DIM

        def _apply(dt):
            self._upd_btn._lbl.text = "Check for Updates"
            self._upd_status.text  = msg
            self._upd_status.color = col
        Clock.schedule_once(_apply)


# ── App ───────────────────────────────────────────────────────────────────────

class TidesApp(App):
    def build(self):
        Window.clearcolor = C_BG
        self.title = "Tides"
        android_private = os.environ.get('ANDROID_PRIVATE')
        if android_private:
            td.set_data_dir(android_private)
        Window.bind(on_keyboard=self._on_keyboard)
        sm = ScreenManager()
        sm.add_widget(SearchScreen(name="search"))
        sm.add_widget(TideScreen(name="tides"))
        sm.add_widget(AboutScreen(name="about"))
        return sm

    def _on_keyboard(self, window, key, *args):
        # Android back key (27 = Escape, maps to KEYCODE_BACK)
        if key == 27:
            sm = self.root
            if sm.current == "tides":
                sm.transition = SlideTransition(direction="right")
                sm.current = "search"
                return True  # consumed
            elif sm.current == "about":
                sm.transition = SlideTransition(direction="right")
                sm.current = "search"
                return True
        return False

    def on_pause(self):
        return True  # keep app alive, GL context preserved by Kivy

    def on_resume(self):
        pass

    def open_station(self, station):
        sm   = self.root
        tide = sm.get_screen("tides")
        sm.transition = SlideTransition(direction="left")
        sm.current    = "tides"
        tide.load(station)

    def open_about(self):
        sm = self.root
        sm.transition = SlideTransition(direction="left")
        sm.current = "about"


if __name__ == "__main__":
    TidesApp().run()
