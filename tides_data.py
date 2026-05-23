"""Pure data layer — no terminal/ANSI output. Used by both main.py and tides.py."""

import json
import math
import os
import ssl
import urllib.request
import concurrent.futures
from datetime import datetime, date, timedelta
from pathlib import Path

_DATA_DIR = None  # overridden by main.py on Android via set_data_dir()


def set_data_dir(path):
    global _DATA_DIR
    _DATA_DIR = path


def _make_ssl_context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        ctx = ssl.create_default_context()
        return ctx

_SSL_CTX = _make_ssl_context()


# ── Utilities ─────────────────────────────────────────────────────────────────

def _get(url, timeout=10, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CTX) as r:
            return json.loads(r.read().decode())
    except Exception:
        return None


def central_utc_offset(d):
    y = d.year
    dst_start = min(date(y, 3, day) for day in range(8, 15) if date(y, 3, day).weekday() == 6)
    dst_end   = min(date(y, 11, day) for day in range(1, 8) if date(y, 11, day).weekday() == 6)
    return -5.0 if dst_start <= d < dst_end else -6.0


def hhmm(decimal_hours):
    h  = decimal_hours % 24
    hh = int(h)
    mm = int(round((h - hh) * 60))
    if mm == 60:
        hh += 1; mm = 0
    suffix = "AM" if hh < 12 else "PM"
    hh12   = hh % 12 or 12
    return f"{hh12}:{mm:02d} {suffix}"


def wind_dir_arrow(degrees):
    dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
            "S","SSW","SW","WSW","W","WNW","NW","NNW"]
    return dirs[round(degrees / 22.5) % 16]


def beaufort(mph):
    if mph < 1:   return "Calm"
    if mph < 4:   return "Light air"
    if mph < 8:   return "Light breeze"
    if mph < 13:  return "Gentle breeze"
    if mph < 19:  return "Moderate breeze"
    if mph < 25:  return "Fresh breeze"
    if mph < 32:  return "Strong breeze"
    return "Near gale+"


# ── Astronomy ─────────────────────────────────────────────────────────────────

def julian_date(d):
    y, m, day = d.year, d.month, d.day
    if m <= 2:
        y -= 1; m += 12
    A = y // 100
    B = 2 - A + A // 4
    return int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + day + B - 1524.5


def moon_phase(d):
    days  = (julian_date(d) - 2451549.5) % 29.53058867
    illum = round((1 - math.cos(2 * math.pi * days / 29.53058867)) / 2 * 100)
    p = days / 29.53058867
    if   p < 0.0625 or p >= 0.9375: return "New Moon",        illum, ""
    elif p < 0.1875:                 return "Waxing Crescent", illum, ""
    elif p < 0.3125:                 return "First Quarter",   illum, ""
    elif p < 0.4375:                 return "Waxing Gibbous",  illum, ""
    elif p < 0.5625:                 return "Full Moon",       illum, ""
    elif p < 0.6875:                 return "Waning Gibbous",  illum, ""
    elif p < 0.8125:                 return "Last Quarter",    illum, ""
    else:                            return "Waning Crescent", illum, ""


def sun_times(d, lat, lon, utc_off):
    N      = d.timetuple().tm_yday
    decl_r = math.radians(-23.45 * math.cos(math.radians(360 / 365 * (N + 10))))
    B      = math.radians(360 / 364 * (N - 81))
    eot    = 9.87 * math.sin(2 * B) - 7.53 * math.cos(B) - 1.5 * math.sin(B)
    noon_utc = 12.0 - lon / 15.0 - eot / 60.0
    cos_ha   = -math.tan(math.radians(lat)) * math.tan(decl_r)
    if not (-1 < cos_ha < 1):
        return None, None, noon_utc + utc_off
    ha_h = math.degrees(math.acos(cos_ha)) / 15.0
    return noon_utc - ha_h + utc_off, noon_utc + ha_h + utc_off, noon_utc + utc_off


