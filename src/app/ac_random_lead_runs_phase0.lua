local STORAGE_PREFIX = '.ac-random-lead-runs.phase1.'
local STORAGE = {
  active = STORAGE_PREFIX .. 'active',
  command = STORAGE_PREFIX .. 'command',
  status = STORAGE_PREFIX .. 'status',
  message = STORAGE_PREFIX .. 'message',
  carsCount = STORAGE_PREFIX .. 'carsCount',
  distance = STORAGE_PREFIX .. 'distance',
  cycles = STORAGE_PREFIX .. 'cycles',
  track = STORAGE_PREFIX .. 'track',
  layout = STORAGE_PREFIX .. 'layout',
  car = STORAGE_PREFIX .. 'car',
  samples = STORAGE_PREFIX .. 'samples',
  duration = STORAGE_PREFIX .. 'duration',
  hasPending = STORAGE_PREFIX .. 'hasPending',
  hasSaved = STORAGE_PREFIX .. 'hasSaved',
  runId = STORAGE_PREFIX .. 'runId',
  runVersion = STORAGE_PREFIX .. 'runVersion',
  runPath = STORAGE_PREFIX .. 'runPath',
  targetSteer = STORAGE_PREFIX .. 'targetSteer',
  actualSteer = STORAGE_PREFIX .. 'actualSteer',
  targetWheel = STORAGE_PREFIX .. 'targetWheel',
  actualWheel = STORAGE_PREFIX .. 'actualWheel',
  targetRPM = STORAGE_PREFIX .. 'targetRPM',
  actualRPM = STORAGE_PREFIX .. 'actualRPM',
  audioStatus = STORAGE_PREFIX .. 'audioStatus',
  heightOffset = STORAGE_PREFIX .. 'heightOffset',
  diagnosticLogPath = STORAGE_PREFIX .. 'diagnosticLogPath',
  nativeAvailable = STORAGE_PREFIX .. 'nativeAvailable',
  nativeStatus = STORAGE_PREFIX .. 'nativeStatus',
  nativeDuration = STORAGE_PREFIX .. 'nativeDuration',
  nativeReplayOffset = STORAGE_PREFIX .. 'nativeReplayOffset',
}

local SERVER_URL = 'http://127.0.0.1:8081/api/random-lead'
local server = {
  connected = false,
  requestInFlight = false,
  commandInFlight = false,
  pollTimer = 0,
  pollSequence = 0,
  status = nil,
  error = 'Connecting to localhost playback server…',
}

local function acceptServerResponse(err, response)
  server.requestInFlight = false
  server.commandInFlight = false
  if err ~= nil then
    server.connected = false
    server.error = tostring(err)
    return
  end
  if response == nil or response.status < 200 or response.status >= 300 then
    server.connected = false
    server.error = response == nil and 'Empty HTTP response' or
      string.format('HTTP %s: %s', tostring(response.status), tostring(response.body))
    return
  end
  local parsedOk, parsed = pcall(JSON.parse, response.body)
  if not parsedOk or type(parsed) ~= 'table' then
    server.connected = false
    server.error = 'Invalid server response: ' .. tostring(parsed)
    return
  end
  server.connected = true
  server.status = parsed
  server.error = ''
end

local function pollServer(force)
  if server.requestInFlight or (not force and server.pollTimer > 0) then return end
  server.requestInFlight = true
  server.pollTimer = 0.5
  server.pollSequence = server.pollSequence + 1
  web.get(SERVER_URL .. '/status?request=' .. tostring(server.pollSequence), acceptServerResponse)
end

local function sendServerCommand(command)
  if server.commandInFlight then return end
  server.commandInFlight = true
  server.requestInFlight = true
  web.post(SERVER_URL .. '/command/' .. command, acceptServerResponse)
end

local function read(key, fallback)
  local value = ac.load(key)
  if value == nil then return fallback end
  return value
end

local function send(command)
  if tonumber(read(STORAGE.active, 0)) == 1 then
    ac.store(STORAGE.command, command)
  end
