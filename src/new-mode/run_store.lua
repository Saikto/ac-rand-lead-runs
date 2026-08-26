local M = {}

local FORMAT_VERSION = 3

local function valueOrDash(value)
  if value == nil or value == '' then
    return '-'
  end
  return tostring(value)
end

local function safeSegment(value)
  return valueOrDash(value):gsub('[^%w%._%-]', '_')
end

local function currentIdentity()
  return {
    track = valueOrDash(ac.getTrackID()),
    layout = valueOrDash(ac.getTrackLayout()),
    car = valueOrDash(ac.getCarID(0)),
  }
end

function M.directory()
  local identity = currentIdentity()
  return string.format(
    '%s\\Assetto Corsa\\ac-random-lead-runs\\runs\\%s\\%s\\%s',
    ac.getFolder(ac.FolderID.Documents),
    safeSegment(identity.track),
    safeSegment(identity.layout),
    safeSegment(identity.car)
  )
end

function M.path()
  return M.directory() .. '\\latest.json'
end

function M.create(frames, duration)
  local identity = currentIdentity()
  return {
    version = FORMAT_VERSION,
    id = 'run-' .. os.date('%Y%m%d-%H%M%S'),
    createdAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    track = identity.track,
    layout = identity.layout,
    car = identity.car,
    sampleRateHz = 50,
    duration = duration,
    frames = frames,
  }
end

function M.validate(run)
  if type(run) ~= 'table' then
    return false, 'Run root is not an object'
  end
  if run.version ~= 1 and run.version ~= 2 and run.version ~= FORMAT_VERSION then
    return false, 'Unsupported run version: ' .. tostring(run.version)
  end

  local identity = currentIdentity()
  if run.track ~= identity.track or run.layout ~= identity.layout or run.car ~= identity.car then
    return false, string.format(
      'Run mismatch: expected %s/%s/%s, got %s/%s/%s',
      identity.track,
      identity.layout,
      identity.car,
      tostring(run.track),
      tostring(run.layout),
      tostring(run.car)
    )
  end
  if type(run.frames) ~= 'table' or #run.frames < 2 then
    return false, 'Run must contain at least two frames'
  end
  if type(run.duration) ~= 'number' or run.duration <= 0 then
    return false, 'Run duration is invalid'
  end
  return true
end

function M.save(run)
  local valid, validationError = M.validate(run)
  if not valid then
    return false, validationError
  end

  local directory = M.directory()
  local baseId = run.id
  local path = directory .. '\\' .. safeSegment(baseId) .. '.json'
  local suffix = 2
  while io.fileExists(path) do
    run.id = string.format('%s-%d', baseId, suffix)
    path = string.format('%s\\%s.json', directory, safeSegment(run.id))
    suffix = suffix + 1
  end
  local encodedOk, encoded = pcall(JSON.stringify, run)
  if not encodedOk then
    return false, 'JSON encoding failed: ' .. tostring(encoded)
  end
  io.createFileDir(path)
  if not io.save(path, encoded, true) then
    return false, 'Could not write run file: ' .. path
  end
  local latestPath = M.path()
  if not io.save(latestPath, encoded, true) then
    return false, 'Run was saved, but latest.json could not be updated: ' .. latestPath
  end
  return true, nil, path
end

function M.load()
  local path = M.path()
  local data = io.load(path)
  if data == nil then
    return nil, nil, path
  end

  local parsedOk, run = pcall(JSON.parse, data)
  if not parsedOk then
    return nil, 'JSON parsing failed: ' .. tostring(run), path
  end
  local valid, validationError = M.validate(run)
  if not valid then
    return nil, validationError, path
  end
  return run, nil, path
end

return M
