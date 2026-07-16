---
feature_ids: [F002]
related_features: [F001]
topics: [gps, recording, background, battery, core-location, core-motion, power-optimization]
doc_kind: spec
created: 2026-07-10
---

# F002: Background Persistent Recording（后台常驻记录 + 三档省电）

> Status: spec | Owner: 砚砚（缅因猫/gpt，实现）| Design: opus（布偶猫/opus-4-8）
> Branch: **`main`**（核心记录功能）| Related: F001（点亮系统消费本 feature 产出的轨迹点）

## Why

**被动记录足迹是这个 app 的核心身份**——用户不该每次出门都记得点 Start。护城河是"手机在兜里、app 在后台，足迹自动长出来"。

但"常驻"和"续航"冲突：现在是**会话式**（`RecordingManager.start()` 开连续 GPS，`stop()` 结束），连续 GPS 实测约 **6 小时耗光电池**，优化后可达 ~20h（[Apple 能效指南](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html)）。本 feature 的价值不是"能后台记录"（现有 `allowsBackgroundLocationUpdates=true` 已能），而是**在不烧电前提下常驻记录**。也是 F001 上游：后台持续产点，区域才持续点亮。

## Current State / 现状基线（实测证据，`main`）

- 只有点 **Start** 才录；`stop()` 即结束。无常驻能力。
- 录制中用**连续 GPS**，静止**不降级**——停着不动也烧 GPS。
- `RecordingProfile`（High/Daily/Eco）只在"录制中"决定精度，无静止感知 / 运动门控 / SLC 基线。
- `backgroundRecordingEnabled` 字段 = "本 session 是否拿到 Always 授权"，**不是**常驻开关。
- 查看模型：`HistoryView` 按 `localDayKey` 聚合 `DaySummary`（每天一卡）→ `DayDetailView` 用 `ForEach(sessions)` 渲染当天 `DaySession` 列表（`SessionRow`：时间段+档位+点数+距离）。

## What

1. **左菜单开关**（`RecordSettingsView` Recording section）：`Toggle("后台常驻记录")`。
   - OFF（默认）：维持现状——点 Start 才记。
   - ON：app 启动即注册常驻定位，**无需点 Start**；被划掉也靠 SLC/Visit 唤醒续记。
2. **三档不变**（省电/普通/运行 = Eco/Daily/High），重新定义为**"省电↔保真"滑块**，共用省电引擎，激进度不同。
3. **省电引擎**：CMMotion 运动门控 + SLC/Visit 静止基线 + 精度分级 + 系统自动暂停——静止不烧 GPS。

## 核心设计：三档运行方式 + 省电引擎

### 横切省电引擎（三档共用）

