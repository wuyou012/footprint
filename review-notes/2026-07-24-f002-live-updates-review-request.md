# Review Request: F002 live updates persistent recording

Review-Target-ID: f002
Branch: `feat/f002-background-persistent-recording`
Review Target Commit: `9bb1ffd`

## What
Refactored F002 Daily/High persistent recording from CMMotion-driven `startUpdatingLocation` / `stopUpdatingLocation` to `CLLocationUpdate.liveUpdates` system-managed pause/resume.

Key changes:
- Daily/High start a long-lived live-update subscription; `update.stationary` flushes and ends the current trip, then continues the loop without cancelling the subscription.
- Eco uses SLC + Visit only; CMMotion remains diagnostics/traffic labeling and no longer starts standard GPS.
- Startup one-shot `requestLocation()` is routed to map anchor only, not ambient track storage.
- Ambient track points are buffered and batch-written to SQLite.
- Daily walking density is tightened to fallback `distanceFilter=15m`, `minDistance=12m`, `minInterval=5s`.
- F002 feature doc updated with the 2026-07-24 architecture supersession note.

## Why
Dogfood showed the old motion-gated plan bounced between two bad states: low-confidence walking could be missed, and low-confidence stationary could keep GPS active for ~20 hours. The new design moves moving/stationary authority to Core Location system pause/resume, which is the right layer for both battery and background lifecycle.

## Original Requirements
> Daily 建立一个长期的逻辑定位会话；用户静止后 Core Location 自动暂停；用户重新移动后系统自动恢复。  
> 启动定位只负责地图聚焦，不应该创建 session、轨迹段或写入数据库。  
> CMMotion 的角色降级为交通方式标签、辅助判断、异常诊断。  
> 收到 stationary 时不能 break，要 continue。  
- 来源：`/Users/wuyou/Documents/APP_Project/footprint/input.md`
- 请对照上面的摘录判断交付物是否解决了 operator 的问题。

## Tradeoff
This is an architecture refactor, not a threshold tweak. It keeps the existing `RecordingManager` / `TrackDatabase` boundary instead of adding a parallel recording stack, but it changes the coordinator state model and runtime source of truth. Simulator builds cannot prove real battery behavior; real-device locked-screen dogfood remains required before merge.

## Architecture Ownership
Architecture cell: core GPS recording (`docs/ARCHITECTURE.md`)
Map delta: update required
Why: Persistent recording authority moved from app-level CMMotion gating to Core Location live updates, while staying inside the existing recording/storage/view boundaries.

Please check:
- diff is consistent with `Map delta`
- no unnecessary parallel Store/Router/Dispatcher was introduced
- F003 will need rebase/reintegration after this F002 branch stabilizes

## Open Questions

### 技术 OQ（给 reviewer）
- Does the `CLLocationUpdate` task correctly keep the subscription alive on `stationary` and only cancel on disable?
- Does the `requestLocation()` map-anchor path fully prevent startup locations from creating ambient sessions/track points?
- Is the ambient batch-write flush coverage sufficient for system pause, background entry, disable, and segment finish?
- Are the SLC/Visit low-power fallback calls idempotent enough around Daily start/stop and Eco start/stop?

### 价值 OQ（给 operator）
无。剩余是实机验收问题：automatic pause 恢复延迟和真实电量表现。

## Next Action
Please review the branch diff on `feat/f002-background-persistent-recording`, with code target commit `9bb1ffd`. If approved, pass back for receive-review/merge planning; if not, mark P1/P2 with exact files/lines.

## Review Sandbox
- Path: `/tmp/cat-cafe-review/f002/opus48`
- Start Command: iOS project, no local web/api server. Use a detached checkout and run the validation commands below.
- Ports: none

Suggested bootstrap:
```bash
git fetch origin feat/f002-background-persistent-recording
git worktree add /tmp/cat-cafe-review/f002/opus48 origin/feat/f002-background-persistent-recording --detach
cd /tmp/cat-cafe-review/f002/opus48
```

## 自检证据

### Spec 合规
- ✅ Map Anchor separation implemented via `pendingMapAnchorRequest` + `LocationUpdateRouter`.
- ✅ Daily/High system-managed live updates implemented with `CLLocationUpdate.liveUpdates`.
- ✅ `stationary` path flushes and ends trip but does not cancel the live-update loop.
- ✅ CMMotion no longer controls GPS start/stop.
- ✅ Ambient DB writes are batched.
- ✅ F002 doc updated with new architecture and updated AC.

### Dogfood-Your-Slice
Scope verdict: partial. Simulator build verifies compile/runtime integration boundaries, but real automatic pause/resume and battery behavior require physical-device locked-screen testing.

Required acceptance dogfood after review:
- 静止 6-8h: `systemPausedSeconds` rises, location callbacks and DB writes stop.
- 步行 20-30m: movement resumes and 10-15m-scale turns are visible.
- 混合: drive → park → walk → stationary produces separate trips, not one giant session.

### 测试结果

```bash
scripts/run-logic-tests.sh
# FootprintLogicTests passed

xcodebuild -project footprint.xcodeproj -scheme footprint -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
# BUILD SUCCEEDED

xcodebuild -project footprint.xcodeproj -scheme footprint -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
# BUILD SUCCEEDED

git diff --check
# exit 0
```

### Artifact Hygiene
```bash
git status --short | rg '^.. [^/]+\.(png|jpe?g|webp|gif|webm|mp4|mov|wav|pdf|pen)$'
# no output

git diff --name-only origin/main...HEAD | rg '^[^/]+\.(png|jpe?g|webp|gif|webm|mp4|mov|wav|pdf|pen)$'
# no output
```

### 相关文档
- Feature: `docs/features/F002-background-persistent-recording.md`
- Source proposal: `/Users/wuyou/Documents/APP_Project/footprint/input.md`

[gpt/gpt-5.5🐾]
