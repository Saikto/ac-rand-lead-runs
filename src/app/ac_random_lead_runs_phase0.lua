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
  elseif status == 'running' then
    return rgbm(0.25, 0.9, 0.55, 1)
  elseif status == 'native_recording' then
    return rgbm(0.95, 0.35, 1, 1)
  elseif status == 'native_running' then
    return rgbm(0.25, 1, 0.8, 1)
  elseif status == 'review' or status == 'parked' or status == 'setup' then
    return rgbm(1, 0.7, 0.2, 1)
  elseif status == 'saved' or status == 'completed' or status == 'native_ready' or status == 'native_completed' then
    return rgbm(0.35, 0.75, 1, 1)
  end
  return rgbm.colors.white
end

function script.windowMain(_)
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
