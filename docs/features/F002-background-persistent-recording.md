---
feature_ids: [F002]
related_features: [F001]
topics: [gps, recording, background, battery, core-location, core-motion, power-optimization]
doc_kind: spec
created: 2026-07-10
---

# F002: Background Persistent Recording（后台常驻记录 + 三档省电）

> Status: spec | Owner: 砚砚（缅因猫/gpt，实现）| Design: opus（布偶猫/opus-4-8）
> Related: F001（点亮系统消费本 feature 产出的轨迹点）

## Why

**被动记录足迹是这个 app 的核心身份**——用户不该每次出门都记得点 Start。真正的护城河是"手机在兜里、app 在后台，足迹自动长出来"。

但"常驻"和"续航"天然冲突：现在的记录是**会话式**（`RecordingManager.start()` 开连续 GPS，`stop()` 结束），连续 GPS 实测约 **6 小时耗光电池**，优化后可达 ~20h（[Apple 能效指南](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html)）。所以本 feature 的价值不是"能后台记录"（现有代码 `allowsBackgroundLocationUpdates=true` 已能），而是**在不烧电的前提下常驻记录**。

同时，这也是 F001 的上游：只有后台源源不断产生轨迹点，地图区域才会持续点亮，奖励闭环才转得起来。

## Current State / 现状基线（实测证据）

`RecordingManager.swift`（`main` 核心）当前行为：
- 只有用户点 **Start** 才录制；`stop()` 即结束。无"常驻"能力。
- 录制中用**连续 GPS**（`startUpdatingLocation` + `allowsBackgroundLocationUpdates`），静止时**不降级**——停着不动也在烧 GPS。
- 精度/距离由 `RecordingProfile`（High/Daily/Eco）的 `desiredAccuracy` + `distanceFilter` 决定，但这三档只在"录制中"生效，无静止感知、无运动门控、无 SLC/Visit 基线。
- `backgroundRecordingEnabled` 字段存在，但语义 = "本次 session 是否拿到 Always 授权"，**不是**"常驻开关"。

结论：现有三档只是"录制时的精度档"，缺一层"什么时候该开 GPS"的省电引擎，也没有"不点 Start 也记"的常驻入口。

## What

1. **左菜单开关**：`RecordSettingsView` 的 "Recording" section 加 `Toggle("后台常驻记录")`。
   - OFF（默认）：维持现状——点 Start 才记，session 式。
   - ON：app 启动即注册常驻定位服务，**无需点 Start**，手机在后台/被划掉也持续记录（SLC/Visit 在 app 被系统回收后仍能唤醒重启 app）。
2. **三档不变**（省电 / 普通 / 运行 = Eco / Daily / High），但每档在常驻模式下的**运行方式**被重新定义：三档是"省电↔保真"滑块，共用同一套省电引擎，只是激进程度不同。
3. **省电引擎**：CMMotion 运动门控 + SLC/Visit 静止基线 + 精度分级 + 系统自动暂停——静止不烧 GPS，只有真正移动才开。

## 核心设计：三档运行方式 + 省电引擎

### 横切省电引擎（三档共用，只是激进度不同）

