#!/usr/bin/env python3
"""Exercise actual QML processes/cache with a synthetic curl and no Meteobar."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone

plugin = Path(sys.argv[1])
tests = Path(__file__).resolve().parent
curl = r'''#!/usr/bin/python3
import json,os,sys,time
from pathlib import Path
from urllib.parse import urlparse,parse_qs
url=sys.argv[-1]; scenario=os.environ['WEATHER_TEST_SCENARIO']
with open(os.environ['WEATHER_TEST_CALLS'],'a') as out: out.write(url+'\n')
if scenario == 'offline': sys.exit(28)
if scenario in ('race','units','queued'): time.sleep(0.25)
if 'ipinfo.io' in url: print('{"loc":"invalid","city":"City"}')
elif 'ipwho.is' in url: print('{"success":true,"latitude":40,"longitude":-74,"city":"Auto City","region":"Example","country_code":"US"}')
elif 'geocoding-api' in url:
 name=parse_qs(urlparse(url).query)['name'][0]
 print(json.dumps({'results':[{'name':name,'latitude':40,'longitude':-74,'admin1':'Example','country_code':'US'}]}))
elif 'api.open-meteo' in url:
 if scenario == 'malformed': print('{broken'); sys.exit(0)
 data=json.loads(Path(os.environ['WEATHER_TEST_DATA']).read_text())
 if 'temperature_unit=celsius' in url: data['current']['temperature_2m']=22.4
 print(json.dumps(data))
else: sys.exit(1)
'''

with tempfile.TemporaryDirectory(prefix='weather-runtime.') as temp:
    root = Path(temp)
    (root/'weather').mkdir()
    for file in (plugin/'omarchy').iterdir():
        if file.suffix == '.js' or file.name in ('WeatherService.qml', 'WeatherRequest.qml'):
            shutil.copy2(file, root/'weather'/file.name)
    shutil.copy2(tests/'Service.qml', root/'shell.qml')
    for folder in ('bin','runtime','cache','config','state'):
        (root/folder).mkdir(mode=0o700)
    (root/'bin/curl').write_text(curl)
    (root/'bin/curl').chmod(0o755)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
               XDG_RUNTIME_DIR=str(root/'runtime'), XDG_CACHE_HOME=str(root/'cache'),
               XDG_CONFIG_HOME=str(root/'config'), XDG_STATE_HOME=str(root/'state'),
               PATH=str(root/'bin')+':/usr/bin', WEATHER_TEST_DATA=str(tests/'fixtures/weather.json'),
               WEATHER_TEST_CALLS=str(root/'calls'))
    def run(scenario):
        (root/'calls').write_text('')
        result = subprocess.run(['quickshell','--path',str(root),'--no-color'],
                                env=dict(env, WEATHER_TEST_SCENARIO=scenario),
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=12)
        marker = 'WEATHER_RESULT '
        lines = [line.split(marker,1)[1] for line in result.stdout.splitlines() if marker in line]
        assert result.returncode == 0 and len(lines) == 1, result.stdout
        assert 'TypeError:' not in result.stdout and 'ReferenceError:' not in result.stdout, result.stdout
        return json.loads(lines[0]), (root/'calls').read_text().splitlines()
    def clear_cache():
        shutil.rmtree(root/'cache/chaz-weather',ignore_errors=True)

    value,calls=run('manual')
    assert value['report']['current']['temperature']==72.3 and len(calls)==2, (value,calls)
    assert len(value['report']['hourly'])==12 and len(value['report']['daily'])==6
    value,calls=run('manual')
    assert not calls and not value['stale'], 'fresh disk cache must survive restart'
    key=json.dumps(['Fixture City','imperial'],separators=(',',':'))
    cache=root/'cache/chaz-weather'/(hashlib.md5(key.encode()).hexdigest()+'.json')
    saved=json.loads(cache.read_text())
    saved['fetchedAt']=(datetime.now(timezone.utc)-timedelta(minutes=2)).isoformat()
    cache.write_text(json.dumps(saved))
    value,calls=run('offline')
    assert value['report']['current']['temperature']==72.3 and value['stale'] and not value['error']
    assert value['report']['cache']['stale_reason']=='fetch_error'
    value,calls=run('manual')
    assert not value['stale'] and not value['error'] and len(calls)==2
    clear_cache(); value,calls=run('auto')
    assert value['report']['location']=='Auto City, Example, US' and len(calls)==3
    clear_cache(); value,calls=run('race')
    assert value['report']['location']=='Second City, Example, US' and len(calls)==3, (value,calls)
    clear_cache(); value,calls=run('units')
    assert value['report']['units']['temperature']=='°C' and value['report']['current']['temperature']==22.4
    clear_cache(); value,calls=run('queued')
    assert len(calls)==2 and not value['error'], 'queued refresh should reuse just-fetched cache'
    clear_cache(); value,calls=run('malformed')
    assert value['report'] is None and value['error']
    clear_cache(); value,calls=run('offline')
    assert value['report'] is None and value['error']
    clear_cache(); cache.parent.mkdir(mode=0o700); cache.write_text('broken')
    value,calls=run('manual')
    assert value['report'] and not value['error']
    # Failed process start must finish too; a private PATH contains mkdir only.
    clear_cache(); (root/'bin/curl').unlink()
    (root/'bin/mkdir').symlink_to('/usr/bin/mkdir')
    env['PATH']=str(root/'bin')
    # Keep the runner discoverable without making curl available.
    (root/'bin/quickshell').symlink_to('/usr/bin/quickshell')
    value,calls=run('manual')
    assert value['report'] is None and value['error']
print('PASS: QML requests, provider fallback, cache/restart/recovery, request races, malformed data and missing curl')