end

local function fullWidthButton(label, command, enabled)
  if not enabled then ui.pushDisabled() end
  local clicked = ui.button(label, vec2(ui.availableSpaceX(), 38))
  if not enabled then ui.popDisabled() end
  if clicked and enabled then send(command) end
end

local function statusColor(status)
  if status == 'error' then
    return rgbm(1, 0.25, 0.25, 1)
  elseif status == 'recording' then
    return rgbm(1, 0.25, 0.25, 1)
  elseif status == 'running' or status == 'playing' then
    return rgbm(0.25, 0.9, 0.55, 1)
  elseif status == 'native_recording' then
    return rgbm(0.95, 0.35, 1, 1)
  elseif status == 'native_running' then
    return rgbm(0.25, 1, 0.8, 1)
  elseif status == 'review' or status == 'parked' or status == 'setup'
      or status == 'countdown' or status == 'loop_wait' or status == 'waiting_for_player' then
    return rgbm(1, 0.7, 0.2, 1)
  elseif status == 'saved' or status == 'completed' or status == 'native_ready' or status == 'native_completed' then
    return rgbm(0.35, 0.75, 1, 1)
  end
  return rgbm.colors.white
end

local function serverButton(label, command, enabled)
  if not enabled then ui.pushDisabled() end
  local clicked = ui.button(label, vec2(ui.availableSpaceX(), 38))
  if not enabled then ui.popDisabled() end
  if clicked and enabled then sendServerCommand(command) end
end

local function drawServerWindow()
  pollServer(false)
  ui.pushFont(ui.Font.Title)
  ui.text('Random Lead Runs')
  ui.popFont()

  if not server.connected or server.status == nil then
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 0.35, 0.25, 1))
    ui.text('Server controls: disconnected')
    ui.popStyleColor()
    ui.textWrapped(server.error)
    if ui.button('Retry connection', vec2(ui.availableSpaceX(), 38)) then pollServer(true) end
    ui.offsetCursorY(8)
    ui.textWrapped('These controls work on the generated localhost AssettoServer session at port 8081.')
    return
  end

  local status = server.status
  local state = tostring(status.state or 'unknown')
  ui.pushStyleColor(ui.StyleColor.Text, statusColor(state))
  ui.text('Status: ' .. state)
  ui.popStyleColor()
  ui.textWrapped(tostring(status.message or ''))
  ui.text(string.format('Mode: %s   Library: %d run(s)',
    tostring(status.mode or 'current'), tonumber(status.runCount) or 0))
  if state == 'playing' then
    ui.text(string.format('Progress: %.1f / %.1f s',
      tonumber(status.elapsed) or 0, tonumber(status.duration) or 0))
  end

  local runId = status.runId
  if runId ~= nil and tostring(runId) ~= '' then
    ui.textWrapped(string.format('Selected: %s (%s/%s)', tostring(runId),
      tostring(status.selectedIndex or '?'), tostring(status.runCount or '?')))
  elseif status.mode == 'random' then
    ui.text('Selected: hidden until attempt ends')
  end
  if status.lastCompletedRunId ~= nil and tostring(status.lastCompletedRunId) ~= '' then
    ui.textWrapped('Last completed: ' .. tostring(status.lastCompletedRunId))
  end

  local enabled = not server.commandInFlight and (tonumber(status.runCount) or 0) > 0
  ui.offsetCursorY(8)
  serverButton('Play selected run', 'current', enabled)
  serverButton('Play next run', 'next', enabled)
  serverButton('Start random mode', 'random', enabled)
  serverButton('Restart current attempt', 'restart', enabled)
  serverButton('Stop and hide leader', 'stop', enabled and state ~= 'stopped')

  ui.offsetCursorY(8)
  ui.separator()
  ui.text('Diagnostics')
  ui.text(string.format('Leader visible: %s   API: localhost:8081', status.visible and 'yes' or 'no'))
  if ui.button('Copy server status') then
    ac.setClipboardText(string.format(
      'State: %s\nMode: %s\nMessage: %s\nLibrary: %s\nSelected: %s\nLast completed: %s\nProgress: %.2f / %.2f s\nVisible: %s',
      state, tostring(status.mode), tostring(status.message), tostring(status.runCount),
      tostring(status.runId or 'hidden'), tostring(status.lastCompletedRunId or '-'),
      tonumber(status.elapsed) or 0, tonumber(status.duration) or 0, tostring(status.visible)))
  end