| 手段 | 机制 | 为什么省电 | 来源 |
|---|---|---|---|
| **CMMotion 运动门控** | `CMMotionActivityManager` 报 stationary/walking/running/automotive | M 系列协处理器处理，**几乎零耗电**就能判断在不在动 → 静止就关 GPS | [NSHipster](https://nshipster.com/cmmotionactivity/) |
| **SLC + Visit 静止基线** | `startMonitoringSignificantLocationChanges` + `startMonitoringVisits` | 用蜂窝/WiFi 定位（非 GPS），~500m 粒度，近零耗电；app 被杀也能唤醒 | [Apple 能效指南](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html) |
| **desiredAccuracy 分级** | 按档设精度，不过度请求 | 精度是耗电大头——BestForNavigation/NearestTenMeters 最贵，HundredMeters 省很多 | [Apple 能效指南](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html) |
| **distanceFilter 匹配精度** | filter 与 accuracy 同级 | 系统层过滤，不在 app 层烧 CPU 反复算距离 | [Rangle](https://rangle.io/blog/optimizing-ios-location-services) |
| **pausesLocationUpdatesAutomatically** | 静止久了系统自动暂停连续更新 | 系统级省电（代价：恢复有延迟，靠 CMMotion/SLC 补） | 同上 |

**统一状态逻辑**：SLC/Visit 唤醒（后台约 10s 窗口）→ 查 CMMotion → 在动则拉起连续 GPS，静止则维持 SLC-only。**飞行 / 长时间静止 → 落 SLC-only，几乎不记点。**

### 三档 = 省电激进度滑块（后台常驻下的运行方式）

> 参数为**起点值**，真机 dogfood 校准。所有档位在**静止时**都退回 SLC/Visit 基线、关闭连续 GPS。

| | **省电 Eco** | **普通 Daily（默认）** | **运行 High** |
|---|---|---|---|
| 定位主力 | SLC + Visit 为主 | SLC/Visit 基线 + 移动时连续 GPS | 连续 GPS 为主（SLC/Visit 兜底） |
| desiredAccuracy | `HundredMeters` | `HundredMeters` | `NearestTenMeters` |
| distanceFilter | 80–100m | 25m | 8–10m |
| 移动时开 GPS 策略 | **duty-cycle**：周期短开拿点即关，或明确 automotive/walking 才开 | CMMotion 检测到移动即开连续 | 移动即持续高精度 |
| 静止退回阈值 | 立即（几乎不主动开 GPS） | stationary ≥ 3 min 退 SLC | stationary ≥ 5 min 退 SLC |
| 有效记点频率 | ~100m/点 或 1–2 min/点 | ~10–25m/点（~15s） | ~8–10m/点（~1–10s） |
| 续航预期（目标，待实测） | 全天 < 5% 电量 | 日常通勤全天 ~10–15% | 连续记录数小时级明显耗电 |
| 场景 | 只想大概记"去过哪些城市"，喂点亮足够 | 日常通勤/城市走动，轨迹顺滑电量可接受 | 跑步/骑行/徒步，要精细轨迹 |

**与 F001 点亮的关系**：省电档的 ~100m 粒度足够命中区域边界点亮（F001 V0"存在即点亮、50m 精度可接受"），所以"省电常驻 + 全球点亮"是绝配——最低电量代价换最大点亮覆盖。

## Acceptance Criteria

> 硬度自检：每条 trace 回 Why，且非作者可复核（真机 dogfood 截图/日志，本项目无 test target，用 `xcodebuild` + 模拟器/真机证据）。

- [ ] **AC-1（常驻入口）**：左菜单 Recording section 有"后台常驻记录"开关；开启后**不点 Start**，app 进后台 + 走动，回来能看到新增轨迹点。→ trace: Why"不该每次记得点 Start"
- [ ] **AC-2（被杀唤醒）**：开启常驻后，从后台**划掉 app**，走动 ≥500m，SLC 唤醒 app 并续记点。→ trace: Why"app 在后台/被划掉也持续"
- [ ] **AC-3（三档运行方式）**：省电/普通/运行三档按上表的定位机制 + 参数实现；日志可证明**静止时连续 GPS 已关闭、退回 SLC**。→ trace: Why"不烧电前提下常驻"
- [ ] **AC-4（运动门控）**：CMMotion 报 stationary 达档位阈值后，连续 GPS 停止；报 walking/automotive 后重新拉起。→ trace: 省电引擎
- [ ] **AC-5（续航实测）**：普通档日常通勤半天真机实测，电量消耗对比"现有连续模式"显著下降（给出两组电量数字）。→ trace: Why"续航"
- [ ] **AC-6（数据不污染）**：常驻自动记录的点按"环境会话"分组（按天或 visit-to-visit 分段），**不混入**手动 Start session 的统计/导出。→ 见 OQ-1
- [ ] **AC-7（授权与隐私）**：Always 授权引导清晰；常驻开启时有明确状态提示 + 隐私/耗电说明文案（App Store Always-location 需正当性说明）。

## Dependencies
- `main` 核心 `RecordingManager` / `LocationFilter` / `RecordingProfile` / `TrackDatabase`（本 feature 增强，不推翻）。
- 需 Info.plist：`UIBackgroundModes: location` + `NSLocationAlwaysAndWhenInUseUsageDescription`（核实是否已配）。
- Core Motion（`CMMotionActivityManager`）——需 `NSMotionUsageDescription` + 运动权限。
- **顺带修（resume guide 标记的核心 debt）**：`TrackDatabase.migrate()` 无条件 `PRAGMA user_version=1` → 改"读 currentVersion、只升不降"，避免跨分支切换把共享 dev DB 降级。碰核心 GPS 正好一起修。

## Risk
- **常驻恢复延迟**：`pausesLocationUpdatesAutomatically` + SLC 恢复不是瞬时；快速短途移动可能漏头几个点。缓解：CMMotion 抢先拉起 + Visit 补。
- **App Store 正当性**：Always + 后台定位需清晰隐私说明；个人自用无碍，若上架需正当性文案。
- **CMMotion 置信度**：低置信度活动读数需结合位移变化兜底（[NSHipster](https://nshipster.com/cmmotionactivity/) 建议）。
- **电量目标未实测**：上表续航数字是设计目标，**必须真机 dogfood 校准**，不得当实测结论宣传。

## Open Questions
- **OQ-1（环境会话分组）**：常驻自动点怎么归组？候选：①按 localDay 一个滚动 session；②按 CLVisit 到达/离开切"行程段"。倾向 ②（语义清晰，天然配合 Visit 监控），Design Gate 定。
- **OQ-2（开关与手动 Start 关系）**：常驻 ON 时用户再点 Start 高精度录制，两者如何切换/叠加？倾向"手动 Start 临时提权到 High，停止后落回常驻档"。
- **OQ-3（duty-cycle 周期）**：省电档周期短开 GPS 的开/关时长（Design Gate + dogfood 定）。

## Design Gate（待办）
架构级（新增常驻服务层 + 三档状态机重构核心 GPS）→ 猫猫讨论技术方案（状态机/数据模型）→ operator 拍板 OQ-1/OQ-2 → 再 writing-plans + worktree。**co-creator 已确认**：三档不变（省电/普通/运行）、省电引擎方向、常驻开关入左菜单。

## Review
- 实现：砚砚（缅因猫/gpt）。Review：opus 或第三只猫（**禁止 self-review**）。
- 门禁：worktree（基于 main 核心）→ TDD → quality-gate → cross-review → merge-gate；真机 dogfood 电量/唤醒截图作证据。
