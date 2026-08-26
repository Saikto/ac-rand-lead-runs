local STORAGE_PREFIX = '.ac-random-lead-runs.recorder.'
local STORAGE = {
  active = STORAGE_PREFIX .. 'active',
  command = STORAGE_PREFIX .. 'command',
  status = STORAGE_PREFIX .. 'status',
  message = STORAGE_PREFIX .. 'message',
  track = STORAGE_PREFIX .. 'track',
  layout = STORAGE_PREFIX .. 'layout',
  car = STORAGE_PREFIX .. 'car',
  samples = STORAGE_PREFIX .. 'samples',
  duration = STORAGE_PREFIX .. 'duration',
  hasPending = STORAGE_PREFIX .. 'hasPending',
  latestRunId = STORAGE_PREFIX .. 'latestRunId',
  runVersion = STORAGE_PREFIX .. 'runVersion',
  runPath = STORAGE_PREFIX .. 'runPath',
  libraryPath = STORAGE_PREFIX .. 'libraryPath',
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

local function read(key, fallback)
  local value = ac.load(key)
  if value == nil then return fallback end
  return value
end

local function statusColor(status)
  if status == 'error' or status == 'recording' then return rgbm(1, 0.25, 0.25, 1) end
  if status == 'playing' then return rgbm(0.25, 0.9, 0.55, 1) end
  if status == 'review' or status == 'countdown' or status == 'loop_wait'
      or status == 'waiting_for_player' then return rgbm(1, 0.7, 0.2, 1) end
  if status == 'saved' or status == 'completed' then return rgbm(0.35, 0.75, 1, 1) end
  return rgbm.colors.white
end

local function fullWidthButton(label, enabled, callback)
  if not enabled then ui.pushDisabled() end
  local clicked = ui.button(label, vec2(ui.availableSpaceX(), 38))
  if not enabled then ui.popDisabled() end
  if clicked and enabled then callback() end
end

local function sendRecorderCommand(command)
  if tonumber(read(STORAGE.active, 0)) == 1 then ac.store(STORAGE.command, command) end
end

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

local function drawTitle()
  ui.pushFont(ui.Font.Title)
  ui.text('Random Lead Runs')
  ui.popFont()
end

local function drawServerWindow()
  pollServer(false)
  drawTitle()
  if not server.connected or server.status == nil then
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 0.35, 0.25, 1))
    ui.text('Playback server: disconnected')
    ui.popStyleColor()
    ui.textWrapped(server.error)
    fullWidthButton('Retry connection', not server.requestInFlight, function() pollServer(true) end)
    ui.offsetCursorY(8)
    ui.textWrapped('Start the localhost server, then connect to 127.0.0.1:9600.')
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
  if status.runId ~= nil and tostring(status.runId) ~= '' then
    ui.textWrapped(string.format('Selected: %s (%s/%s)', tostring(status.runId),
      tostring(status.selectedIndex or '?'), tostring(status.runCount or '?')))
  elseif status.mode == 'random' then
    ui.text('Selected: hidden until attempt ends')
  end
  if status.lastCompletedRunId ~= nil and tostring(status.lastCompletedRunId) ~= '' then
    ui.textWrapped('Last completed: ' .. tostring(status.lastCompletedRunId))
  end

  local enabled = not server.commandInFlight and (tonumber(status.runCount) or 0) > 0
  ui.offsetCursorY(8)
  fullWidthButton('Play selected run', enabled, function() sendServerCommand('current') end)
  fullWidthButton('Play next run', enabled, function() sendServerCommand('next') end)
  fullWidthButton('Start random mode', enabled, function() sendServerCommand('random') end)
  fullWidthButton('Restart current attempt', enabled, function() sendServerCommand('restart') end)
  fullWidthButton('Stop and hide leader', enabled and state ~= 'stopped', function() sendServerCommand('stop') end)

  ui.offsetCursorY(8)
  ui.separator()
  ui.text(string.format('Leader visible: %s   API: localhost:8081', status.visible and 'yes' or 'no'))
  if ui.button('Copy server status') then
    ac.setClipboardText(string.format(
      'State: %s\nMode: %s\nMessage: %s\nLibrary: %s\nSelected: %s\nLast completed: %s\nProgress: %.2f / %.2f s\nVisible: %s',
      state, tostring(status.mode), tostring(status.message), tostring(status.runCount),
      tostring(status.runId or 'hidden'), tostring(status.lastCompletedRunId or '-'),
      tonumber(status.elapsed) or 0, tonumber(status.duration) or 0, tostring(status.visible)))
  end
