#!/usr/bin/env python3

import json
import os
import sys
import requests
from pyquery import PyQuery

# weather icons
weather_icons = {
    "sunnyDay": "󰖙",
    "clearNight": "󰖔",
    "cloudyFoggyDay": "",
    "cloudyFoggyNight": "",
    "rainyDay": "",
    "rainyNight": "",
    "snowyIcyDay": "",
    "snowyIcyNight": "",
    "severe": "",
    "default": "",
}

# your location
location_id = "ef7f997d4fd571b8c0310ee49f7082b617fa29ae5d07414d2fd31727d3d5febd"
url = f"https://weather.com/en-PH/weather/today/l/{location_id}"

# fetch the page with headers so weather.com gives us the normal page
try:
    resp = requests.get(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
        },
        timeout=10,
    )
    resp.raise_for_status()
except Exception as e:
    # if we can’t even fetch, print something Waybar can show and exit
    out_data = {
        "text": "  N/A",
        "alt": "weather-error",
        "tooltip": f"Error fetching weather: {e}",
        "class": "default",
    }
    print(json.dumps(out_data))
    sys.exit(0)

html_data = PyQuery(resp.text)


def first_text(selector, default=""):
    el = html_data(selector)
    if not el:
        return default
    text = el.eq(0).text()
    return text if text else default


# current temperature
temp = first_text("span[data-testid='TemperatureValue']", "N/A")

# current status phrase
status = first_text("div[data-testid='wxPhrase']", "Unknown")
status = f"{status[:16]}.." if len(status) > 17 else status

# try to detect icon code from the header classes like "CurrentConditions--header--..."
# we make this defensive
status_code = "default"
region_header = html_data("#regionHeader")
if region_header:
    cls = region_header.attr("class") or ""
    # often classes look like: "CurrentConditions--header--something Icon--sunnyDay--something"
    for part in cls.split():
        if part.startswith("Icon--"):
            # e.g. Icon--sunnyDay--31
            bits = part.split("--")
            if len(bits) >= 2:
                status_code = bits[1]
            break

icon = weather_icons.get(status_code, weather_icons["default"])

# feels like
temp_feel = first_text(
    "div[data-testid='FeelsLikeSection'] span[data-testid='TemperatureValue']",
    "N/A",
)
temp_feel_text = f"Feels like {temp_feel}F" if temp_feel != "N/A" else "Feels like N/A"

# min / max
# sometimes the order can change, so we grab all and index defensively
wxdata_temps = html_data("div[data-testid='wxData'] span[data-testid='TemperatureValue']")
temp_max = wxdata_temps.eq(0).text() if wxdata_temps.length >= 1 else "N/A"
temp_min = wxdata_temps.eq(1).text() if wxdata_temps.length >= 2 else "N/A"
temp_min_max = f"  {temp_min}\t\t  {temp_max}"

# wind
wind_raw = first_text("span[data-testid='Wind']", "")
# this element often has multiple lines like "Wind\n6 km/h"
if wind_raw:
    parts = wind_raw.splitlines()
    wind_speed = parts[-1].strip() if parts else wind_raw
else:
    wind_speed = "N/A"
wind_text = f"  {wind_speed}"

# humidity
humidity = first_text("span[data-testid='PercentageValue']", "N/A")
humidity_text = f"  {humidity}"

# visibility
visibility = first_text("span[data-testid='VisibilityValue']", "N/A")
visibility_text = f"  {visibility}"

# AQI (may not exist)
air_quality_index = first_text("text[data-testid='DonutChartValue']", "N/A")

# hourly rain prediction (may not exist or may be multiple)
hourly_section = html_data("section[aria-label='Hourly Forecast']")
prediction_elems = hourly_section("div[data-testid='SegmentPrecipPercentage'] > span")
if prediction_elems.length:
    # join like "10% 20% 0%"
    prediction = " ".join([prediction_elems.eq(i).text() for i in range(prediction_elems.length)])
    prediction = prediction.replace("Chance of Rain", "").strip()
    prediction = f"\n\n (hourly) {prediction}" if prediction else ""
else:
    prediction = ""

# tooltip for Waybar
tooltip_text = str.format(
    "\t\t{}\t\t\n{}\n{}\n{}\n\n{}\n{}\n{}{}",
    f'<span size="xx-large">{temp}F</span>',
    f"<big> {icon}</big>",
    f"<b>{status}</b>",
    f"<small>{temp_feel_text}</small>",
    f"<b>{temp_min_max}</b>",
    f"{wind_text}\t{humidity_text}",
    f"{visibility_text}\tAQI {air_quality_index}",
    f"<i> {prediction}</i>",
)

out_data = {
    "text": f"{icon}  {temp}F",
    "alt": status,
    "tooltip": tooltip_text,
    "class": status_code,
}
print(json.dumps(out_data))

# simple cache text version
simple_weather = (
    f"{icon}  {status}\n"
    f"  {temp}F ({temp_feel_text})\n"
    f"{wind_text} \n"
    f"{humidity_text} \n"
    f"{visibility_text} AQI {air_quality_index}\n"
)

try:
    cache_path = os.path.expanduser("~/.cache")
    os.makedirs(cache_path, exist_ok=True)
    with open(os.path.join(cache_path, ".weather_cache"), "w") as f:
        f.write(simple_weather)
except Exception:
    # don't crash waybar if cache write fails
    pass