| 手段 | 机制 | 为什么省电 | 来源 |
|---|---|---|---|
| **CMMotion 运动门控** | `CMMotionActivityManager` 报 stationary/walking/running/automotive | M 协处理器处理，**几乎零耗电**判断在不在动 → 静止关 GPS | [NSHipster](https://nshipster.com/cmmotionactivity/) |
| **SLC + Visit 静止基线** | `startMonitoringSignificantLocationChanges` + `startMonitoringVisits` | 蜂窝/WiFi 非 GPS，~500m 粒度近零耗电；app 被杀也能唤醒 | [Apple 能效指南](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html) |
| **desiredAccuracy 分级** | 按档设精度不过度请求 | 精度是耗电大头 | 同上 |
| **distanceFilter 匹配精度** | filter 与 accuracy 同级 | 系统层过滤，不在 app 层烧 CPU | [Rangle](https://rangle.io/blog/optimizing-ios-location-services) |
| **pausesLocationUpdatesAutomatically** | 静止久系统自动暂停 | 系统级省电（恢复延迟靠 CMMotion/SLC 补） | 同上 |

**统一状态逻辑**：SLC/Visit 唤醒（后台约 10s 窗口）→ 查 CMMotion → 在动拉起连续 GPS，静止维持 SLC-only。飞行 / 长时间静止 → SLC-only。

### 三档参数（co-creator 2026-07-10 调整：省电/普通"点更少、filter 更大，知道移动即可，不需精准轨迹"）

> 参数为起点值，真机 dogfood 校准。所有档位**静止时**都退回 SLC/Visit、关闭连续 GPS。

| | **省电 Eco** | **普通 Daily（默认）** | **运行 High** |
|---|---|---|---|
| 定位主力 | SLC + Visit 为主 | 基线 + 移动时连续 GPS | 连续 GPS 为主 |
| desiredAccuracy | `HundredMeters` | `HundredMeters` | `NearestTenMeters` |
| **distanceFilter** | **~200m**（原 80–100 ↑）| **~60m**（原 25 ↑）| 8–10m（不变）|
| 移动开 GPS 策略 | duty-cycle 短开即关，automotive/walking 才开 | 检测到移动即开连续 | 移动即持续高精度 |
| 静止退回阈值 | 立即 | stationary ≥ 3 min | stationary ≥ 5 min |
| 有效记点频率 | ~200m/点（一天寥寥数十点）| ~60m/点 | ~8–10m/点 |
| **会话分组** | **按天**（一天 1 段滚动 session）| **按行程段**（CLVisit 切）| **按行程段**（CLVisit 切）|
| 续航预期（目标，待实测） | 全天 < 5% 电量 | 通勤全天 ~10% | 数小时级明显耗电 |
| 场景 | 只想记去过哪些片区/城市，喂点亮 | 日常通勤（知道走向即可）| 跑步/骑行/徒步，精细轨迹 |

**和 F001 绝配**：省电档 ~200m 粒度足够命中城市级区域点亮（F001 V0"存在即点亮"），最低电量换最大点亮覆盖。

## 分段后「查看 / UI」的变化分析（回答 co-creator 2026-07-10）

**结论：现有查看结构天然兼容分段，改动很小。** `DayDetailView` 已是 `ForEach(sessions)` 渲染多个 `SessionRow`，行程段直接落进去，**无需重构**。

| Surface | 现在 | F002 分段后 | 变化 |
|---|---|---|---|
| **History（按天）** | 每天一卡 "N sessions · M points" | 仍每天一卡 | 结构不变；**省电档** N=1（一天一段）；**普通/运动档** N=当天行程段数（早通勤/午出门/晚归可能 3–5 段），"N sessions" 数字变大 |
| **Day Detail** | 地图 + `ForEach(sessions)` SessionRow 列表 | 同结构，SessionRow 变多（每行程段一行）| **无需重构**；一天多段自然铺开，每段显示各自时间段+距离 |
| **SessionRow** | 时间段 + 档位标签 + 点数 + 距离 | 同 | 档位标签常驻下=当前档 |

**建议的小 UI 调整（enhancement，非阻塞）**：
1. **措辞**：自动分段下 "sessions" → "行程/Trips" 更贴切（`DayCard` + DayDetail 标题）。
2. **段增强（可选）**：SessionRow 显示**起止地点**（配合 CLVisit 的 from/to 反查地名），让"行程段"可读性更强。
3. **数据层**：`DaySession` 表结构不变（已有 start/end/profile/count/distance），只是 session **产生方式**从"手动 start-stop"变成"自动按 visit/天切分"——migration 友好，查看查询（`loadSessions(for:)` / `loadDaySummaries`）无需改。

## Acceptance Criteria

> 硬度自检：每条 trace 回 Why 且非作者可复核（真机 dogfood 截图/日志；本项目无 test target，用 `xcodebuild` + 模拟器/真机证据）。

- [ ] **AC-1（常驻入口）**：左菜单有"后台常驻记录"开关；开启后不点 Start，进后台+走动，回来见新点。→ Why"不该每次点 Start"
- [ ] **AC-2（被杀唤醒）**：开启后从后台划掉 app，走 ≥500m，SLC 唤醒续记。→ Why"被划掉也持续"
- [ ] **AC-3（三档参数）**：三档按上表 accuracy/filter/分组实现；日志证明静止时连续 GPS 关闭、退 SLC。→ Why"不烧电常驻"
- [ ] **AC-4（运动门控）**：CMMotion 报 stationary 达阈值后停连续 GPS；报 walking/automotive 后拉起。→ 省电引擎
- [ ] **AC-5（续航实测）**：普通档日常通勤半天真机实测，电量对比现有连续模式显著下降（给两组数字）。→ Why"续航"
- [ ] **AC-6（分组正确）**：省电档一天 1 段；普通/运动档按 CLVisit 切多段；均**不污染**手动 Start session 统计/导出。→ 见分段分析
- [ ] **AC-7（查看兼容）**：History/DayDetail 正确显示自动分段（省电 1 段、普通/运动多段），SessionRow 时间段+距离正确。→ 分段查看分析
- [ ] **AC-8（授权隐私）**：Always + Motion 授权引导清晰；常驻开启有状态提示 + 隐私/耗电说明文案。

## Dependencies
- `main` 核心 `RecordingManager` / `LocationFilter` / `RecordingProfile` / `TrackDatabase`（增强不推翻）。
- Info.plist：`UIBackgroundModes: location` + `NSLocationAlwaysAndWhenInUseUsageDescription`（核实是否已配）。
- Core Motion `CMMotionActivityManager` + `NSMotionUsageDescription`。
- **顺带修（resume guide 核心 debt）**：`TrackDatabase.migrate()` 无条件 `PRAGMA user_version=1` → 改"读 currentVersion、只升不降"，避免跨分支切换降级共享 dev DB。碰核心 GPS 正好一起修。

## Risk
- **常驻恢复延迟**：`pausesLocationUpdatesAutomatically` + SLC 恢复非瞬时；快速短途可能漏头几个点。缓解：CMMotion 抢先拉起 + Visit 补。
- **App Store 正当性**：Always + 后台定位需清晰隐私说明；个人自用无碍，上架需正当性文案。
- **CMMotion 置信度**：低置信读数结合位移变化兜底（[NSHipster](https://nshipster.com/cmmotionactivity/)）。
- **电量目标未实测**：续航数字是设计目标，**必须真机 dogfood 校准**，不当实测结论宣传。

## Open Questions
- **OQ-1（会话分组）✅ 已定（co-creator 2026-07-10）**：**运动/普通档按 CLVisit 切行程段；省电档按天**。
- **OQ-2（常驻 × 手动 Start）— 🅃🄾🄳🄾 先不管**：常驻 ON 时用户再点 Start 高精度录制如何切换/叠加。倾向"手动 Start 临时提权 High，停止落回常驻档"，但**本 feature 暂不处理，记为 todo**。
- **OQ-3（duty-cycle 周期）**：省电档周期短开 GPS 的开/关时长（Design Gate + dogfood 定）。

## 实现计划（Design Gate 产出 · opus 2026-07-10）

> Design Gate 状态：**已过**（co-creator 授权"开始然后传球实现" 2026-07-10）。产品决策全部锁定：三档不变、省电引擎方向、常驻开关入左菜单、省电/普通参数调粗、OQ-1 分组、OQ-2 搁置。以下是给实现（砚砚）的技术蓝图。

### 新增组件（在现有 `RecordingManager` 之上抽常驻协调层，不推翻现有 session 式录制）

| 组件 | 位置 | 职责 |
|---|---|---|
| **`MotionGate`** | `Services/` | 封装 `CMMotionActivityManager`，输出 `isStationary` + activity 类型(walking/running/automotive/cycling/unknown) + confidence。纯信号源，可测。 |
| **`PersistentLocationCoordinator`** | `Services/` | 常驻大脑：注册 SLC (`startMonitoringSignificantLocationChanges`) + Visit (`startMonitoringVisits`)，订阅 MotionGate，跑状态机 `.dormant`(GPS 关，SLC/Visit only) ↔ `.active`(连续 GPS，按档参数)。转移：moving→active；stationary 达档阈值→dormant。 |
| **`SessionSegmenter`** | `Services/` 或 `TrackDatabase` 内 | 决定新点归哪个 ambient session：**Eco 按 `localDayKey` 切**（跨天开新段）；**Daily/High 按 `CLVisit` 切**（arrival 开段 / departure 结束段）。 |
| `RecordingProfile` 扩展 | `Models/TrackModels.swift` | 更新三档参数（Eco filter ~200m / Daily ~60m / High 不变 + accuracy 分级）+ 新增常驻阈值（`stationaryTimeoutSeconds` 等）。 |

### 数据模型改动
- `sessions` 表加 `kind TEXT`（`'manual'` | `'ambient'`）区分手动 vs 常驻自动，**保证 AC-6 不污染手动统计**。
- 可选 `origin TEXT`（`'visit'` | `'day'`）记录分段依据；CLVisit 起止地点（行程段显示用）可延后到 P6。
- **migration：user_version bump + 顺带修"无条件 `PRAGMA user_version=1`"bug → 改"读 currentVersion、只升不降"**。

### Phase 拆分（TDD，逐阶段可验收；P1–P4 纯逻辑隔离，最佳起点）

| Phase | 内容 | 验收（先红后绿）|
|---|---|---|
| **P1** | `MotionGate`（CMMotion 封装 → stationary/moving 信号）| 单测：mock activity 序列 → 正确 stationary/moving |
| **P2** | 三档参数更新（Eco 200m / Daily 60m / High 不变 + accuracy 分级 + 常驻阈值）| 单测：各档参数值 |
| **P3** | `PersistentLocationCoordinator` 状态机（dormant↔active + SLC/Visit 注册 + MotionGate 门控）| 单测：moving→active、stationary timeout→dormant |
| **P4** | `SessionSegmenter`（Eco 按天 / Daily·High 按 Visit 切段）+ `sessions.kind` + migration（含修 user_version bug）| 单测：分段逻辑 + migration 幂等 |
| **P5** | 接入 `RecordingManager` + 左菜单 `Toggle`（`RecordSettingsView`）+ Always/Motion 授权引导 + 常驻状态提示 | 模拟器 dogfood：开开关→后台→点出现 |
| **P6** | 查看兼容（History/DayDetail 显示自动分段）+ 措辞 sessions→行程（可选增强）| dogfood 截图：省电 1 段 / 普通多段正确显示 |
| **P7** | 真机 dogfood：电量对比 + 被杀唤醒 + 分段验收 | 两组电量数字 + 唤醒截图 |

## Review
- 实现：砚砚（缅因猫/gpt）。Review：opus 或第三只猫（**禁止 self-review**）。
- 门禁：worktree（基于 `main`）→ TDD → quality-gate → cross-review → merge-gate；真机 dogfood 电量/唤醒/分段查看截图作证据。

## Review & 验收进度（2026-07-10）

**实现**：砚砚（缅因猫/gpt），分支 `feat/f002-background-persistent-recording`（HEAD `229d4a6`）。

**Cross-review（opus/opus-4-8）**：
- 🔴 **P1（已修+复审通过）**：省电(eco)档被 SLC 唤醒重启后当天**重复开 ambient session**（违反"一天一段"AC-6）。根因：ambient day session"每 localDayKey 一个 open"不变量只在内存 segmenter、未落 DB restore。
  - 修复 `229d4a6`：新增 `TrackDatabase.startOrResumeAmbientDaySession`——`.day` origin 先查当天 open session（`kind=ambient AND origin=day AND local_day_key AND status=recording AND end_ts IS NULL`，`LIMIT 1` 处理脏数据），存在则恢复 `ActiveRecordingSession`（含 `lastAccepted`/`acceptedCount`/`distance`/`segmentID` 兜底），不再重复 INSERT。补测 `testDatabaseResumesOpenAmbientDaySession`。
  - 复审：opus 独立跑 `run-logic-tests.sh` → `FootprintLogicTests passed`。**通过**。
- 🟡 **P2（归 dogfood 校准，不阻塞代码 review）**：① trip 模式被杀重启切段；② `CLVisit` arrival/departure 未区分；③ `finishAmbientSession` 用 `nowMs()` 而非事件时间戳。真机行为确认后校准。

**Merge 前 pending（真机 dogfood，需 co-creator 真机）**：
- [ ] **AC-2**：开省电常驻 → 划掉 app → 走动 ≥500m → SLC 唤醒续记，**当天仍 1 段**（同时验证 P1 修复的真机行为）。
- [ ] **AC-5**：普通档通勤半天电量 vs 现有连续模式对比（两组数字）。

代码 review **通过**；真机 dogfood 完成后进 merge-gate。

### Dogfood 迭代（2026-07-14 ~ 07-16，opus 实现 + 砚砚 review）

co-creator 真机 dogfood 发现并修复一串问题（feat HEAD `d4935c0`）：
- `2999c62` 记录指示器（`isSampling` + `recordingIndicator`，解决"看不出在不在记"）
- `30988be` 开启常驻记起始点（`requestLocation`，站着不动也有起点）
- `e8be848` 常驻/手动 UI 分离（起始点让 `recording=true` 误触发手动录制 UI）
- `82edfe8` **MotionGate 放宽**（低置信运动→moving；旧逻辑一刀切丢弃低置信步行）+ 诊断 log
- `f84223b` 诊断日志文件双写 + app 内导出（co-creator 不能带连线 Xcode 行走）
- `36802ee` **CLVisit 不再 dormant**（诊断 log 铁证：步行时 iOS 误触发 visit 到达→dormant→停 GPS→app 挂起→整段步行丢失；坐车/地铁速度快不误报所以准）
- `d4935c0` review P1/P2 修复（坐标不进 public 统一日志用 `.private` redact + 诊断文件 1MB 轮转）

**步行记录丢失根因链（诊断 log 实证）**：① CLVisit 误触发 dormant（14ms / 76s start→stop 铁证）+ ② CMMotion 低置信步行被旧 MotionGate 丢弃。

**Review 闭环**：砚砚 cross-review → P1（精确坐标进 public 统一日志）/ P2（诊断文件无限增长）→ opus 修 `d4935c0` → 砚砚 **focused rereview 通过**。

**Merge 前 pending（真机，需 co-creator）**：
- [ ] rebuild `d4935c0` 真机重走**纯步行**路线 → 导出新 log 确认：步行段连续 `recorded point`、`⚑ CLVisit arrival` 出现但**不再中断采样**（不再 14ms/76s start→stop）。
- [ ] AC-5 电量对比（原 pending）。