def moon_ra(jd):
    d   = jd - 2451545.0
    L   = (218.316 + 13.176396 * d) % 360
    M   = math.radians((134.963 + 13.064993 * d) % 360)
    F   = math.radians((93.272  + 13.229350 * d) % 360)
    lam = (L + 6.289 * math.sin(M)
             - 1.274 * math.sin(2 * math.radians(L) - M)
             + 0.658 * math.sin(2 * math.radians(L))
             - 0.214 * math.sin(2 * M)
             - 0.114 * math.sin(2 * F)) % 360
    beta = 5.128 * math.sin(F)
    eps  = math.radians(23.439 - 0.0000004 * d)
    lr, br = math.radians(lam), math.radians(beta)
    x = math.cos(br) * math.cos(lr)
    y = math.cos(eps) * math.cos(br) * math.sin(lr) - math.sin(eps) * math.sin(br)
    return math.degrees(math.atan2(y, x)) % 360


def solunar_times(d, lon, utc_off):
    jd0   = julian_date(d)
    T     = (jd0 - 2451545.0) / 36525.0
    gmst0 = (100.4606184 + 36000.77004 * T + 0.000387933 * T ** 2) % 360
    ra    = moon_ra(jd0 + 0.5)
    t_ut  = ((ra - lon - gmst0) % 360) / (360.985647 / 24)
    ra    = moon_ra(jd0 + t_ut / 24)
    t_ut  = ((ra - lon - gmst0) % 360) / (360.985647 / 24)
    upper  = (t_ut + utc_off) % 24
    lower  = (upper + 12 + 25 / 60) % 24
    minor1 = (upper - 6 - 12.5 / 60) % 24
    minor2 = (upper + 6 + 12.5 / 60) % 24
    return {"major1": upper, "major2": lower, "minor1": minor1, "minor2": minor2}


# ── Station search ────────────────────────────────────────────────────────────

_STATIONS_URL = (
    "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json"
    "?type=tidepredictions&units=english"
)


_stations_cache = None  # populated on first fetch, reused for autocomplete


def _load_stations():
    global _stations_cache
    if _stations_cache is None:
        data = _get(_STATIONS_URL, timeout=15)
        if data and "stations" in data:
            _stations_cache = data["stations"]
    return _stations_cache or []


def search_stations(query):
    q = query.lower()
    out = []
    for s in _load_stations():
        name  = s.get("name", "")
        state = s.get("state", "")
        if q in name.lower() or q in state.lower():
            out.append({
                "id":   s["id"],
                "name": f"{name}, {state}" if state else name,
                "lat":  float(s.get("lat", 0)),
                "lon":  float(s.get("lng", 0)),
            })
    return out


def fetch_station_info(station_id):
    url  = (f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/"
            f"stations/{station_id}.json")
    data = _get(url, timeout=10)
    if not data or not data.get("stations"):
        return None
    s     = data["stations"][0]
    state = s.get("state", "")
    name  = s.get("name", "")
    return {
        "id":   station_id,
        "name": f"{name}, {state}" if state else name,
        "lat":  float(s.get("lat", 0)),
        "lon":  float(s.get("lng", 0)),
    }


# ── NOAA data fetching ────────────────────────────────────────────────────────

def _fetch_predictions(station_id, date_str, interval):
    url = (
        "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        f"?begin_date={date_str}&end_date={date_str}"
        f"&station={station_id}"
        "&product=predictions&datum=MLLW&time_zone=lst_ldt"
        f"&interval={interval}&units=english&format=json&application=tides_android"
    )
    data = _get(url, timeout=12)
    return (data or {}).get("predictions", [])


def _fetch_obs(station_id, product):
    url = (
        "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        f"?station={station_id}&product={product}"
        "&date=latest&units=english&time_zone=lst_ldt&format=json"
    )
    data = _get(url)
    if not data or "data" not in data:
        return None
    try:
        return data["data"][-1]
    except (IndexError, KeyError):
        return None


