# Review Request: F002 Background Persistent Recording

Review-Target-ID: f002
Branch: `feat/f002-background-persistent-recording`
Head: `ed598a6`

## What
Implemented F002 on the core GPS branch:

- Added persistent recording toggle in `RecordSettingsView`.
- Added motion gating (`MotionGate` + `CoreMotionActivityProvider`) and a persistent location state machine.
- Added SLC / Visit registration in `RecordingManager`.
- Added ambient session segmentation: Eco groups by day, Daily / High group by trip.
- Added `recording_sessions.kind` + `origin` schema v2 and fixed the `user_version` downgrade bug.
- Updated History / Day Detail wording to Trips and labels rows as `AUTO` / `MANUAL`.
- Added a lightweight Swift logic test runner for P1-P4.

## Why
Operator wants footprint to record passively without remembering to press Start, while Eco / Daily should use fewer points and larger filters because the goal is knowing movement / visited areas, not perfect track fidelity.

## Original Requirements
> 省电和普通点数可以更少，filter更大一些，因为不需要足够精准的轨迹，只有知道移动就可  
> 切行程端是合理的，我认为运动模式和普通模式可以这么做，省电模式按天即可  
> 2先不管；作为一个todo  
> 合理的，开始然后传球实现

- Source: thread `thread_mrf0m4q6dbosnc13`, co-creator messages `0001783696299859-000138-03d402d4` and `0001783697189287-000141-65cbd89f`.
- Please review against the original behavior goal, not only the code diff.

## Tradeoff
- Did **not** implement OQ-2 manual Start overlay while persistent mode is ON. Current behavior disables manual Start until persistent recording is turned off.
- True SLC wake-after-kill and battery claims are **not** asserted here; they require physical-device dogfood.
- Added a shell-based logic test runner instead of a full Xcode test target to avoid pbxproj churn in this file-system-synchronized Xcode 26 project.

## Architecture Ownership
Architecture cell: core GPS recording
Map delta: update required
Why: Adds a persistent coordination layer above existing session recording, without replacing `RecordingManager` or the SQLite storage boundary.

Reviewer focus:
- Does the new coordinator stay above the existing manual session path instead of corrupting it?
- Is disabling manual Start while persistent ON an acceptable containment of OQ-2?
- Does DB migration really avoid `user_version` downgrade across branch switching?

## Open Questions

### Technical OQ
- `RecordingManager` grew substantially. Please review for lifecycle edge cases around ambient session finish, toggling OFF, Visit arrival, and app foreground/background transitions.
- Eco duty-cycle is represented as a distinct command and currently starts/stops sampling via the same `CLLocationManager` path; true on/off cadence still needs dogfood tuning.
- Simulator can launch the app, but cannot verify kill wake or battery behavior.

### Value OQ
None for this review. OQ-2 remains explicitly parked as a later todo per operator.

## Next Action
@opus48 please cross-review this branch. If accepted, next step is physical-device dogfood before merge-gate claims AC-2 / AC-5 complete.

## Review Sandbox
- Path: `/tmp/footprint-review-f002/opus48`
- Start Command: no server; open the Xcode project or use the validation commands below.
- Ports: none.

Suggested reviewer bootstrap:

```bash
git clone https://github.com/wuyou012/footprint.git /tmp/footprint-review-f002/opus48
cd /tmp/footprint-review-f002/opus48
git checkout feat/f002-background-persistent-recording
```

## Self-Check Evidence

### Spec Compliance
- AC-1 code path present: toggle enables persistent monitoring and stores preference. Simulator launch verified, but background walking was not device-tested.
- AC-2 pending physical device: kill wake via SLC cannot be proven in simulator.
- AC-3 covered by logic tests for profile parameters and by build for CoreLocation integration.
- AC-4 covered by MotionGate / coordinator logic tests; device confidence stream still needs dogfood.
- AC-5 pending physical device battery comparison.
- AC-6 covered by `SessionSegmenter` and DB `kind/origin` tests.
- AC-7 implemented in History / Day Detail with AUTO / MANUAL labels.
- AC-8 implemented by Always Location existing plist keys plus new `NSMotionUsageDescription`.

### Design / Artifact Hygiene
- `find designs -name '*.pen' -maxdepth 3` -> no `designs/` directory.
- Root media / design artifact scans -> no matches.

### Dogfood
Scope verdict: partial, because the core feature requires a real iPhone for background wake / battery validation.

- Simulator device: booted iPhone 17.
- App install: `xcrun simctl install booted .../footprint.app` -> exit 0.
- App launch: `xcrun simctl launch booted com.wuyou.footprint` -> PID `27417`.
- Screenshot: `/tmp/footprint-f002-evidence/launch.png`; main map UI rendered, not blank.

### Validation Commands

```bash
bash scripts/run-logic-tests.sh
# FootprintLogicTests passed

xcodebuild -scheme footprint -configuration Debug -destination 'generic/platform=iOS Simulator' build
# ** BUILD SUCCEEDED **

git diff --check
# exit 0
```

## Related Docs
- Feature spec: `docs/features/F002-background-persistent-recording.md`
- Architecture reference: `docs/ARCHITECTURE.md`
