---
feature_ids: [F003]
related_features: [F001, F002]
topics: [integration, region-lighting, award, map-overlay, branch-merge]
doc_kind: spec
created: 2026-07-22
---

# F003: Award 集成（F001 点亮 ⊕ F002 常驻 + 主界面显示点亮区域）

> Status: spec | Owner: 砚砚（缅因猫/gpt，实现）| Design: opus（布偶猫/opus-4-8）
> Evolved from: F001（点亮）+ F002（常驻记录）| Branch: 新集成分支（基于 `feat/f002`）

## Why

点亮（award）目前独立在 `feature/city-boundary-achievements`（F001），常驻记录在 `feat/f002`（F002），两者分离——在 F002 分支看不到 award。co-creator 决定（2026-07-22）**合并 award 功能**，并让用户在**常驻记录 + 主录制界面**直接看到点亮区域（未点亮轮廓 + 已点亮填色），不用切到单独的 award 页。

## What

1. **分支集成**：把 F001 点亮能力合入 F002（常驻）——两个 feature 在一个 app 里同时工作。
2. **主界面 award overlay**：主录制界面地图（`TrackMapView`）叠加 region 渲染——**未点亮=淡轮廓，已点亮=填色**。
3. **常驻联动点亮**：常驻记录产生的 `track_points` 自动喂 F001 的 `RegionMatcher` → 点亮（F001 消费 track_points，常驻的点也是 track_points，天然联动）。

## Current State / 集成复杂度（实测 diff）

| 分支 | 相对 main | 内容 |
|---|---|---|
| F001 `city` | 21 文件 / +3951 | Region*/ChinaGeo/RegionMatcher/RegionAchievement*/BundledRegionDataProvider/CityBoundaryCatalog + `Data/city_boundaries.geojson` + 改 ContentView/RecordView/RecordSettingsView/TrackDatabase/TrackMapView/footprintApp（**注意 city 还含 photo 代码**）|
| F002 `feat/f002` | 13 文件 / +1385 | CoreMotion/FootprintLog/MotionGate/PersistentLocationCoordinator/SessionSegmenter + 改 TrackModels/RecordingManager/TrackDatabase/DayDetailView/HistoryView/RecordSettingsView/RecordView |

**3 个冲突文件（两分支都改，需手动合并）**：
- `TrackDatabase.swift`（F001 +621 region 表 / F002 +228 kind/origin）— **最难**：两套 schema + migration，版本号要协调。
- `RecordView.swift`（F001 +292 award入口/photo/颜色 / F002 +137 指示器/常驻UI）— 合并两套 overlay。
- `RecordSettingsView.swift`（F001 +159 photo/award section / F002 +37 常驻开关/诊断）— 合并两套 section。

## 集成策略（给实现）

**基 = `feat/f002`（`d7e0c6d`，含最新常驻）**，把 F001 合进来：
1. **无冲突新文件**：直接从 `city` 取 `Models/Region*`、`Services/{ChinaGeo,RegionMatcher,BundledRegionDataProvider,CityBoundaryCatalog,RegionAchievement*}`、`Views/RegionAchievement*`、`Data/city_boundaries.geojson`、`scripts/verify-f001-*`。（photo 代码按需，co-creator 只要 award，可暂不带 photo）
2. **冲突文件手动合并**（保留双方能力）：
   - **TrackDatabase**：合并两套 migration——F002 的 `recording_sessions.kind/origin` + F001 的 `regions/region_geometries/region_hits/region_achievements/region_rtree` 表。**统一 user_version 序列**（F002 到 v2，F001 region 表挂 v3，或合并成一次迁移），保持"只升不降"。
   - **RecordView**：F002 的记录指示器 + 常驻 UI **叠加** F001 的 Awards 入口。
   - **RecordSettingsView**：F002 的常驻开关/诊断 section **叠加** F001 的 award/photo section。
   - **ContentView / footprintApp / TrackMapView**：取 F001 的 award route + region overlay 基建。
3. **主界面 award overlay（新）**：主录制界面 `TrackMapView` 叠加 region 渲染——复用 F001 `RegionAchievementMapView` 的 MapPolygon 渲染逻辑（未点亮 faint 轮廓 / 已点亮 cyan 填色）。加一个开关控制主界面是否显示点亮层（避免和轨迹混乱）。

## 分阶段实现计划（TDD 友好，逐阶段模拟器可验收）

| Phase | 内容 | 验收（模拟器）|
|---|---|---|
| **P1** | 分支集成：新文件 + 3 冲突文件手动合并，`xcodebuild` build 过，F001+F002 现有功能都不坏 | build succeeded + 常驻记录 + award 页各自仍工作 |
| **P2** | 主界面 award overlay：`TrackMapView` 叠加 region（未点亮轮廓 + 已点亮填色）+ 显示开关 | 模拟器截图：主界面地图看到区域轮廓/填色 |
| **P3** | 常驻联动点亮：常驻 track_points → RegionMatcher → 点亮；DEBUG seed 验证 | 模拟器：常驻记录点落入 region → 主界面该区域点亮 |

