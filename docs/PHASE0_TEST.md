# Phase 0 manual test

## Control fixture

- CSP: 0.2.11 build 3465 or newer
- Mode: `AC Random Lead Runs — Phase 0`
- Track: `vdc_bikernieki_2022`, layout `drift_vdc`
- Car: `vdc_nissan_s14_kouki_public`
- Session: offline Track Day created by the New Mode
- Opponents: exactly one, using the same car model as the player

The mode is not hard-restricted to this content. The fixture only makes test results reproducible.

## In-game app window

Enable `Random Lead Runs — Phase 0` in Content Manager’s Assetto Corsa Apps settings if it is not enabled automatically. In the session, open it from the right-hand app bar.

The window has three controls:

- `Park leader for contact test`: park the virtual leader 7 m in front of the player.
- `Start 12 s synthetic lead run`: start an S-shaped lead run 7 m in front of the player.
- `Stop and hide leader`: stop playback and hide the virtual leader.

Phase 0 does not register or use any keyboard hotkeys.

## Test order

1. In Content Manager, select exactly one opponent using the same car model as the player.
2. Launch the control fixture, open the app window and confirm that it reports `Cars: 2` and `Status: idle`.
3. Click `Park leader for contact test`. Confirm that a normal-looking second S14 appears 7 m ahead.
4. Touch its door slowly, then hit its rear quarter more firmly.
5. Confirm that the chase car receives an impulse while the leader stays at its submitted position.
6. Check body visibility, wheel placement, brake lights, idle audio and whether the leader can be driven through.
7. Click `Stop and hide leader`; confirm the leader disappears without a session restart.
8. Align the player with a sufficiently open part of the course and click `Start 12 s synthetic lead run`.
9. Follow the leader and observe orientation, wheel animation, smoke, engine audio and visual jitter.
10. Repeat the run ten times, using `Stop and hide leader` when needed. Confirm there is no accumulated offset or stale collision body.

## Record for each check

Use `pass`, `degraded`, or `fail` and add a short note:

| Check | Result | Notes |
|---|---|---|
| Physical AI leader created | pass | User confirmed that the leader appears 7 m ahead after pressing Park. |
| Show/hide/reset |  |  |
| Chase receives contact impulse | pass | Collision impulse is transferred to the player car. |
| Leader trajectory unaffected by contact | pass | Contact does not displace the state-driven leader. |
| Body and wheels render correctly |  |  |
| Brake lights |  |  |
| Engine audio |  |  |
| Tyre smoke/slip |  |  |
| Rotation/orientation | degraded | Synthetic straight/S path left the usable track area and appeared to fly; real recorded transforms must retain surface height. |
| Proximity jitter |  |  |
| Ten-cycle stability |  |  |

The spike passes only if contact affects the chase car and the leader remains deterministic. A non-colliding ghost is not an acceptable fallback.

## Test result — 2026-08-25

The core feasibility condition passed on CSP 0.2.11 build 3465: a physical AI opponent can be state-driven while transferring collision impulses only to the chase car in practice. The synthetic trajectory is not a route generator and can leave the track; Phase 1 must record and replay full world-space transforms from an actual lead run.
