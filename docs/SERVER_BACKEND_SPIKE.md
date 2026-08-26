# Localhost remote-car backend spike

Status: compile-time prototype

Pinned AssettoServer: `6ce86addc1b1c70caf018a7b39f6d7bc9aa9493f` (`v0.0.55-pre35`)

## Why this exists

CSP 0.2.11 build 3465 is the latest public recommended CSP release and does not expose `ac.setReplayBasedGhost`, `ac.disableCar` or `shared/sim/altonline`. The per-frame physical teleport backend cannot preserve suspension, driven-wheel speed, RPM or smoke.

AssettoServer already sends synthetic traffic through AC/CSP’s native remote-car packets. Its outgoing state includes body position/rotation/velocity, four encoded tyre angular speeds, steering, RPM, gear, gas and light flags. This spike reuses that native client pipeline without trying to render or physically simulate a second car inside Lua.

## Current scope

`server-plugin/RandomLeadServerPlugin`:

- loads the newest `latest.json` from the existing run library, or an explicit configured path;
- validates run schema v1/v2/v3 and the reserved leader car model;
- announces an empty entry-list slot as `Recorded Leader`;
- interpolates the run against server time;
- emits regular AC `PositionUpdate` packets at the server tick rate;
- includes recorded steering, four wheel speeds, RPM, gear, throttle and brake lights;
- loops automatically with configurable start/reset delays for the first visual/contact test.

Run schema v3 records the physics transform required by AC network packets. Legacy v1/v2 recordings used CSP’s visual/model origin; the fixture reads `GRAPHICS_OFFSET` from the recorded car’s `car.ini` and the server plugin converts those frames back to physics origin during playback.

It intentionally does not yet provide in-game commands or distribution packaging. The localhost fixture and launcher are automated; the first exit criterion is narrower: prove that the remote-car renderer fixes body height, wheel/suspension animation, smoke and audio, and that contact affects the chase car without moving the recorded leader.

## Build

```powershell
.\tools\build-server-plugin.ps1
```

The script uses an ignored checkout in `.tmp/AssettoServer` and refuses to build against a different upstream commit. AssettoServer targets .NET 9.

## Automated localhost fixture

Run:

```powershell
.\tools\start-localhost-test.ps1
```

The launcher builds the pinned server/plugin, selects the newest `latest.json`, verifies installed content, generates two same-car slots, reserves session ID 1 for the leader, links the local AC content read-only through junctions, and starts a 50 Hz server on `127.0.0.1:9600`. Generated files and logs stay below ignored `.runtime/localhost-server`.

See [LOCALHOST_TEST.md](LOCALHOST_TEST.md) for the manual runtime test.

## Licensing boundary

AssettoServer is AGPL-3.0. This repository currently references its source only from an ignored development checkout and does not vendor or redistribute AssettoServer binaries. Before publishing a packaged server/plugin binary, the project must explicitly choose and document an AGPL-compatible distribution arrangement.

The pinned upstream build currently reports NuGet security advisories for its transitive `Scriban 6.6.0` dependency, including a critical advisory. The spike is localhost-only and no AssettoServer binary is committed or distributed. Packaging is blocked until the dependency is updated upstream or the exposure is explicitly assessed and mitigated.

## Primary references

- [AssettoServer source](https://github.com/compujuckel/AssettoServer/tree/6ce86addc1b1c70caf018a7b39f6d7bc9aa9493f)
- [AssettoServer `PositionUpdateOut`](https://github.com/compujuckel/AssettoServer/blob/6ce86addc1b1c70caf018a7b39f6d7bc9aa9493f/AssettoServer.Shared/Network/Packets/Outgoing/PositionUpdateOut.cs)
- [AssettoServer AI state packet population](https://github.com/compujuckel/AssettoServer/blob/6ce86addc1b1c70caf018a7b39f6d7bc9aa9493f/AssettoServer/Server/Ai/AiState.cs)
