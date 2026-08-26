const state = { catalog: null, settings: null, server: null };
const $ = id => document.getElementById(id);
const fields = ['serverName', 'playerCar', 'playerSkin', 'weather', 'ambientTemperature', 'roadTemperatureDelta',
  'timeOfDay', 'timeMultiplier', 'windSpeed', 'windDirection', 'trackGrip', 'tractionControlAllowed', 'absAllowed',
  'damageMultiplier', 'fuelRate', 'tyreWearRate', 'startDelaySeconds', 'loopDelaySeconds', 'tcpPort', 'httpPort'];

async function api(path, options) {
  const response = await fetch(path, options);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
  return body;
}

function toast(message, error = false) {
  const element = $('toast');
  element.textContent = message;
  element.className = `toast show${error ? ' error' : ''}`;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => element.className = 'toast', 3200);
}

function option(select, value, label) {
  const element = document.createElement('option');
  element.value = value;
  element.textContent = label;
  select.appendChild(element);
}

function matchesQuery(text, query) {
  const haystack = text.toLowerCase();
  return query.trim().toLowerCase().split(/\s+/).filter(Boolean).every(token => haystack.includes(token));
}

function renderRunLibrary() {
  const grid = $('runGrid');
  grid.innerHTML = '';
  const query = $('runSearch').value;
  const runs = state.catalog.runs.filter(run =>
    matchesQuery([run.id, run.trackName, run.track, run.layout, run.carName, run.car].join(' '), query));
  $('runCount').textContent = query ? `${runs.length} / ${state.catalog.runs.length} runs` : `${runs.length} run${runs.length === 1 ? '' : 's'}`;
  runs.forEach((run, index) => {
    const card = document.createElement('button');
    card.className = `run-card${run.path === state.settings.runFile ? ' selected' : ''}`;
    const ordinal = document.createElement('span'); ordinal.className = 'index'; ordinal.textContent = `RUN ${String(index + 1).padStart(2, '0')}`;
    const title = document.createElement('h3'); title.textContent = run.trackName;
    const car = document.createElement('p'); car.textContent = `Leader · ${run.carName}`;
    const meta = document.createElement('div'); meta.className = 'run-meta';
    const id = document.createElement('span'); id.textContent = run.id;
    const duration = document.createElement('span'); duration.textContent = `${run.duration.toFixed(1)} s`;
    meta.append(id, duration); card.append(ordinal, title, car, meta);
    card.addEventListener('click', () => { state.settings.runFile = run.path; renderRunLibrary(); renderSummary(); });
    grid.appendChild(card);
  });
  if (!runs.length) grid.textContent = state.catalog.runs.length ? 'No runs match this filter.' : 'No valid recordings found.';
}

function renderCars(filter = '') {
  const select = $('playerCar');
  const selected = state.settings.playerCar;
  select.innerHTML = '';
  const query = filter.trim();
  state.catalog.cars.filter(car => matchesQuery(`${car.name} ${car.id}`, query))
    .forEach(car => option(select, car.id, `${car.name}  ·  ${car.id}`));
  if ([...select.options].some(item => item.value.toLowerCase() === selected.toLowerCase())) select.value = selected;
  if (!select.value && select.options.length) select.selectedIndex = 0;
  renderSkins();
}

function renderSkins(filter = '') {
  const car = state.catalog.cars.find(item => item.id === $('playerCar').value);
  const select = $('playerSkin');
  const selected = state.settings.playerSkin;
  select.innerHTML = '';
  const query = filter.trim();
  (car?.skins || []).filter(skin => matchesQuery(skin, query)).forEach(skin => option(select, skin, skin));
  if ([...select.options].some(item => item.value.toLowerCase() === selected.toLowerCase())) select.value = selected;
  if (!select.value && select.options.length) select.selectedIndex = 0;
}

function renderWeather(filter = '') {
  const select = $('weather');
  const selected = state.settings.weather;
  select.innerHTML = '';
  const query = filter.trim();
  state.catalog.weather.filter(weather => matchesQuery(weather, query)).forEach(weather => option(select, weather, weather));
  if ([...select.options].some(item => item.value.toLowerCase() === selected.toLowerCase())) select.value = selected;
  if (!select.value && select.options.length) select.selectedIndex = 0;
}

function fillForm() {
  renderCars();
  renderWeather();
  fields.forEach(id => { if ($(id) && state.settings[id] !== undefined) $(id).value = state.settings[id]; });
  ['loop', 'stabilityAllowed', 'autoClutchAllowed', 'tyreBlanketsAllowed'].forEach(id => $(id).checked = state.settings[id]);
}

function readForm() {
  state.settings.serverName = $('serverName').value.trim();
  state.settings.playerCar = $('playerCar').value;
  state.settings.playerSkin = $('playerSkin').value;
  state.settings.weather = $('weather').value;
  ['ambientTemperature', 'roadTemperatureDelta', 'windSpeed', 'windDirection', 'trackGrip', 'tractionControlAllowed',
    'absAllowed', 'damageMultiplier', 'fuelRate', 'tyreWearRate', 'tcpPort', 'httpPort'].forEach(id => state.settings[id] = Number.parseInt($(id).value, 10));
  ['timeMultiplier', 'startDelaySeconds', 'loopDelaySeconds'].forEach(id => state.settings[id] = Number.parseFloat($(id).value));
  state.settings.timeOfDay = $('timeOfDay').value;
  ['loop', 'stabilityAllowed', 'autoClutchAllowed', 'tyreBlanketsAllowed'].forEach(id => state.settings[id] = $(id).checked);
  renderSummary();
  return state.settings;
}