def _fetch_pressure_trend(station_id):
    """Return +1 rising, -1 falling, 0 steady — based on last 3h of pressure."""
    url = (
        "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        f"?station={station_id}&product=air_pressure"
        "&range=3&units=english&time_zone=lst_ldt&format=json"
    )
    data = _get(url)
    if not data or "data" not in data:
        return 0
    pts = data["data"]
    if len(pts) < 2:
        return 0
    try:
        diff = float(pts[-1]["v"]) - float(pts[0]["v"])
        return 1 if diff > 0.5 else -1 if diff < -0.5 else 0
    except (KeyError, ValueError, TypeError):
        return 0


def _fetch_water_level(station_id):
    url = (
        "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        f"?station={station_id}&product=water_level&datum=MLLW"
        "&date=latest&units=english&time_zone=lst_ldt&format=json"
    )
    data = _get(url)
    if not data or "data" not in data:
        return None
    try:
        return data["data"][-1]
    except (IndexError, KeyError):
        return None


def _fetch_nws(lat, lon):
    hdr = {"User-Agent": "tides-android/1.0"}
    pts = _get(f"https://api.weather.gov/points/{lat},{lon}", timeout=8, headers=hdr)
    if not pts:
        return None
    result = {}
    hourly_url   = pts.get("properties", {}).get("forecastHourly")
    forecast_url = pts.get("properties", {}).get("forecast")
    if hourly_url:
        hly = _get(hourly_url, timeout=8, headers=hdr)
        if hly:
            result["hourly"] = hly.get("properties", {}).get("periods", [])[:3]
    if forecast_url:
        fc = _get(forecast_url, timeout=8, headers=hdr)
        if fc:
            result["forecast"] = fc.get("properties", {}).get("periods", [])
    return result or None


# ── Parsing ───────────────────────────────────────────────────────────────────

def _parse_hourly(raw):
    out = {}
    for p in raw:
        try:
            t = datetime.strptime(p["t"], "%Y-%m-%d %H:%M")
            out[t.hour] = float(p["v"])
        except (KeyError, ValueError):
            pass
    return out   # dict: hour(0-23) → height_ft


def _parse_hilo(raw):
    out = []
    for p in raw:
        try:
            t = datetime.strptime(p["t"], "%Y-%m-%d %H:%M")
            out.append((t, float(p["v"]), p["type"]))
        except (KeyError, ValueError):
            pass
    return out   # list of (datetime, height_ft, "H"/"L")


def _parse_conditions(obs):
    def ov(key, field="v"):
        try:
            val = obs.get(key)
            return None if val is None else val.get(field)
        except AttributeError:
            return None

    c = {k: None for k in (
        "air_temp", "water_temp", "wind_speed", "wind_dir",
        "wind_gust", "wind_dir_str", "beaufort_str", "pressure", "water_level",
    )}
    try: c["air_temp"]    = float(ov("air_temperature"))
    except (TypeError, ValueError): pass
    try: c["water_temp"]  = float(ov("water_temperature"))
    except (TypeError, ValueError): pass
    try:
        ws = float(ov("wind", "s"))
        wd = float(ov("wind", "d"))
        wg = float(ov("wind", "g"))
        c["wind_speed"]   = ws
        c["wind_dir"]     = wd
        c["wind_gust"]    = wg
        c["wind_dir_str"] = wind_dir_arrow(wd)
        c["beaufort_str"] = beaufort(ws)
    except (TypeError, ValueError): pass
    try: c["pressure"]    = float(ov("air_pressure"))
    except (TypeError, ValueError): pass
    try: c["water_level"] = float(ov("water_level"))
    except (TypeError, ValueError): pass
    return c


def _parse_nws(raw):
    if not raw:
        return None
    r = {}
    if raw.get("hourly"):
        cur = raw["hourly"][0]
        r["condition"]  = cur.get("shortForecast", "")
        r["temp"]       = cur.get("temperature", "")
        r["rain_pct"]   = cur.get("probabilityOfPrecipitation", {}).get("value") or 0
        r["wind_speed"] = cur.get("windSpeed", "")
        r["wind_dir"]   = cur.get("windDirection", "")
    if raw.get("forecast"):
        r["periods"] = [
            {"name": p.get("name", ""), "detail": p.get("detailedForecast", "")}
            for p in raw["forecast"]
        ]
    return r


