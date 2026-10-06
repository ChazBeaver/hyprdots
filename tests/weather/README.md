# Weather compatibility fixtures

`fixtures/reference.json` records the installed Meteobar 0.5.4 executable's
output for synthetic weather, locations, and theme palettes. Its upstream
source is commit `4793dd2b988254110407eeadac61b974f264a708`. It contains no
personal location or network response. The expected data is independent of
the replacement implementation.

Before retiring that executable, 264 comparisons covered all condition icons
(including unknown-code fallback), four icon sets, day/night, both unit
systems, English/German descriptions, and three palettes. The retained
fixtures exercise every icon mapping and representative complete forecasts.

`model.cjs` compares the replacement against those fixtures and tests malformed
input, timezone handling, location selection, and cache isolation.
`runtime.py` runs the actual QML service with a synthetic `curl`, private cache,
and no Meteobar dependency. It covers restart/offline recovery, both IP
providers, request races, missing executables, and invalid responses.

Run `bash tests/weather.sh`, or pass a staged plugin directory as its argument.
These tests need Node.js, Python 3, and the installed Quickshell. They do not
access the network or modify the live shell. A sandbox may deny Quickshell's
unused IPC socket; service assertions still run in the isolated offscreen host.
