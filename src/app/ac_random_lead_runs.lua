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

local visualDiagnostics = {
  attempt = 0,
  active = false,
  sampleTimer = 0,
  flushTimer = 0,
  rows = nil,
  path = '',
  latest = nil,
  error = '',
  suspensionMin = { math.huge, math.huge, math.huge, math.huge },
  suspensionMax = { -math.huge, -math.huge, -math.huge, -math.huge },
}

local DIAGNOSTIC_HEADER = table.concat({
  'server_elapsed_s', 'target_body_ms', 'remote_body_ms',
  'target_fl_rads', 'target_fr_rads', 'target_rl_rads', 'target_rr_rads',
  'sent_fl_rads', 'sent_fr_rads', 'sent_rl_rads', 'sent_rr_rads',
  'remote_fl_rads', 'remote_fr_rads', 'remote_rl_rads', 'remote_rr_rads',
  'speed_diff_fl_ms', 'speed_diff_fr_ms', 'speed_diff_rl_ms', 'speed_diff_rr_ms',
  'slip_ratio_fl', 'slip_ratio_fr', 'slip_ratio_rl', 'slip_ratio_rr',
  'nd_slip_fl', 'nd_slip_fr', 'nd_slip_rl', 'nd_slip_rr',
  'load_k_fl', 'load_k_fr', 'load_k_rl', 'load_k_rr',
  'suspension_fl_m', 'suspension_fr_m', 'suspension_rl_m', 'suspension_rr_m'
}, ',')

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
  server.pollTimer = server.status ~= nil and server.status.state == 'playing' and 0.1 or 0.5
  server.pollSequence = server.pollSequence + 1
  web.get(SERVER_URL .. '/status?request=' .. tostring(server.pollSequence), acceptServerResponse)
end

local function sendServerCommand(command)
  if server.commandInFlight then return end
  server.commandInFlight = true
  server.requestInFlight = true
  web.post(SERVER_URL .. '/command/' .. command, acceptServerResponse)
end

local function numberOrZero(value)
  return tonumber(value) or 0
end

local function statusArrayValue(values, index)
  if type(values) ~= 'table' then return 0 end
  return numberOrZero(values[index])
end

local function resetSuspensionRange()
  visualDiagnostics.suspensionMin = { math.huge, math.huge, math.huge, math.huge }
  visualDiagnostics.suspensionMax = { -math.huge, -math.huge, -math.huge, -math.huge }
end

local function flushVisualLog()
  if visualDiagnostics.rows == nil or visualDiagnostics.path == '' then return end
  local ok, result = pcall(io.save, visualDiagnostics.path, table.concat(visualDiagnostics.rows, '\n') .. '\n')
  if not ok or result == false then
    visualDiagnostics.error = 'Could not write diagnostic log: ' .. tostring(result)
  end
end

local function startVisualLog()
  visualDiagnostics.attempt = visualDiagnostics.attempt + 1
  visualDiagnostics.active = true
  visualDiagnostics.sampleTimer = 0
  visualDiagnostics.flushTimer = 0
  visualDiagnostics.error = ''
  visualDiagnostics.latest = nil
  resetSuspensionRange()
  local folder = ac.getFolder(ac.FolderID.ACDocuments) .. '\\ac-random-lead-runs\\logs'
  visualDiagnostics.path = string.format('%s\\remote-visual-%s-%02d.csv',
    folder, os.date('%Y%m%d-%H%M%S'), visualDiagnostics.attempt)
  io.createFileDir(visualDiagnostics.path)
  visualDiagnostics.rows = { DIAGNOSTIC_HEADER }
  flushVisualLog()
end

local function stopVisualLog()
  if not visualDiagnostics.active then return end
  flushVisualLog()
  visualDiagnostics.active = false
  visualDiagnostics.rows = nil
end

local function collectVisualSample()
  if server.status == nil then return nil end
  local leader = ac.getCar(tonumber(server.status.leaderSessionId) or 1)
  if leader == nil then return nil end
  local sample = {
    elapsed = numberOrZero(server.status.elapsed),
    targetBody = numberOrZero(server.status.targetBodySpeed),
    remoteBody = numberOrZero(leader.speedMs),
    target = {}, sent = {}, angular = {}, speedDifference = {},
    slipRatio = {}, ndSlip = {}, loadK = {}, suspension = {}
  }
  for i = 1, 4 do
    local wheel = leader.wheels[i - 1]
    sample.target[i] = statusArrayValue(server.status.targetWheelSpeed, i)
    sample.sent[i] = statusArrayValue(server.status.sentWheelSpeed, i)
    sample.angular[i] = numberOrZero(wheel.angularSpeed)
    sample.speedDifference[i] = numberOrZero(wheel.speedDifference)
    sample.slipRatio[i] = numberOrZero(wheel.slipRatio)
    sample.ndSlip[i] = numberOrZero(wheel.ndSlip)
    sample.loadK[i] = numberOrZero(wheel.loadK)
    sample.suspension[i] = numberOrZero(wheel.suspensionTravel)
    visualDiagnostics.suspensionMin[i] = math.min(visualDiagnostics.suspensionMin[i], sample.suspension[i])
    visualDiagnostics.suspensionMax[i] = math.max(visualDiagnostics.suspensionMax[i], sample.suspension[i])
  end
  return sample
