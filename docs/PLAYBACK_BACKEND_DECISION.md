# Playback backend decision — native replay car instead of physical teleport

Status: proposed pivot after Phase 1 diagnostics  
Date: 2026-08-25

## Decision

Do not continue polishing the per-frame `physics.setCarPosition()` backend as the production playback path. Keep it only as a collision/data-lifecycle reference.

The next experiment must use CSP’s native replay-car pipeline, starting with `ac.setReplayBasedGhost()` and the official `Revenant` mode pattern. If persistent saved runs cannot be loaded into that pipeline, use a local fake AC server/remote-car backend, following the architecture proven by Virtual Steward. Do not build a custom KN5 renderer or input-replay controller before those two native paths are exhausted.

## Evidence from the 2026-08-25 A/B test

Four 19-second playbacks were logged with requested height offsets of 0, 5, 10 and 15 cm.

| Measurement | Result | Meaning |
|---|---:|---|
| Front ride height | about 119 mm in all four runs | Requested vertical offset does not move the rendered/physical body |
| Rear ride height | about 114 mm in all four runs | Same result at the rear |
| Position error, excluding first sample | 14.5 cm at 0 cm offset; 24.5 cm at 15 cm offset | `setCarPosition()` aligns the car to the track and rejects the requested vertical displacement |
| FL wheel target/actual mean | 14.85 / 12.68 rad/s | Front wheel command partly survives |
| RL wheel target/actual mean | 29.66 / 1.30 rad/s | Driven rear wheel command is almost entirely overwritten by physics |
| Engine target/actual mean | 5361 / 7 RPM | Physics RPM command is overwritten; only the separate FMOD event creates believable live sound |
| Steering | target and actual frequently diverge and saturate at ±450° | The steering/suspension state is not a stable replay channel under per-frame teleport |

This matches the visual report: low body, wheels in arches, slow rear wheel rotation, no tyre smoke and wooden suspension. These are not missing recorder fields. The recorded JSON contains plausible wheel speeds, steering and RPM; the physical AI state discards or resets them after the script writes them.

The local CSP SDK explicitly documents that `physics.setCarPosition()` aligns a car on the track surface. Calling it every render/physics frame also prevents the suspension and tyre model from evolving naturally.

## Candidate backends

### A. Native replay-based opponent — first choice

The official CSP `Revenant` mode drives opponent index 1 with:

```lua
ac.setReplayBasedGhost(1, 0, replayOffset, 'stiff')
```

It exposes four collision policies: `disabled`, `pushable`, `knockable` and `stiff`. `stiff` is the required product behavior: the recorded leader continues on its trajectory and pushes the chase car.

Why this is the first experiment:

- the car goes through CSP/AC’s native replay rendering path rather than a teleported live suspension;
- the API is purpose-built for replaying a car with physical collision behavior;
- it should reuse native replay wheel/body state, effects and audio handling;
- the existing recorder/library/UI can remain, while only the playback adapter changes.

Known unknowns:

- `ac.setReplayBasedGhost()` is used by the current official mode but is not declared in the installed local Lua SDK; runtime availability on CSP 0.2.11 build 3465 must be probed;
- the official example plays a segment from the current session’s rolling replay buffer;
- persistence and random selection across sessions are not yet proven;
- saved `.ghost` loading exists through `shared/sim/ghost`, but it is not yet proven that a loaded ghost can be attached to the collidable replay opponent;
- smoke, suspension, wheel rotation and engine sound still require an in-game A/B test.

### B. Local fake AC server / native remote car — persistence fallback

Inspection of Virtual Steward 0.5c shows that it:

- parses `.acreplay` files;
- starts a local HTTP/TCP/UDP AC server;
- connects Assetto Corsa to `127.0.0.1:8081`;
- emits normal AC/CSP network packets, including `CSPPositionUpdate`.

Therefore Virtual Steward’s replay cars use the native online remote-car pipeline. This is materially different from our physical teleport implementation and explains why a local server remains a serious production option despite extra process complexity.

If CSP cannot persist/load a replay-based ghost directly, our external helper can own the run library and emit the selected run as a synthetic remote client. The in-game Lua app can remain the user-facing UI and talk only to a localhost helper. The helper and local server can be launched by Content Manager/install tooling so the user does not manually operate a second window.

This path has more engineering and packaging cost, but it preserves the native car renderer/effects and naturally supports a persistent random replay database.

### C. Alternative approaches not selected now

#### Replay recorded controls into a physical AI

This would restore natural suspension, smoke and sound, but drift dynamics are chaotic. Small differences in setup, tyres, temperature, timestep or contact rapidly change the trajectory. Frequent corrections bring back the same teleport artifacts; infrequent corrections break determinism. It conflicts with the requirement to reproduce each recorded leader error exactly.

#### Custom KN5 visual proxy plus a semi-dynamic rigid body

CSP’s `physics.RigidBody` could provide a collision shell while Lua animates a separate visual car. But a generic implementation would have to reproduce wheel hierarchies, suspension transforms, skins, lights, driver animation, soundbanks, smoke and replay serialization for arbitrary mod cars. This is a large renderer project and duplicates systems AC already has.

#### AI spline

An AI spline produces a naturally simulated vehicle, but it does not reproduce the recorded drift angle, transitions, wheelspin and small mistakes. It is useful for generic racing-line traffic, not for this training product.

## Phase 1.5 experiment

Add a separate native-backend test to the existing in-game window; do not remove the current buttons until the comparison is complete.

1. `Start native capture` marks the current rolling-replay time.
2. The user drives a 10–20 second lead.
3. `Play native capture` calls `ac.setReplayBasedGhost()` for opponent 1 with `stiff` collision mode.
4. Repeat with `pushable` only to understand contact behavior; the product default remains `stiff`.
5. Compare against the physical backend using the same car and route.

Pass criteria:

- normal body height and believable suspension movement;
- front steering and all four wheel rotations are smooth;
- tyre smoke appears under wheelspin;
- native or otherwise replay-safe engine audio is present;
- chase receives collision impulse while the leader continues its recorded route;
- restart works at least ten times without accumulating state;
- normal AC replay of the chase session does not introduce severe wheel jitter.

After live fidelity passes, run a separate persistence experiment:

1. save and reload a CSP `.ghost` generated from the accepted run;
2. try attaching the loaded record to the replay-based opponent;
3. if that cannot be made collidable, stop investigating private Lua internals and build the localhost remote-car prototype.

## Stop conditions

- Do not spend more time adding wheel/RPM/suspension overrides to the physical teleport backend.
- Do not start Phase 2 library/random UI until one native backend passes live fidelity.
- Do not require users to upgrade CSP solely for undocumented `altonline` until the exact compatible build and behavior are verified.

## Primary references

- [Official CSP Revenant mode](https://github.com/ac-custom-shaders-patch/acc-lua-internal/blob/4d02a7affc8aecfb7738dce9f93be3a82118e2b7/included-new-modes/revenant/mode.lua)
- [Official Revenant manifest](https://github.com/ac-custom-shaders-patch/acc-lua-internal/blob/4d02a7affc8aecfb7738dce9f93be3a82118e2b7/included-new-modes/revenant/manifest.ini)
- [Official CSP ghost helper](https://github.com/ac-custom-shaders-patch/acc-lua-internal/blob/2031bd2d7c913e0aad3ff18a3bab86ffccad1326/lua-shared/sim/ghost.lua)

