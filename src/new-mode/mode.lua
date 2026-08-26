local RunStore = require('run_store')

local SAMPLE_INTERVAL = 1 / 50
local MAX_RECORDING_DURATION = 180

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

local state = {
  status = 'idle',
  message = 'Ready to record a lead run',
  recordingFrames = nil,
  recordingElapsed = 0,
  nextSampleTime = 0,
  pendingRun = nil,
  latestRun = nil,
  runPath = RunStore.path(),
}

local lastLoggedError = nil

local function setError(message)
  state.status = 'error'
  state.message = message
  if lastLoggedError ~= message then
    lastLoggedError = message
    ac.error('[AC Random Lead Runs] ' .. message)
  end
end

local function visibleRun()
  return state.pendingRun or state.latestRun
end

local function sampleCount()
  if state.recordingFrames then return #state.recordingFrames end
  local run = visibleRun()
  return run and #run.frames or 0
end

local function duration()
  if state.recordingFrames then return state.recordingElapsed end
  local run = visibleRun()
  return run and run.duration or 0
end

local function publishState()
  local run = visibleRun()
  ac.store(STORAGE.active, 1)
  ac.store(STORAGE.status, state.status)
  ac.store(STORAGE.message, state.message)
  ac.store(STORAGE.track, ac.getTrackID() or '?')
  ac.store(STORAGE.layout, ac.getTrackLayout() or '-')
  ac.store(STORAGE.car, ac.getCarID(0) or '?')
  ac.store(STORAGE.samples, sampleCount())
  ac.store(STORAGE.duration, duration())
  ac.store(STORAGE.hasPending, state.pendingRun and 1 or 0)
  ac.store(STORAGE.latestRunId, run and run.id or '-')
  ac.store(STORAGE.runVersion, run and run.version or 0)
  ac.store(STORAGE.runPath, state.runPath)
  ac.store(STORAGE.libraryPath, RunStore.directory())
end

local function captureFrame(car, sampleTime)
  local steerLock = math.max(car.steerLock or 0, 1)
  local transform = car.transform
  return {
    sampleTime,
    transform.position.x, transform.position.y, transform.position.z,
    transform.look.x, transform.look.y, transform.look.z,
    transform.up.x, transform.up.y, transform.up.z,
    car.velocity.x, car.velocity.y, car.velocity.z,
    math.clamp(car.steer / steerLock, -1, 1),
    car.gas, car.brake, car.clutch, car.handbrake,
    car.gear, car.rpm,
    car.wheels[0].angularSpeed,
    car.wheels[1].angularSpeed,
    car.wheels[2].angularSpeed,
    car.wheels[3].angularSpeed,
  }
end

local function startRecording()
  local player = ac.getCar(0)
  if not player then
    setError('Player car is not available')
    return
  end
  if ac.getSim().isReplayActive then
    setError('Recording is unavailable while an AC replay is active')
    return
  end
  state.pendingRun = nil
  state.recordingFrames = {captureFrame(player, 0)}
  state.recordingElapsed = 0
  state.nextSampleTime = SAMPLE_INTERVAL
  state.status = 'recording'
  state.message = 'Recording at 50 Hz; drive the lead run, then press Stop recording'
end

local function stopRecording(autoStopped)
  if state.status ~= 'recording' or not state.recordingFrames then return end
  local frames = state.recordingFrames
  state.recordingFrames = nil
  if #frames < 2 then
    setError('Recording is too short; at least two samples are required')
    return
  end
  local recordedDuration = frames[#frames][1]
  state.pendingRun = RunStore.create(frames, recordedDuration)
  state.status = 'review'
  state.message = string.format('%s: %.2f s, %d samples. Keep or Discard it.',
    autoStopped and 'Maximum recording duration reached' or 'Recording stopped', recordedDuration, #frames)
end

local function keepPendingRun()
  if not state.pendingRun then return end
  local saved, saveError, path = RunStore.save(state.pendingRun)
  if not saved then
    setError(saveError)
    return
  end
  state.latestRun = state.pendingRun
  state.pendingRun = nil
  state.runPath = path
  state.status = 'saved'
  state.message = 'Run saved to the library. Restart the localhost server to load it.'
end

local function discardPendingRun()
  if not state.pendingRun then return end
  state.pendingRun = nil
  state.status = 'idle'
  state.message = 'Run discarded; ready to record another lead run'
end

local function updateRecording(dt)
  if state.status ~= 'recording' or not state.recordingFrames then return end
  if ac.getSim().isReplayActive then
    state.recordingFrames = nil
    setError('Recording cancelled because AC replay mode started')
    return
  end
  local player = ac.getCar(0)
  if not player then
    state.recordingFrames = nil
    setError('Player car became unavailable during recording')
    return
  end
  state.recordingElapsed = state.recordingElapsed + dt
  while state.nextSampleTime <= state.recordingElapsed do
    state.recordingFrames[#state.recordingFrames + 1] = captureFrame(player, state.nextSampleTime)
    state.nextSampleTime = state.nextSampleTime + SAMPLE_INTERVAL
  end
  if state.recordingElapsed >= MAX_RECORDING_DURATION then stopRecording(true) end
end

local loadedRun, loadError, loadedPath = RunStore.load()
state.runPath = loadedPath
if loadError then
  setError('Latest run load failed: ' .. loadError)
elseif loadedRun then
  state.latestRun = loadedRun
  state.message = 'Ready to record. Latest run: ' .. tostring(loadedRun.id)
end

function script.update(dt)
  local command = ac.load(STORAGE.command)
  if command ~= nil then ac.store(STORAGE.command, nil) end
  if command == 'record_start' then
    startRecording()
  elseif command == 'record_stop' then
    stopRecording(false)
  elseif command == 'keep' then
    keepPendingRun()
  elseif command == 'discard' then
    discardPendingRun()
  end
  updateRecording(dt)
  publishState()
end

ac.store(STORAGE.command, nil)
publishState()

ac.onRelease(function()
  for _, key in pairs(STORAGE) do ac.store(key, nil) end
end)
