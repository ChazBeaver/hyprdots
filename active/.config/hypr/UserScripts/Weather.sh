#!/usr/bin/env python3
import os
import json
import requests

# set your coordinates here
LAT = 27.95   # Tampa-ish, change to yours
LON = -82.46  # Tampa-ish, change to yours

URL = (
    "https://api.open-meteo.com/v1/forecast"
    f"?latitude={LAT}&longitude={LON}"
    "&current_weather=true"
    "&hourly=temperature_2m,relativehumidity_2m,apparent_temperature"
)

CACHE_DIR = os.path.expanduser("~/.cache")
CACHE_FILE = os.path.join(CACHE_DIR, ".weather_cache")

def c_to_f(c):
    return (c * 9 / 5) + 32

def main():
    try:
        r = requests.get(URL, timeout=6)
        data = r.json()
    except Exception as e:
        # fallback: keep old cache content if any
        # or write a simple error line
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(CACHE_FILE, "w") as f:
            f.write(f"  Weather\nError: {e}\n")
        return

    current = data.get("current_weather", {})
    temp_c = current.get("temperature")
    wind = current.get("windspeed", "N/A")
    code = current.get("weathercode", None)

    # basic icon mapping (open-meteo codes)
    icon = ""
    if code in (0,):  # clear
        icon = "󰖙"
    elif code in (1, 2):  # mainly clear / partly cloudy
        icon = ""
    elif code in (3,):  # overcast
        icon = ""
    elif code in (51, 53, 55, 61, 63, 65, 80, 81, 82):  # rain/drizzle
        icon = ""
    elif code in (71, 73, 75, 77):  # snow
        icon = ""
    elif code in (95, 96, 99):
        icon = ""

    if temp_c is not None:
        temp_f = round(c_to_f(temp_c))
        temp_line = f"  {temp_f}F"
    else:
        temp_line = "  N/A"

    wind_line = f"  {wind} km/h"
    header = f"{icon}  Weather"

    # write in the same style your hyprlock label is ready to show
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(CACHE_FILE, "w") as f:
        f.write(f"{header}\n{temp_line}\n{wind_line}\n")

if __name__ == "__main__":
    main()
