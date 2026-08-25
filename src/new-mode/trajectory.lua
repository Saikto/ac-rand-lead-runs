local M = {}

local function copyVec3(value)
  return vec3(value.x, value.y, value.z)
end

local function horizontalNormalized(value, fallback)
  local result = vec3(value.x, 0, value.z)
  if result:lengthSquared() < 0.0001 then
    return copyVec3(fallback)
  end
  return result:normalize()
end

---Captures a player-relative reference frame. The virtual leader starts in front
---of the player, so the spike does not depend on hardcoded world coordinates.
---@param car ac.StateCar
---@param leadGap number
---@return table
function M.captureAnchor(car, leadGap)
  local look = horizontalNormalized(car.look, vec3(0, 0, 1))
  local side = horizontalNormalized(car.side, vec3(1, 0, 0))

  return {
    origin = copyVec3(car.position) + look * leadGap,
    look = look,
    side = side,
  }
end

---Returns a deterministic, drift-like S trajectory.
---It is intentionally synthetic: Phase 0 checks the playback backend, not route quality.
---@param anchor table
---@param time number
---@param duration number
---@return vec3 position
---@return vec3 velocity
---@return vec3 bodyLook
---@return number driftAmount
function M.sample(anchor, time, duration)
  local progress = math.saturateN(time / duration)
  local wave = progress * math.pi * 3
  local distance = progress * 72
  local lateral = math.sin(wave) * 3.2

  local forwardSpeed = 72 / duration
  local lateralSpeed = math.cos(wave) * 3.2 * math.pi * 3 / duration

  local position = anchor.origin + anchor.look * distance + anchor.side * lateral
  local velocity = anchor.look * forwardSpeed + anchor.side * lateralSpeed
  local velocityLook = horizontalNormalized(velocity, anchor.look)

  -- Body angle deliberately differs from velocity direction to exercise drift visuals.
  local driftAngle = math.sin(wave - math.pi * 0.35) * math.rad(27)
  local c = math.cos(driftAngle)
  local s = math.sin(driftAngle)
  local velocitySide = vec3(velocityLook.z, 0, -velocityLook.x)
  local bodyLook = horizontalNormalized(velocityLook * c + velocitySide * s, velocityLook)

  return position, velocity, bodyLook, math.abs(math.sin(driftAngle))
end

return M

