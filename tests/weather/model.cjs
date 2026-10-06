const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const plugin = process.argv[2];
const M = require(path.join(plugin, 'omarchy/Model.js'));
const C = require(path.join(plugin, 'omarchy/Conditions.js'));
const P = require(path.join(plugin, 'omarchy/Palette.js'));
const reference = require('./fixtures/reference.json');
for (const b of reference.baselines) {
  const actual = M.normalize(b.entry, b.units, b.icons, b.language, P.palette(b.toml, ''), C.condition);
  for (const field of ['current', 'hourly', 'daily', 'palette', 'units', 'location', 'location_short', 'cache'])
    assert.deepEqual(actual[field], b.expected[field], field);
}
for (const b of reference.icons)
  assert.deepEqual(C.condition(b.code, b.day, b.icons, 'en'), {icon: b.icon, description: b.description, condition: b.condition});
const clone = value => JSON.parse(JSON.stringify(value));
const base = reference.baselines[0];
const entry = clone(base.entry);
const render = e => M.normalize(e, base.units, base.icons, base.language, P.palette(base.toml, ''), C.condition);
assert.equal(render(entry).hourly[0].time, '2026-10-05T15:00');
assert.equal(render(entry).hourly.length, 12);
assert.equal(render(entry).daily.length, 6);
entry.weather.current.time = '2026-10-06T00:15';
assert.equal(render(entry).hourly[0].time, '2026-10-06T00:00');
delete entry.weather.current.apparent_temperature;
assert.equal(render(entry).current.feels_like, null);
delete entry.weather.hourly.precipitation_probability;
assert.equal(render(entry).hourly[0].precip_pct, null);
entry.weather.hourly.temperature_2m.pop();
assert.throws(() => render(entry), /mismatched/);
assert.throws(() => M.parse('{broken'));
assert.throws(() => M.parse('{"error":true}'));
assert.throws(() => M.parse(' '.repeat(1048577)), /size limit/);
assert.throws(() => M.validateWeather({current: {temperature_2m: null}}));
assert.equal(M.cached(JSON.stringify(base.entry), 'another location'), null);
assert.equal(M.cached('broken', base.entry.key), null);
assert.equal(M.fresh({fetchedAt: '2026-10-05T00:00:00Z'}, Date.parse('2026-10-05T00:00:59Z')), true);
assert.equal(M.fresh({fetchedAt: '2026-10-05T00:00:00Z'}, Date.parse('2026-10-05T00:01:00Z')), false);
assert.equal(M.fresh({fetchedAt: '2026-10-06T00:00:00Z'}, Date.parse('2026-10-05T00:00:00Z')), false);
assert.equal(M.requestKey('auto','imperial'), M.requestKey('','imperial'));
assert.notEqual(M.requestKey('','imperial'), M.requestKey('','metric'));
const data = {results: [
  {name:'Springfield',latitude:1,longitude:2,admin1:'Wrong',country_code:'CA'},
  {name:'Springfield',latitude:3,longitude:4,admin1:'Illinois',country_code:'US'}
]};
assert.equal(M.resolveLocation(data,'geocode','Springfield, Illinois, US').latitude,3);
assert.equal(M.resolveLocation(data,'geocode','Springfield, Missing').latitude,1);
assert.throws(() => M.resolveLocation({loc:'91,180',city:'Invalid'},'ipinfo',''));
assert.throws(() => M.resolveLocation({loc:',',city:'Invalid'},'ipinfo',''));
assert.equal(M.resolveLocation({loc:'40,-74',city:' City ',region:'State',country:'US'},'ipinfo','').name,'City, State, US');
assert.equal(M.resolveLocation({success:true,latitude:40,longitude:-74,city:'City'},'ipwho','').short,'City');
assert.throws(() => M.resolveLocation({success:false},'ipwho',''));
assert.equal(M.language(['C','de_DE.UTF-8']), 'en');
assert.equal(M.language(['','de_DE.UTF-8']), 'de');
for (const units of ['imperial','metric']) {
  const url = new URL(M.forecastUrl({latitude:40,longitude:-74},units));
  assert.equal(url.searchParams.get('temperature_unit'),units === 'imperial' ? 'fahrenheit':'celsius');
  assert.equal(url.searchParams.get('wind_speed_unit'),units === 'imperial' ? 'mph':'kmh');
  assert.equal(url.searchParams.get('forecast_days'),'6');
}
// The new runtime must not shell out to any weather backend or package helper.
for (const file of ['WeatherRequest.qml','WeatherService.qml','Panel.qml']) {
  const source=fs.readFileSync(path.join(plugin,'omarchy',file),'utf8');
  assert.doesNotMatch(source, /\["(?:meteobar|yay|paru)"/);
}
console.log('PASS: stored Meteobar 0.5.4 reference, all condition icons, palette, timezone, cache and input validation');