# ── Fishing rating ────────────────────────────────────────────────────────────

def fishing_rating(hilo, wind_mph, sol, target_date=None):
    is_today = (target_date is None or target_date == date.today())
    if not is_today:
        return 0, "N/A"
    now_h = datetime.now().hour + datetime.now().minute / 60
    score = 0

    for t, _, _ in hilo:
        diff = abs((t.hour + t.minute / 60) - now_h)
        if diff < 1.5:  score += 2; break
        if diff < 3.0:  score += 1; break

    if wind_mph is not None:
        if wind_mph < 10:   score += 2
        elif wind_mph < 15: score += 1

    def in_p(start, dur):
        end = (start + dur) % 24
        return (start <= now_h < end) if start < end else (now_h >= start or now_h < end)

    for key in ("major1", "major2"):
        if in_p(sol[key], 2): score += 2; break
    else:
        for key in ("minor1", "minor2"):
            if in_p(sol[key], 1): score += 1; break

    label = {5: "Excellent", 4: "Very Good", 3: "Good", 2: "Fair"}.get(min(score, 5), "Poor")
    return min(score, 5), label


# ── Master fetch ──────────────────────────────────────────────────────────────

def fetch_all_data(station_id, lat, lon, target_date=None, met_id=None):
    """Fetch all station data in parallel. Returns a single dict for the UI."""
    if target_date is None:
        target_date = date.today()
    date_str = target_date.strftime("%Y%m%d")
    utc_off  = central_utc_offset(target_date)
    mid      = met_id or station_id

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        f_hourly = ex.submit(_fetch_predictions, station_id, date_str, "h")
        f_hilo   = ex.submit(_fetch_predictions, station_id, date_str, "hilo")
        f_air    = ex.submit(_fetch_obs,             mid,        "air_temperature")
        f_wind   = ex.submit(_fetch_obs,             mid,        "wind")
        f_pres   = ex.submit(_fetch_obs,             mid,        "air_pressure")
        f_ptrend = ex.submit(_fetch_pressure_trend,  mid)
        f_wtemp  = ex.submit(_fetch_obs,             station_id, "water_temperature")
        f_wlev   = ex.submit(_fetch_water_level,     station_id)
        f_nws    = ex.submit(_fetch_nws, lat, lon)

    obs_raw = {
        "air_temperature":  f_air.result(),
        "wind":             f_wind.result(),
        "air_pressure":     f_pres.result(),
        "water_temperature":f_wtemp.result(),
        "water_level":      f_wlev.result(),
    }
    hourly = _parse_hourly(f_hourly.result() or [])
    hilo   = _parse_hilo(f_hilo.result() or [])
    cond   = _parse_conditions(obs_raw)
    cond["pressure_trend"] = f_ptrend.result()
    nws    = _parse_nws(f_nws.result())

    sunrise, sunset, solar_noon = sun_times(target_date, lat, lon, utc_off)
    phase_name, phase_pct, phase_emoji = moon_phase(target_date)
    sol    = solunar_times(target_date, lon, utc_off)
    stars, rating_label = fishing_rating(hilo, cond.get("wind_speed"), sol, target_date)

    return {
        "station_id":  station_id,
        "lat":         lat,
        "lon":         lon,
        "target_date": target_date,
        "is_today":    target_date == date.today(),
        "hourly":      hourly,
        "hilo":        hilo,
        "conditions":  cond,
        "nws":         nws,
        "sun": {
            "sunrise": hhmm(sunrise)      if sunrise      else "N/A",
            "noon":    hhmm(solar_noon)   if solar_noon   else "N/A",
            "sunset":  hhmm(sunset)       if sunset       else "N/A",
            "golden":  hhmm(sunset - 1.0) if sunset       else "N/A",
        },
        "moon": {"phase": phase_name, "emoji": phase_emoji, "pct": phase_pct},
        "solunar": {
            "major1": sol["major1"], "major2": sol["major2"],
            "minor1": sol["minor1"], "minor2": sol["minor2"],
        },
        "fishing": {"stars": stars, "label": rating_label},
    }