end

local function drawRecorderWindow()
  local active = tonumber(read(STORAGE.active, 0)) == 1
  local status = tostring(read(STORAGE.status, active and 'loading' or 'inactive'))
  local message = tostring(read(STORAGE.message,
    active and 'Waiting for recorder status' or 'AC Random Lead Runs — Recorder is not active'))
  local hasPending = tonumber(read(STORAGE.hasPending, 0)) == 1
  local recording = status == 'recording'

  drawTitle()
  ui.pushStyleColor(ui.StyleColor.Text, statusColor(status))
  ui.text('Status: ' .. status)
  ui.popStyleColor()
  ui.textWrapped(message)

  ui.offsetCursorY(8)
  ui.text('Record lead')
  fullWidthButton('Start recording', active and not recording and not hasPending,
    function() sendRecorderCommand('record_start') end)
  fullWidthButton('Stop recording', active and recording,
    function() sendRecorderCommand('record_stop') end)

  ui.offsetCursorY(8)
  ui.text('Review recording')
  fullWidthButton('Keep run', active and hasPending and not recording,
    function() sendRecorderCommand('keep') end)
  fullWidthButton('Discard run', active and hasPending and not recording,
    function() sendRecorderCommand('discard') end)

  ui.offsetCursorY(8)
  ui.separator()
  ui.text(string.format('Samples: %s   Duration: %.2f s',
    tostring(read(STORAGE.samples, 0)), tonumber(read(STORAGE.duration, 0)) or 0))
  ui.textWrapped(string.format('Track: %s / %s',
    tostring(read(STORAGE.track, '?')), tostring(read(STORAGE.layout, '-'))))
  ui.textWrapped('Car: ' .. tostring(read(STORAGE.car, '?')))
  ui.textWrapped(string.format('Run: %s   Format: v%s',
    tostring(read(STORAGE.latestRunId, '-')), tostring(read(STORAGE.runVersion, 0))))

  local runPath = tostring(read(STORAGE.runPath, ''))
  if runPath ~= '' then
    ui.textWrapped('File: ' .. runPath)
    if ui.button('Copy run file path') then ac.setClipboardText(runPath) end
  end
  local libraryPath = tostring(read(STORAGE.libraryPath, ''))
  if libraryPath ~= '' and ui.button('Copy library folder path') then ac.setClipboardText(libraryPath) end

  if message ~= '' and ui.button('Copy status details') then
    ac.setClipboardText(string.format('Status: %s\n%s\nSamples: %s\nDuration: %.2f s\nRun: %s\nFile: %s',
      status, message, tostring(read(STORAGE.samples, 0)), tonumber(read(STORAGE.duration, 0)) or 0,
      tostring(read(STORAGE.latestRunId, '-')), runPath))
  end

  if not active then
    ui.offsetCursorY(6)
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 0.65, 0.2, 1))
    ui.textWrapped('Launch the “AC Random Lead Runs — Recorder” mode, then reopen this app window.')
    ui.popStyleColor()
  end
end

function script.update(dt)
  server.pollTimer = math.max(0, server.pollTimer - dt)
  if ac.getSim().isOnlineRace then pollServer(false) end
end

function script.windowMain(_)
  if ac.getSim().isOnlineRace then drawServerWindow() else drawRecorderWindow() end
end
