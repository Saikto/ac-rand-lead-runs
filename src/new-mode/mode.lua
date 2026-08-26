local RunStore = require('run_store')

local SAMPLE_INTERVAL = 1 / 50
local MAX_RECORDING_DURATION = 180
local LEAD_GAP = 7
local LEADER_INDEX = 1

local FRAME = {
  time = 1,
  px = 2, py = 3, pz = 4,
  lx = 5, ly = 6, lz = 7,
  ux = 8, uy = 9, uz = 10,
  vx = 11, vy = 12, vz = 13,
  steer = 14,
  gas = 15,
  brake = 16,
  clutch = 17,
  handbrake = 18,
  gear = 19,
  rpm = 20,
  wheelFL = 21,
  wheelFR = 22,
  wheelRL = 23,
  wheelRR = 24,
}

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

local function getNativeCapability()
  local missing = {}
  if type(ac.setReplayBasedGhost) ~= 'function' then
    missing[#missing + 1] = 'ac.setReplayBasedGhost'
  end
  if type(ac.disableCar) ~= 'function' then
    missing[#missing + 1] = 'ac.disableCar'
  end
  if #missing > 0 then
    return false, 'unavailable: missing ' .. table.concat(missing, ', ')
  end
  return true, 'available: native replay and collision API'
end

local nativeAvailable, nativeInitialStatus = getNativeCapability()

local state = {
  status = 'idle',
  message = 'Ready to record a lead run',
  recordingFrames = nil,
  recordingElapsed = 0,
  nextSampleTime = 0,
  pendingRun = nil,
  savedRun = nil,
  runPath = RunStore.path(),
  playbackElapsed = 0,
  playbackCursor = 1,
  cycles = 0,
  lastDistance = 0,
  lastPlaybackGear = nil,
  targetSteer = 0,
  actualSteer = 0,
  targetWheel = 0,
  actualWheel = 0,
  targetRPM = 0,
  actualRPM = 0,
  audioStatus = 'not initialized',
  diagnosticLogPath = '-',
  diagnosticRows = nil,
  diagnosticNextSample = 0,
  diagnosticNextFlush = 0,
  driveTime = 0,
  nativeCaptureStart = -1,
  nativeCaptureDuration = 0,
  nativePlaybackElapsed = 0,
  nativeReplayOffset = 0,
  nativePlaying = false,
  nativeStatus = nativeInitialStatus,
}

local leaderInitialized = false
local leaderControls = nil
local engineAudio = nil
local lastLoggedError = nil

local function setError(message)
  state.status = 'error'
  state.message = message
  if lastLoggedError ~= message then
    lastLoggedError = message
    ac.error('[AC Random Lead Runs] ' .. message)
  end
end

local function selectedRun()
  return state.pendingRun or state.savedRun
end

local function selectedSampleCount()
  if state.recordingFrames then
    return #state.recordingFrames
  end
  local run = selectedRun()
  return run and #run.frames or 0
end

local function selectedDuration()
  if state.recordingFrames then
    return state.recordingElapsed
  end
  local run = selectedRun()
  return run and run.duration or 0
end

local function publishState()
  local run = selectedRun()
  ac.store(STORAGE.active, 1)
  ac.store(STORAGE.status, state.status)
  ac.store(STORAGE.message, state.message)
  ac.store(STORAGE.carsCount, ac.getSim().carsCount)
  ac.store(STORAGE.distance, state.lastDistance)
  ac.store(STORAGE.cycles, state.cycles)
  ac.store(STORAGE.track, ac.getTrackID() or '?')
  ac.store(STORAGE.layout, ac.getTrackLayout() or '-')
  ac.store(STORAGE.car, ac.getCarID(0) or '?')
  ac.store(STORAGE.samples, selectedSampleCount())
  ac.store(STORAGE.duration, selectedDuration())
  ac.store(STORAGE.hasPending, state.pendingRun and 1 or 0)
  ac.store(STORAGE.hasSaved, state.savedRun and 1 or 0)
  ac.store(STORAGE.runId, run and run.id or '-')
  ac.store(STORAGE.runVersion, run and run.version or 0)
  ac.store(STORAGE.runPath, state.runPath)
  ac.store(STORAGE.targetSteer, state.targetSteer)
  ac.store(STORAGE.actualSteer, state.actualSteer)
  ac.store(STORAGE.targetWheel, state.targetWheel)
  ac.store(STORAGE.actualWheel, state.actualWheel)
  ac.store(STORAGE.targetRPM, state.targetRPM)
  ac.store(STORAGE.actualRPM, state.actualRPM)
  ac.store(STORAGE.audioStatus, state.audioStatus)
  ac.store(STORAGE.diagnosticLogPath, state.diagnosticLogPath)
  ac.store(STORAGE.nativeAvailable, nativeAvailable and 1 or 0)
  ac.store(STORAGE.nativeStatus, state.nativeStatus)
  ac.store(STORAGE.nativeDuration, state.nativeCaptureDuration)
  ac.store(STORAGE.nativeReplayOffset, state.nativeReplayOffset)
end

local function getLeader()
  if ac.getSim().carsCount <= LEADER_INDEX then
    return nil
  end
  return ac.getCar(LEADER_INDEX)
end

local function resetLeaderControls()
  if not leaderControls then return end
  leaderControls.steer = math.huge
  leaderControls.gas = 0
  leaderControls.brake = 0
  leaderControls.handbrake = 0
  leaderControls.clutch = 1
  leaderControls.requestedGearIndex = 0
end

local function ensureEngineAudio()
  if engineAudio ~= nil then
    return engineAudio:isValid()
  end

  local carID = ac.getCarID(0)
  local guidPath = string.format('%s\\%s\\sfx\\GUIDs.txt', ac.getFolder(ac.FolderID.ContentCars), carID)
  local guidData = io.load(guidPath, '')
  local eventName = guidData:match('(event:/cars/[^%s]+/engine_ext)')
  if eventName == nil then
    state.audioStatus = 'engine_ext not found in GUIDs.txt'
    ac.warn('[AC Random Lead Runs] ' .. state.audioStatus .. ': ' .. guidPath)
    return false
  end

  engineAudio = ac.AudioEvent(eventName, true, true)
  if not engineAudio:isValid() then
    state.audioStatus = 'engine_ext event invalid'
    ac.warn('[AC Random Lead Runs] ' .. state.audioStatus .. ': ' .. eventName)
    return false
  end

  engineAudio:setVolumeChannel(ac.AudioChannel.Opponents)
  state.audioStatus = 'ready: ' .. eventName
  ac.log('[AC Random Lead Runs] Engine audio ready: ' .. eventName)
  return true
end

local function updateEngineAudio(position, look, up, velocity, rpm, gas)
  local audioOK, audioError = pcall(function()
    if not ensureEngineAudio() then return end
    engineAudio:setPosition(position, look, up, velocity)
    engineAudio:setParam('rpms', rpm)
    engineAudio:setParam('throttle', gas)
    engineAudio:setParam('load', gas)
    engineAudio:resumeIf(true)
  end)
  if not audioOK then
    state.audioStatus = 'error: ' .. tostring(audioError)
    ac.warn('[AC Random Lead Runs] Engine audio update failed: ' .. tostring(audioError))
  end
end

local function stopEngineAudio()
  if engineAudio and engineAudio:isValid() then
    engineAudio:stop()
  end
end

local function setLeaderActive(active)
  local leader = getLeader()
  if not leader then return end
  ac.setCarActive(LEADER_INDEX, active)
  if leader.physicsAvailable then
    if active then
      physics.setAINoInput(LEADER_INDEX, true, false)
      physics.setEngineStallEnabled(LEADER_INDEX, false)
      leaderControls = leaderControls or ac.overrideCarControls(LEADER_INDEX)
    else
      stopEngineAudio()
      resetLeaderControls()
      physics.overrideSteering(LEADER_INDEX, math.nan)
      physics.setEngineStallEnabled(LEADER_INDEX, true)
    end
  end
  leaderInitialized = true
end

local function requirePhysicalLeader()
  local leader = getLeader()
  if not leader then
    setError('No leader car: add exactly one opponent in Content Manager before starting the session')
    return nil
  end
  if not leader.physicsAvailable then
    setError('Leader car index 1 has no local physics component')
    return nil
  end
  return leader
end

local function hideNativeGhost()
  local hidden, hideError = pcall(function()
    if type(ac.setReplayBasedGhost) == 'function' then
      ac.setReplayBasedGhost(LEADER_INDEX, -1)
    end
    if type(ac.setDriverVisible) == 'function' then
      ac.setDriverVisible(LEADER_INDEX, false)
    end
    if type(ac.disableCar) == 'function' then
      ac.disableCar(LEADER_INDEX, true)
    end
  end)
  state.nativePlaying = false
  state.nativePlaybackElapsed = 0
  if not hidden then
    state.nativeStatus = 'hide failed: ' .. tostring(hideError)
    ac.warn('[AC Random Lead Runs] Native ghost hide failed: ' .. tostring(hideError))
  end
end

local function startNativeCapture()
  if not nativeAvailable then
    setError('Native replay backend is unavailable: ' .. nativeInitialStatus)
    state.nativeStatus = nativeInitialStatus
    return
  end
  if not getLeader() then
    setError('No leader car: add exactly one opponent in Content Manager before starting the session')
    return
  end
  hideNativeGhost()
  setLeaderActive(false)
  state.nativeCaptureStart = state.driveTime
  state.nativeCaptureDuration = 0
  state.nativeReplayOffset = 0
  state.status = 'native_recording'
  state.nativeStatus = 'capturing from the native rolling replay'
  state.message = 'Native capture is running; drive the lead, then press Stop native capture'
  ac.log('[AC Random Lead Runs] Native replay capture started')
end

local function stopNativeCapture()
  if state.status ~= 'native_recording' or state.nativeCaptureStart < 0 then return end
  state.nativeCaptureDuration = state.driveTime - state.nativeCaptureStart
  if state.nativeCaptureDuration < 0.5 then
    state.nativeCaptureStart = -1
    setError('Native capture is too short; record at least 0.5 seconds')
    return
  end
  state.status = 'native_ready'
  state.nativeStatus = string.format('capture ready: %.2f s', state.nativeCaptureDuration)
  state.message = 'Native capture ready; return to its start and press Play native capture'
  ac.log(string.format('[AC Random Lead Runs] Native replay capture stopped: %.3f s', state.nativeCaptureDuration))
end

local function startNativePlayback()
  if not nativeAvailable then
    setError('Native replay backend is unavailable: ' .. nativeInitialStatus)
    state.nativeStatus = nativeInitialStatus
    return
  end
  if state.nativeCaptureStart < 0 or state.nativeCaptureDuration < 0.5 then
    setError('No native capture is available in the current session')
    return
  end
  if not getLeader() then
    setError('No leader car: add exactly one opponent in Content Manager before starting the session')
    return
  end

  hideNativeGhost()
  stopEngineAudio()
  resetLeaderControls()
  state.nativeReplayOffset = state.driveTime - state.nativeCaptureStart
  local started, startError = pcall(function()
    ac.setCarActive(LEADER_INDEX, true)
    physics.overrideSteering(LEADER_INDEX, math.nan)
    physics.setAINoInput(LEADER_INDEX, true, true)
    ac.setReplayBasedGhost(LEADER_INDEX, 0, state.nativeReplayOffset, 'stiff')
    ac.setDriverVisible(LEADER_INDEX, true)
    ac.disableCar(LEADER_INDEX, false)
    setTimeout(function()
      pcall(function() ac.disableCar(LEADER_INDEX, false) end)
    end)
  end)
  if not started then
    hideNativeGhost()
    state.nativeStatus = 'start failed: ' .. tostring(startError)
    setError('Native replay playback failed: ' .. tostring(startError))
    return
  end

  state.nativePlaying = true
  state.nativePlaybackElapsed = 0
  state.status = 'native_running'
  state.nativeStatus = string.format('playing stiff collision mode; rewind %.2f s', state.nativeReplayOffset)
  state.message = string.format('Playing %.2f s native capture with stiff collisions', state.nativeCaptureDuration)
  ac.log(string.format('[AC Random Lead Runs] Native replay playback started: duration %.3f s, offset %.3f s',
    state.nativeCaptureDuration, state.nativeReplayOffset))
end

local function stopNativePlayback(message, status)
  hideNativeGhost()
  state.status = status or (state.nativeCaptureDuration >= 0.5 and 'native_ready' or 'idle')
  state.nativeStatus = state.nativeCaptureDuration >= 0.5
    and string.format('capture ready: %.2f s', state.nativeCaptureDuration)
    or nativeInitialStatus
  state.message = message or 'Native replay leader hidden'
end

local function captureFrame(car, sampleTime)
  local steerLock = math.max(car.steerLock or 0, 1)
  local physicsTransform = car.transform
  return {
    sampleTime,
    physicsTransform.position.x, physicsTransform.position.y, physicsTransform.position.z,
    physicsTransform.look.x, physicsTransform.look.y, physicsTransform.look.z,
    physicsTransform.up.x, physicsTransform.up.y, physicsTransform.up.z,
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
  hideNativeGhost()
  setLeaderActive(false)
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
  local duration = frames[#frames][FRAME.time]
  state.pendingRun = RunStore.create(frames, duration)
  state.status = 'review'
  state.message = string.format('%s: %.2f s, %d samples. Keep or Discard it.',
    autoStopped and 'Maximum recording duration reached' or 'Recording stopped', duration, #frames)
end

local function keepPendingRun()
  if not state.pendingRun then return end
  local saved, saveError, path = RunStore.save(state.pendingRun)
  if not saved then
    setError(saveError)
    return
  end
  state.savedRun = state.pendingRun
  state.pendingRun = nil
  state.runPath = path
  state.status = 'saved'
  state.message = 'Run saved and ready for playback'
end

local function discardPendingRun()
  if not state.pendingRun then return end
  state.pendingRun = nil
  state.status = 'idle'
  state.message = state.savedRun and 'Pending run discarded; saved run is still available' or 'Run discarded'
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function frameVec(frame, x, y, z)
  return vec3(frame[x], frame[y], frame[z])
end

local function interpolatedVec(a, b, x, y, z, alpha)
  return vec3(lerp(a[x], b[x], alpha), lerp(a[y], b[y], alpha), lerp(a[z], b[z], alpha))
end

local function writeDiagnosticLog()
  if not state.diagnosticRows or state.diagnosticLogPath == '-' then return end
  io.createFileDir(state.diagnosticLogPath)
  if not io.save(state.diagnosticLogPath, table.concat(state.diagnosticRows, '\n') .. '\n', true) then
    ac.warn('[AC Random Lead Runs] Could not write playback diagnostics: ' .. state.diagnosticLogPath)
  end
end

local function startDiagnosticLog(run)
  state.diagnosticLogPath = string.format(
    '%s\\Assetto Corsa\\ac-random-lead-runs\\logs\\playback-%s-%02d.csv',
    ac.getFolder(ac.FolderID.Documents),
    os.date('%Y%m%d-%H%M%S'),
    state.cycles + 1
  )
  state.diagnosticRows = {
    'time_s,height_offset_m,position_error_m,steer_target_deg,steer_actual_deg,' ..
    'wheel_fl_target_rad_s,wheel_fl_actual_rad_s,wheel_fr_target_rad_s,wheel_fr_actual_rad_s,' ..
    'wheel_rl_target_rad_s,wheel_rl_actual_rad_s,wheel_rr_target_rad_s,wheel_rr_actual_rad_s,' ..
    'rpm_target,rpm_actual,ride_height_front_m,ride_height_rear_m,ground_distance_m,' ..
    'suspension_fl_m,suspension_fr_m,suspension_rl_m,suspension_rr_m,audio_status'
  }
  state.diagnosticNextSample = 0
  state.diagnosticNextFlush = 0
  writeDiagnosticLog()
  ac.log(string.format('[AC Random Lead Runs] Playback diagnostics started for %s: %s',
    tostring(run.id), state.diagnosticLogPath))
end

local function appendDiagnosticSample(leader, targetPosition, steerDegrees, wheels, rpm)
  if not state.diagnosticRows or state.playbackElapsed < state.diagnosticNextSample then return end
  state.diagnosticNextSample = state.diagnosticNextSample + 0.1
  local heightOffset = tonumber(ac.load(STORAGE.heightOffset)) or 0
  state.diagnosticRows[#state.diagnosticRows + 1] = string.format(
    '%.3f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.1f,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%s',
    state.playbackElapsed,
    heightOffset,
    leader.position:distance(targetPosition),
    steerDegrees,
    leader.steer,
    wheels[1], leader.wheels[0].angularSpeed,
    wheels[2], leader.wheels[1].angularSpeed,
    wheels[3], leader.wheels[2].angularSpeed,
    wheels[4], leader.wheels[3].angularSpeed,
    rpm,
    leader.rpm,
    leader.rideHeight[0],
    leader.rideHeight[1],
    leader.groundDistance,
    leader.wheels[0].suspensionTravel,
    leader.wheels[1].suspensionTravel,
    leader.wheels[2].suspensionTravel,
    leader.wheels[3].suspensionTravel,
    (state.audioStatus:gsub(',', ';'))
  )
  if state.playbackElapsed >= state.diagnosticNextFlush then
    state.diagnosticNextFlush = state.playbackElapsed + 1
    writeDiagnosticLog()
  end
end

local function submitRecordedState(frameA, frameB, alpha)
  local leader = requirePhysicalLeader()
  if not leader then return false end
  local position = interpolatedVec(frameA, frameB, FRAME.px, FRAME.py, FRAME.pz, alpha)
  local look = interpolatedVec(frameA, frameB, FRAME.lx, FRAME.ly, FRAME.lz, alpha)
  if look:lengthSquared() < 0.0001 then
    look = frameVec(frameA, FRAME.lx, FRAME.ly, FRAME.lz)
  end
  look:normalize()
  local up = interpolatedVec(frameA, frameB, FRAME.ux, FRAME.uy, FRAME.uz, alpha)
  if up:lengthSquared() < 0.0001 then up = vec3(0, 1, 0) end
  up:normalize()
  position = position + up * (tonumber(ac.load(STORAGE.heightOffset)) or 0)
  local velocity = interpolatedVec(frameA, frameB, FRAME.vx, FRAME.vy, FRAME.vz, alpha)
  local steer = lerp(frameA[FRAME.steer], frameB[FRAME.steer], alpha)
  local gas = lerp(frameA[FRAME.gas], frameB[FRAME.gas], alpha)
  local brake = lerp(frameA[FRAME.brake], frameB[FRAME.brake], alpha)
  local clutch = lerp(frameA[FRAME.clutch], frameB[FRAME.clutch], alpha)
  local handbrake = lerp(frameA[FRAME.handbrake], frameB[FRAME.handbrake], alpha)
  local gear = alpha < 0.5 and frameA[FRAME.gear] or frameB[FRAME.gear]
  local rpm = lerp(frameA[FRAME.rpm], frameB[FRAME.rpm], alpha)
  local speed = velocity:length()
  local function wheelSpeed(frameIndex, wheelIndex)
    if frameA[frameIndex] ~= nil and frameB[frameIndex] ~= nil then
      return lerp(frameA[frameIndex], frameB[frameIndex], alpha)
    end
    return speed / math.max(leader.wheels[wheelIndex].tyreRadius, 0.1)
  end
  local steerDegrees = steer * math.max(leader.steerLock or 0, 1)
  local wheelFL = wheelSpeed(FRAME.wheelFL, 0)
  local wheelFR = wheelSpeed(FRAME.wheelFR, 1)
  local wheelRL = wheelSpeed(FRAME.wheelRL, 2)
  local wheelRR = wheelSpeed(FRAME.wheelRR, 3)
  state.targetSteer = steerDegrees
  state.targetWheel = wheelFL
  state.targetRPM = rpm

  local submitted, submitError = pcall(function()
    physics.setAINoInput(LEADER_INDEX, true, false)
    -- The physical teleport API uses AC model-space direction, which is opposite to CarState.look.
    physics.setCarPosition(LEADER_INDEX, position, look * -1)
    physics.setCarVelocity(LEADER_INDEX, velocity)
    physics.overrideSteering(LEADER_INDEX, steerDegrees)
    physics.setWheelAngularVelocity(LEADER_INDEX, ac.Wheel.FrontLeft, wheelFL)
    physics.setWheelAngularVelocity(LEADER_INDEX, ac.Wheel.FrontRight, wheelFR)
    physics.setWheelAngularVelocity(LEADER_INDEX, ac.Wheel.RearLeft, wheelRL)
    physics.setWheelAngularVelocity(LEADER_INDEX, ac.Wheel.RearRight, wheelRR)
    physics.setEngineRPM(LEADER_INDEX, rpm)
    if state.lastPlaybackGear ~= gear then
      physics.engageGear(LEADER_INDEX, gear)
      state.lastPlaybackGear = gear
    end
    if leaderControls then
      leaderControls.steer = steer
      leaderControls.gas = gas
      leaderControls.brake = brake
      leaderControls.clutch = clutch
      leaderControls.handbrake = handbrake
      leaderControls.requestedGearIndex = gear
    end
  end)
  if not submitted then
    setError('Recorded leader state update failed: ' .. tostring(submitError))
    setLeaderActive(false)
    return false
  end
  state.actualSteer = leader.steer
  state.actualWheel = leader.wheels[0].angularSpeed
  state.actualRPM = leader.rpm
  updateEngineAudio(position, look, up, velocity, rpm, gas)
  appendDiagnosticSample(leader, position, steerDegrees, {wheelFL, wheelFR, wheelRL, wheelRR}, rpm)
  local player = ac.getCar(0)
  state.lastDistance = player and player.position:distance(position) or 0
  return true
end

local function startPlayback()
  local run = state.savedRun
  if not run then
    setError('No saved run for the current track, layout and car')
    return
  end
  if not requirePhysicalLeader() then return end
  hideNativeGhost()
  state.playbackElapsed = 0
  state.playbackCursor = 1
  state.lastPlaybackGear = nil
  state.status = 'running'
  state.message = 'Playing saved run: ' .. tostring(run.id)
  startDiagnosticLog(run)
  setLeaderActive(true)
end

local function stopLeader(message, status)
  writeDiagnosticLog()
  if state.diagnosticRows then
    ac.log('[AC Random Lead Runs] Playback diagnostics saved: ' .. state.diagnosticLogPath)
  end
  state.diagnosticRows = nil
  hideNativeGhost()
  setLeaderActive(false)
  state.playbackElapsed = 0
  state.playbackCursor = 1
  state.lastPlaybackGear = nil
  state.status = status or 'idle'
  state.message = message or 'Leader hidden'
end

local function parkLeader()
  local leader = requirePhysicalLeader()
  local player = ac.getCar(0)
  if not leader or not player then return end
  hideNativeGhost()
  local position = player.position + player.look * LEAD_GAP
  setLeaderActive(true)
  local ok, parkError = pcall(function()
    physics.setCarPosition(LEADER_INDEX, position, player.look * -1)
    physics.setCarVelocity(LEADER_INDEX, vec3())
  end)
  if not ok then
    setError('Parking leader failed: ' .. tostring(parkError))
    return
  end
  state.status = 'parked'
  state.message = 'Leader parked 7 m ahead for contact testing'
end

local function updateRecording(dt)
  if state.status ~= 'recording' or not state.recordingFrames then return end
  state.recordingElapsed = state.recordingElapsed + dt
  local player = ac.getCar(0)
  if not player then
    setError('Player car became unavailable during recording')
    state.recordingFrames = nil
    return
  end
  while state.nextSampleTime <= state.recordingElapsed do
    state.recordingFrames[#state.recordingFrames + 1] = captureFrame(player, state.nextSampleTime)
    state.nextSampleTime = state.nextSampleTime + SAMPLE_INTERVAL
  end
  if state.recordingElapsed >= MAX_RECORDING_DURATION then
    stopRecording(true)
  end
end

local function updatePlayback(dt)
  if state.status ~= 'running' or not state.savedRun then return end
  local run = state.savedRun
  state.playbackElapsed = state.playbackElapsed + dt
  if state.playbackElapsed >= run.duration then
    state.cycles = state.cycles + 1
    stopLeader('Playback completed: ' .. tostring(run.id), 'completed')
    return
  end
  while state.playbackCursor < #run.frames - 1
      and run.frames[state.playbackCursor + 1][FRAME.time] <= state.playbackElapsed do
    state.playbackCursor = state.playbackCursor + 1
  end
  local frameA = run.frames[state.playbackCursor]
  local frameB = run.frames[math.min(state.playbackCursor + 1, #run.frames)]
  local interval = math.max(frameB[FRAME.time] - frameA[FRAME.time], 0.0001)
  local alpha = math.clamp((state.playbackElapsed - frameA[FRAME.time]) / interval, 0, 1)
  submitRecordedState(frameA, frameB, alpha)
end

local function updateNativePlayback(dt)
  if not state.nativePlaying or state.status ~= 'native_running' then return end
  state.nativePlaybackElapsed = state.nativePlaybackElapsed + dt
  local leader = getLeader()
  local player = ac.getCar(0)
  if leader and player then
    state.lastDistance = player.position:distance(leader.position)
  end
  if state.nativePlaybackElapsed >= state.nativeCaptureDuration then
    state.cycles = state.cycles + 1
    stopNativePlayback('Native replay playback completed', 'native_completed')
  end
end

local loadedRun, loadError, loadedPath = RunStore.load()
state.runPath = loadedPath
if loadError then
  setError('Saved run load failed: ' .. loadError)
elseif loadedRun then
  state.savedRun = loadedRun
  state.status = 'saved'
  state.message = 'Saved run loaded: ' .. tostring(loadedRun.id)
end

function script.update(dt)
  if not ac.getSim().isReplayActive then
    state.driveTime = state.driveTime + dt
  end
  if not leaderInitialized and getLeader() then setLeaderActive(false) end
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
  elseif command == 'play' then
    startPlayback()
  elseif command == 'native_capture_start' then
    startNativeCapture()
  elseif command == 'native_capture_stop' then
    stopNativeCapture()
  elseif command == 'native_play' then
    startNativePlayback()
  elseif command == 'park' then
    parkLeader()
  elseif command == 'stop' then
    stopLeader()
  elseif command == 'native_stop' then
    stopNativePlayback()
  end
  updateRecording(dt)
  updatePlayback(dt)
  updateNativePlayback(dt)
  publishState()
end

ac.store(STORAGE.command, nil)
if ac.load(STORAGE.heightOffset) == nil then ac.store(STORAGE.heightOffset, 0) end
if not getLeader() then
  state.status = 'setup'
  state.message = 'Add exactly one opponent in Content Manager, then start a new session'
end
publishState()

if type(ac.onReplay) == 'function' then
  ac.onReplay(function(event)
    if state.nativePlaying then
      stopNativePlayback('Native replay stopped because AC replay mode changed')
    else
      hideNativeGhost()
    end
    if event ~= 'stop' then
      pcall(function() ac.disableCar(LEADER_INDEX, false) end)
    end
  end)
else
  ac.warn('[AC Random Lead Runs] ac.onReplay is unavailable; native playback cannot react to replay mode changes')
end

ac.onRelease(function()
  writeDiagnosticLog()
  hideNativeGhost()
  setLeaderActive(false)
  if engineAudio then engineAudio:dispose() end
  for name, key in pairs(STORAGE) do
    if name ~= 'heightOffset' then ac.store(key, nil) end
  end
end)