# ── Week / date helpers ───────────────────────────────────────────────────────

def week_bounds(anchor, which="this"):
    """Return (monday, sunday) for the week relative to anchor date."""
    monday = anchor - timedelta(days=anchor.weekday())
    if which == "next":
        monday += timedelta(weeks=1)
    elif which == "prev":
        monday -= timedelta(weeks=1)
    return monday, monday + timedelta(days=6)


def fetch_week_hilo(station_id, start_date, end_date):
    """Fetch hi/lo predictions for a multi-day range; returns parsed list."""
    url = (
        "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        f"?begin_date={start_date.strftime('%Y%m%d')}"
        f"&end_date={end_date.strftime('%Y%m%d')}"
        f"&station={station_id}"
        "&product=predictions&datum=MLLW&time_zone=lst_ldt"
        "&interval=hilo&units=english&format=json&application=tides_android"
    )
    data = _get(url, timeout=15)
    return _parse_hilo((data or {}).get("predictions", []))


# ── Location helpers ─────────────────────────────────────────────────────────

def haversine(lat1, lon1, lat2, lon2):
    """Distance in miles between two lat/lon points."""
    R = 3959.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(max(0, min(1, a))))


def get_ip_location():
    """Return (lat, lon, city) via IP geolocation, or (None, None, None)."""
    for url in ("https://ipapi.co/json/", "https://ip-api.com/json/"):
        data = _get(url, timeout=6)
        if not data:
            continue
        lat  = data.get("latitude")  or data.get("lat")
        lon  = data.get("longitude") or data.get("lon")
        city = data.get("city", "your location")
        try:
            return float(lat), float(lon), city
        except (TypeError, ValueError):
            continue
    return None, None, None


def nearest_stations(lat, lon, n=6):
    """Return the n closest NOAA tide-prediction stations to (lat, lon)."""
    data = _get(_STATIONS_URL, timeout=15)
    if not data or "stations" not in data:
        return []
    out = []
    for s in data["stations"]:
        try:
            slat = float(s.get("lat", 0))
            slon = float(s.get("lng", 0))
            state = s.get("state", "")
            name  = s.get("name", "")
            out.append({
                "id":   s["id"],
                "name": f"{name}, {state}" if state else name,
                "lat":  slat,
                "lon":  slon,
                "dist": haversine(lat, lon, slat, slon),
            })
        except (TypeError, ValueError):
            pass
    out.sort(key=lambda x: x["dist"])
    return out[:n]


# ── Favorites ─────────────────────────────────────────────────────────────────

def fav_path():
    if _DATA_DIR:
        d = Path(_DATA_DIR)
    else:
        d = Path.home() / ".config" / "tides"
    try:
        d.mkdir(parents=True, exist_ok=True)
    except OSError:
        d = Path(os.environ.get('TMPDIR', '/tmp'))
    return d / "favorites.json"


def load_favorites():
    try:
        return json.loads(fav_path().read_text())
    except Exception:
        return []


def save_favorites(favs):
    try:
        fav_path().write_text(json.dumps(favs, indent=2))
    except Exception:
        pass


def add_favorite(station):
    favs = load_favorites()
    if any(f["id"] == station["id"] for f in favs):
        return False
    favs.append({"id": station["id"], "name": station["name"],
                 "lat": station["lat"], "lon": station["lon"]})
    save_favorites(favs)
    return True


def remove_favorite(station_id):
    favs = load_favorites()
    new  = [f for f in favs if f["id"] != station_id]
    if len(new) < len(favs):
        save_favorites(new)
        return True
    return False


# ── Settings (theme, etc.) ────────────────────────────────────────────────────

def _settings_path():
    p = fav_path().parent
    return p / "settings.json"


def load_settings():
    try:
        return json.loads(_settings_path().read_text())
    except Exception:
        return {}


def save_settings(updates):
    s = load_settings()
    s.update(updates)
    try:
        _settings_path().write_text(json.dumps(s, indent=2))
    except Exception:
        pass