function selectedRun() { return state.catalog?.runs.find(run => run.path === state.settings.runFile); }
function selectedCar() { return state.catalog?.cars.find(car => car.id.toLowerCase() === state.settings.playerCar.toLowerCase()); }

function renderSummary() {
  if (!state.catalog || !state.settings) return;
  const run = selectedRun();
  const car = selectedCar();
  $('launchTrack').textContent = run?.trackName || 'Select a run';
  $('launchRun').textContent = run ? `${run.id} · ${run.duration.toFixed(1)} s · leader ${run.carName}` : 'The selected run will appear here.';
  $('summaryCar').textContent = `${car?.name || state.settings.playerCar} · ${state.settings.playerSkin}`;
  const road = state.settings.ambientTemperature + state.settings.roadTemperatureDelta;
  $('summaryWeather').textContent = `${state.settings.weather} · ${state.settings.timeOfDay} · air ${state.settings.ambientTemperature}° · road ${road}°`;
  $('summaryPlayback').textContent = state.settings.loop ? `Loop · ${state.settings.startDelaySeconds}s start · ${state.settings.loopDelaySeconds}s repeat` : 'Single attempt';
  $('summaryAddress').textContent = `127.0.0.1:${state.settings.tcpPort}`;
  $('sidebarAddress').textContent = `127.0.0.1:${state.settings.tcpPort}`;
}

function renderServerStatus(status) {
  state.server = status;
  const label = status.state.charAt(0).toUpperCase() + status.state.slice(1);
  $('sidebarState').textContent = label;
  $('consoleState').textContent = label;
  [$('sidebarDot'), $('consoleDot')].forEach(dot => dot.className = `dot ${status.state}`);
  const log = status.log?.length ? status.log.join('\n') : 'Launcher is ready.';
  if ($('serverLog').textContent !== log) { $('serverLog').textContent = log; $('serverLog').scrollTop = $('serverLog').scrollHeight; }
  $('launchButton').disabled = status.running;
  $('topLaunchButton').disabled = status.running;
  $('stopButton').disabled = !status.running;
  $('connectButton').href = status.connectUrl;
  $('connectButton').classList.toggle('disabled', !status.ready);
}

async function save() {
  readForm();
  await api('/api/settings', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(state.settings) });
  toast('Session profile saved');
}

async function launch() {
  try {
    readForm();
    const status = await api('/api/server/start', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(state.settings) });
    renderServerStatus(status); switchPage('launch'); toast('Server preparation started');
  } catch (error) { toast(error.message, true); }
}

async function stop() {
  try { renderServerStatus(await api('/api/server/stop', { method: 'POST' })); toast('Server stopped'); }
  catch (error) { toast(error.message, true); }
}

function switchPage(page) {
  document.querySelectorAll('.nav').forEach(nav => nav.classList.toggle('active', nav.dataset.page === page));
  document.querySelectorAll('.page').forEach(section => section.classList.toggle('active', section.id === `page-${page}`));
  $('pageTitle').textContent = { library: 'Run library', session: 'Session setup', launch: 'Launch & status' }[page];
  if (page === 'launch') { readForm(); renderSummary(); }
}

async function pollStatus() {
  try { renderServerStatus(await api('/api/server/status')); } catch { }
}

async function init() {
  try {
    [state.catalog, state.settings] = await Promise.all([api('/api/catalog'), api('/api/settings')]);
    renderRunLibrary(); fillForm(); renderSummary(); await pollStatus();
  } catch (error) { toast(`Launcher initialization failed: ${error.message}`, true); }
}

document.querySelectorAll('.nav').forEach(nav => nav.addEventListener('click', () => switchPage(nav.dataset.page)));
$('playerCar').addEventListener('change', () => { state.settings.playerCar = $('playerCar').value; state.settings.playerSkin = ''; renderSkins(); readForm(); });
$('playerSkin').addEventListener('change', readForm);
$('runSearch').addEventListener('input', renderRunLibrary);
$('playerCarSearch').addEventListener('input', event => renderCars(event.target.value));
$('playerSkinSearch').addEventListener('input', event => renderSkins(event.target.value));
$('weatherSearch').addEventListener('input', event => renderWeather(event.target.value));
fields.filter(id => !['playerCar', 'playerSkin'].includes(id)).forEach(id => $(id).addEventListener('change', readForm));
['loop', 'stabilityAllowed', 'autoClutchAllowed', 'tyreBlanketsAllowed'].forEach(id => $(id).addEventListener('change', readForm));
$('saveButton').addEventListener('click', () => save().catch(error => toast(error.message, true)));
$('launchButton').addEventListener('click', launch);
$('topLaunchButton').addEventListener('click', launch);
$('stopButton').addEventListener('click', stop);
setInterval(pollStatus, 1000);
init();
