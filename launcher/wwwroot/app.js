const state = { catalog: null, settings: null, server: null };
const $ = id => document.getElementById(id);
const fields = ['serverName', 'playerCar', 'playerSkin', 'weather', 'ambientTemperature', 'roadTemperature',
  'sunAngle', 'startDelaySeconds', 'loopDelaySeconds', 'tcpPort', 'httpPort'];

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

function renderRunLibrary() {
  const grid = $('runGrid');
  grid.innerHTML = '';
  $('runCount').textContent = `${state.catalog.runs.length} run${state.catalog.runs.length === 1 ? '' : 's'}`;
  state.catalog.runs.forEach((run, index) => {
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
  if (!state.catalog.runs.length) grid.textContent = 'No valid recordings found.';
}

function renderCars() {
  const select = $('playerCar');
  select.innerHTML = '';
  state.catalog.cars.forEach(car => option(select, car.id, `${car.name}  ·  ${car.id}`));
  select.value = state.settings.playerCar;
  renderSkins();
}

function renderSkins() {
  const car = state.catalog.cars.find(item => item.id === $('playerCar').value);
  const select = $('playerSkin');
  select.innerHTML = '';
  (car?.skins || []).forEach(skin => option(select, skin, skin));
  if (car?.skins.includes(state.settings.playerSkin)) select.value = state.settings.playerSkin;
  else state.settings.playerSkin = select.value;
}

function fillForm() {
  renderCars();
  $('weather').innerHTML = '';
  state.catalog.weather.forEach(weather => option($('weather'), weather, weather));
  fields.forEach(id => { if ($(id) && state.settings[id] !== undefined) $(id).value = state.settings[id]; });
  $('loop').checked = state.settings.loop;
  $('sunAngleValue').textContent = `${state.settings.sunAngle}°`;
}

function readForm() {
  state.settings.serverName = $('serverName').value.trim();
  state.settings.playerCar = $('playerCar').value;
  state.settings.playerSkin = $('playerSkin').value;
  state.settings.weather = $('weather').value;
  ['ambientTemperature', 'roadTemperature', 'tcpPort', 'httpPort'].forEach(id => state.settings[id] = Number.parseInt($(id).value, 10));
  ['sunAngle', 'startDelaySeconds', 'loopDelaySeconds'].forEach(id => state.settings[id] = Number.parseFloat($(id).value));
  state.settings.loop = $('loop').checked;
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
  $('summaryWeather').textContent = `${state.settings.weather} · ${state.settings.ambientTemperature}° / ${state.settings.roadTemperature}°`;
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
$('sunAngle').addEventListener('input', () => { $('sunAngleValue').textContent = `${$('sunAngle').value}°`; readForm(); });
fields.filter(id => !['playerCar', 'playerSkin', 'sunAngle'].includes(id)).forEach(id => $(id).addEventListener('change', readForm));
$('loop').addEventListener('change', readForm);
$('saveButton').addEventListener('click', () => save().catch(error => toast(error.message, true)));
$('launchButton').addEventListener('click', launch);
$('topLaunchButton').addEventListener('click', launch);
$('stopButton').addEventListener('click', stop);
setInterval(pollStatus, 1000);
init();