end

local function appendVisualSample(sample)
  local values = { sample.elapsed, sample.targetBody, sample.remoteBody }
  local groups = { sample.target, sample.sent, sample.angular, sample.speedDifference,
    sample.slipRatio, sample.ndSlip, sample.loadK, sample.suspension }
  for _, group in ipairs(groups) do
    for i = 1, 4 do values[#values + 1] = group[i] end
  end
  local formatted = {}
  for i, value in ipairs(values) do formatted[i] = string.format('%.6f', value) end
  visualDiagnostics.rows[#visualDiagnostics.rows + 1] = table.concat(formatted, ',')
end

local function updateVisualDiagnostics(dt)
  local playing = server.connected and server.status ~= nil and
    numberOrZero(server.status.diagnosticsVersion) >= 1 and server.status.state == 'playing'
  if playing and not visualDiagnostics.active then startVisualLog() end
  if not playing then
    stopVisualLog()
    return
  end

  visualDiagnostics.sampleTimer = visualDiagnostics.sampleTimer - dt
  visualDiagnostics.flushTimer = visualDiagnostics.flushTimer - dt
  if visualDiagnostics.sampleTimer <= 0 then
    visualDiagnostics.sampleTimer = 0.1
    local ok, sample = pcall(collectVisualSample)
    if ok and sample ~= nil then
      visualDiagnostics.latest = sample
      appendVisualSample(sample)
    elseif not ok then
      visualDiagnostics.error = 'Diagnostic sampling failed: ' .. tostring(sample)
    end
  end
  if visualDiagnostics.flushTimer <= 0 then
    visualDiagnostics.flushTimer = 1
    flushVisualLog()
  end
end

local function visualDiagnosticsText()
  if server.connected and server.status ~= nil and numberOrZero(server.status.diagnosticsVersion) < 1 then
    return 'Server plugin is older than the diagnostics UI. Stop it and start it again without -SkipPrepare.'
  end
  local sample = visualDiagnostics.latest
  if sample == nil then return 'No remote-car sample yet.' end
  return string.format(
    'Transport: %s\n' ..
    'Body target/remote: %.2f / %.2f m/s\n' ..
    'Rear wheel recorded: %.1f / %.1f rad/s\n' ..
    'Rear wheel packet: %.1f / %.1f rad/s\n' ..
    'Rear wheel remote: %.1f / %.1f rad/s\n' ..
    'Rear speed difference: %.2f / %.2f m/s\n' ..
    'Rear slip ratio: %.2f / %.2f   nSlip: %.2f / %.2f\n' ..
    'Suspension current FL/FR/RL/RR: %.1f / %.1f / %.1f / %.1f mm\n' ..
    'Suspension range FL/FR/RL/RR: %.1f / %.1f / %.1f / %.1f mm\n' ..
    'Log: %s%s',
    tostring(server.status.transport or 'unknown'), sample.targetBody, sample.remoteBody,
    sample.target[3], sample.target[4], sample.sent[3], sample.sent[4],
    sample.angular[3], sample.angular[4], sample.speedDifference[3], sample.speedDifference[4],
    sample.slipRatio[3], sample.slipRatio[4], sample.ndSlip[3], sample.ndSlip[4],
    sample.suspension[1] * 1000, sample.suspension[2] * 1000,
    sample.suspension[3] * 1000, sample.suspension[4] * 1000,
    (visualDiagnostics.suspensionMax[1] - visualDiagnostics.suspensionMin[1]) * 1000,
    (visualDiagnostics.suspensionMax[2] - visualDiagnostics.suspensionMin[2]) * 1000,
    (visualDiagnostics.suspensionMax[3] - visualDiagnostics.suspensionMin[3]) * 1000,
    (visualDiagnostics.suspensionMax[4] - visualDiagnostics.suspensionMin[4]) * 1000,
    visualDiagnostics.path ~= '' and visualDiagnostics.path or '-',
    visualDiagnostics.error ~= '' and '\nError: ' .. visualDiagnostics.error or '')
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
  ui.offsetCursorY(8)
  ui.separator()
  ui.text('Visual diagnostics')
  ui.textWrapped(visualDiagnosticsText())
  if ui.button('Copy visual diagnostics') then ac.setClipboardText(visualDiagnosticsText()) end
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
  if ac.getSim().isOnlineRace then
    pollServer(false)
    updateVisualDiagnostics(dt)
  else
    stopVisualLog()
  end
end

function script.windowMain(_)
  if ac.getSim().isOnlineRace then drawServerWindow() else drawRecorderWindow() end
end