## Acceptance Criteria

- [ ] AC-1（集成）：F001 点亮 + F002 常驻在一个 build 里同时工作，现有功能无回归。
- [ ] AC-2（migration）：TrackDatabase 合并 schema，旧库幂等迁移、只升不降；region 表 + kind/origin 都在。
- [ ] AC-3（主界面显示）：主录制界面地图显示**未点亮区域轮廓** + **已点亮区域填色**。
- [ ] AC-4（常驻联动）：常驻记录的点命中 region → 点亮（provenance 可追溯）。
- [ ] AC-5（模拟器验收）：iPhone 模拟器截图证明主界面 award 显示 + 点亮工作（award/点亮可模拟器测，用 DEBUG seed）。

## Dependencies
- F001（`city`，点亮全套）+ F002（`feat/f002`，常驻，`d7e0c6d`）。
- F002 dogfood 实测由 co-creator 并行继续（不阻塞集成，但集成分支应基于 F002 最新）。

## Risk
- **TrackDatabase migration 合并**：两套 schema + 版本号，最易出错。必须幂等 + 只升不降 + 旧库不丢数据。
- **RecordView/Settings UI 合并**：两套 overlay/section 叠加，注意布局不打架。
- **主界面 overlay 性能**：region 多时主界面渲染压力（F001 已有 admin1 优化经验，复用）。
- **photo 代码**：city 含 photo，集成时明确带不带（co-creator 只要 award）。

## Open Questions
- **OQ-1**：主界面点亮层要不要开关？（避免和轨迹/照片点混乱）— 倾向加开关，默认开。
- **OQ-2**：TrackDatabase 两套 migration 合并成一次 v3，还是 v2(F002)→v3(F001) 顺序迁移？P1 定。

## Review
- 实现：砚砚（缅因猫/gpt）。Review：opus 或第三只猫（**禁止 self-review**）。
- 门禁：集成分支（基于 `feat/f002`）→ TDD → quality-gate → cross-review → merge-gate；**模拟器截图验收**（award/点亮可模拟器测）。

## 进度：集成 + 全球一级边界（2026-07-22 ~ 07-23）

### P1–P3 集成（`feat/f003-award-integration`，cross-review 通过）
`41f01ff` 集成 F001 点亮 ⊕ F002 常驻 + 主界面 overlay + 常驻联动点亮 → review 提 P1(catalog 每点重解析)/P2(死代码) → `97ac68b` 修（load-once 缓存）→ **rereview 通过**。migration v3 合并（region 表 + kind/origin，只升不降）、F002 零回归（字节级）、DEBUG seed release 干净。

### 全球一级边界扩展（`02d3cca`，cross-review 通过）
award 从"仅日本 47 admin1"扩到**全球一级行政区**。数据源 **Natural Earth Admin 1 10m v5.1.1**（public domain），简化 2%，`mapshaper@0.7.47` pin + VERSION 校验 + 产物写 provenance；日本保留 MLIT 47 都道府县。最终 4461 admin1 / 239 国家 / 4.4MB。

**🔴 中国政策 override（co-creator 决策 2026-07-23，opus flag）**：Natural Earth 是 de facto 边界，对中国画法不符官方立场 → 修正：**台湾** `TW-*` 21 县市折叠为一个中国 admin1 `CN-TW`（台湾省）；**藏南** `IN-AR` 从印度侧剔除、几何并入 `CN-XZ`（西藏），metadata 记 `sourceComponentRegionIds`。
> ⚠️ **合规注记（承接 F001）**：这是基于 Natural Earth 几何的 Footprint 中国政策 override，**非公开发布/上架所需的官方审图数据源**。个人自用 + 当前 dogfood 足够；**未来公开发布仍需单独合规轨**（compliant 数据源 + 审图号）。港澳(HK/MO)单列、南海诸岛未处理，同属公开前待办。

**性能修复（P1，和 F002 省电目标冲突）**：4482 region 每点全量重算 → 接上已建的 R*Tree 预筛（`loadRegionSpatialCandidateIds` 死代码激活）+ `provider.catalog()` 快照（消 O(n²)）+ matcher memoize（fingerprint gate）+ `RecordView` 按 10 点批量 reload（`AwardOverlayReloadPolicy` 治本触发门控）。

**Merge 前 pending**：F003 基于 `feat/f002`，merge 带 F002 → 等 co-creator F002 方案A 实机优化稳定后一起 merge。