end

function script.update(dt)
  server.pollTimer = math.max(0, server.pollTimer - dt)
  if ac.getSim().isOnlineRace then pollServer(false) end
end

function script.windowMain(_)
  if ac.getSim().isOnlineRace then
    drawServerWindow()
    return
  end
  local active = tonumber(read(STORAGE.active, 0)) == 1
  local status = tostring(read(STORAGE.status, active and 'loading' or 'inactive'))
  local message = tostring(read(STORAGE.message,
    active and 'Waiting for mode status' or 'Random Lead Runs New Mode is not active'))
  local hasPending = tonumber(read(STORAGE.hasPending, 0)) == 1
  local hasSaved = tonumber(read(STORAGE.hasSaved, 0)) == 1
  local recording = status == 'recording'
  local running = status == 'running'
  local reviewing = status == 'review'
  local nativeRecording = status == 'native_recording'
  local nativeRunning = status == 'native_running'
  local nativeAvailable = tonumber(read(STORAGE.nativeAvailable, 0)) == 1
  local nativeDuration = tonumber(read(STORAGE.nativeDuration, 0)) or 0
  local busy = recording or running or nativeRecording or nativeRunning or reviewing

  ui.pushFont(ui.Font.Title)
  ui.text('Record one, chase one')
  ui.popFont()

  ui.pushStyleColor(ui.StyleColor.Text, statusColor(status))
  ui.text('Status: ' .. status)
  ui.popStyleColor()
  ui.textWrapped(message)

  if message ~= '' and ui.button('Copy status details') then
    ac.setClipboardText(string.format(
      'Status: %s\n%s\nNative API: %s\nNative capture: %.2f s\nNative replay offset: %.2f s\nSteer target/actual: %.1f / %.1f deg\nWheel FL target/actual: %.1f / %.1f rad/s\nRPM target/actual: %.0f / %.0f\nEngine audio: %s\nHeight offset: %.0f cm\nPlayback log: %s',
      status,
      message,
      tostring(read(STORAGE.nativeStatus, 'unknown')),
      nativeDuration,
      tonumber(read(STORAGE.nativeReplayOffset, 0)) or 0,
      tonumber(read(STORAGE.targetSteer, 0)) or 0,
      tonumber(read(STORAGE.actualSteer, 0)) or 0,
      tonumber(read(STORAGE.targetWheel, 0)) or 0,
      tonumber(read(STORAGE.actualWheel, 0)) or 0,
      tonumber(read(STORAGE.targetRPM, 0)) or 0,
      tonumber(read(STORAGE.actualRPM, 0)) or 0,
      tostring(read(STORAGE.audioStatus, 'unknown')),
      (tonumber(read(STORAGE.heightOffset, 0)) or 0) * 100,
      tostring(read(STORAGE.diagnosticLogPath, '-'))
    ))
  end

  ui.offsetCursorY(8)
  ui.text('1. Record lead')
  fullWidthButton('Start recording', 'record_start', active and not busy and not hasPending)
  fullWidthButton('Stop recording', 'record_stop', active and recording)

  ui.offsetCursorY(6)
  ui.text('2. Review')
  fullWidthButton('Keep run', 'keep', active and hasPending and not busy)
  fullWidthButton('Discard run', 'discard', active and hasPending and not busy)

  ui.offsetCursorY(6)
  ui.text('3. Chase')
  fullWidthButton('Play saved run (physical teleport)', 'play', active and hasSaved and not hasPending and not busy)
  fullWidthButton('Stop and hide leader', 'stop', active and (running or status == 'parked'))

  ui.offsetCursorY(8)
  ui.separator()
  ui.text('Phase 1.5 native replay spike')
  ui.textWrapped('Captures from AC rolling replay. It is session-only for this test and uses stiff collisions.')
  fullWidthButton('Start native capture', 'native_capture_start', active and nativeAvailable and not busy)
  fullWidthButton('Stop native capture', 'native_capture_stop', active and nativeRecording)
  fullWidthButton('Play native capture (stiff)', 'native_play',
    active and nativeAvailable and nativeDuration >= 0.5 and not busy)
  fullWidthButton('Stop and hide native leader', 'native_stop', active and nativeRunning)
  ui.textWrapped('Native API: ' .. tostring(read(STORAGE.nativeStatus, 'unknown')))
  ui.text(string.format('Capture: %.2f s   Rewind: %.2f s', nativeDuration,
    tonumber(read(STORAGE.nativeReplayOffset, 0)) or 0))

  ui.offsetCursorY(6)
  ui.separator()
  ui.text('Phase 0 contact fixture')
  fullWidthButton('Park leader 7 m ahead', 'park', active and not busy)

  ui.offsetCursorY(8)
  ui.separator()
  ui.text('Diagnostics')
  ui.text(string.format('Samples: %s   Duration: %.2f s',
    tostring(read(STORAGE.samples, 0)), tonumber(read(STORAGE.duration, 0)) or 0))
  ui.text(string.format('Pending: %s   Saved: %s', hasPending and 'yes' or 'no', hasSaved and 'yes' or 'no'))
  ui.text(string.format('Cars: %s   Distance: %.1f m   Plays: %s',
    tostring(read(STORAGE.carsCount, 0)), tonumber(read(STORAGE.distance, 0)) or 0,
    tostring(read(STORAGE.cycles, 0))))
  ui.textWrapped(string.format('Run: %s   Format: v%s',
    tostring(read(STORAGE.runId, '-')), tostring(read(STORAGE.runVersion, 0))))
  ui.text(string.format('Steer target/actual: %.1f° / %.1f°',
    tonumber(read(STORAGE.targetSteer, 0)) or 0, tonumber(read(STORAGE.actualSteer, 0)) or 0))
  ui.text(string.format('Wheel FL target/actual: %.1f / %.1f rad/s',
    tonumber(read(STORAGE.targetWheel, 0)) or 0, tonumber(read(STORAGE.actualWheel, 0)) or 0))
  ui.text(string.format('RPM target/actual: %.0f / %.0f',
    tonumber(read(STORAGE.targetRPM, 0)) or 0, tonumber(read(STORAGE.actualRPM, 0)) or 0))
  ui.textWrapped('Engine audio: ' .. tostring(read(STORAGE.audioStatus, 'unknown')))
  ui.textWrapped('Playback log: ' .. tostring(read(STORAGE.diagnosticLogPath, '-')))
  local heightOffsetCm = (tonumber(read(STORAGE.heightOffset, 0)) or 0) * 100
  local changedHeightOffset = ui.slider('Leader height offset', heightOffsetCm, -5, 15, '%.0f cm')
  if changedHeightOffset ~= heightOffsetCm then
    ac.store(STORAGE.heightOffset, changedHeightOffset / 100)
  end
  ui.textWrapped(string.format('Track: %s / %s',
    tostring(read(STORAGE.track, '?')), tostring(read(STORAGE.layout, '-'))))
  ui.textWrapped('Car: ' .. tostring(read(STORAGE.car, '?')))

  local runPath = tostring(read(STORAGE.runPath, ''))
  if runPath ~= '' then
    ui.textWrapped('File: ' .. runPath)
    if ui.button('Copy run file path') then ac.setClipboardText(runPath) end
  end

  if not active then
    ui.offsetCursorY(6)
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 0.65, 0.2, 1))
    ui.textWrapped('Launch the “AC Random Lead Runs — Phase 1” mode, then reopen this app window.')
    ui.popStyleColor()
  end
end
