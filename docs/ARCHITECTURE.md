---
topics: [architecture, code-structure, branches, navigation]
doc_kind: reference
created: 2026-07-10
---

# Footprint 代码结构 / 分支布局（真相源）

> **这个文件的家在 `main`**。任何人/猫 checkout `main` 读此文件即可看懂：代码怎么组织、有哪些分支、各干什么、哪个 feature 归哪个分支。
> **立项前先读这里**，避免把 feature 放错分支（教训：F002 一度被放进点亮分支）。

## 项目概览

`footprint` = **原生 SwiftUI iOS 足迹 app**。核心能力：GPS 轨迹记录 → 本地 SQLite 持久化 → 地图渲染 / 按天历史 / GPX 导出。之上叠加成就点亮（F001）、相册导入等 feature。
（`legacy-android` 分支是最早的 RN/Expo 安卓版，遗留保全，不再开发。）

## 分支布局（目前不合并，各自独立演进）

| 分支 | 职责 | 归属 feature | HEAD 参考 |
|---|---|---|---|
| **`main`** | **核心 GPS 记录**（录制/存储/查看/导出）—— 调试核心 checkout 这个 | 核心 + **F002**（后台常驻记录）| `core-gps-checkpoint-2026-07-07` |
| `feature/city-boundary-achievements` | 区域点亮成就 | **F001**（+ 候选 F003 全球点亮）| — |
| `feature/photo-location-import` | 相册照片位置导入 | 相册 feature | — |
| `legacy-android` | 最早 RN/Expo 安卓版（遗留） | — | — |

**不合并策略（co-creator 决策 2026-07-10）**：点亮 / 相册 / 核心 三分支暂不合并，各自独立。项目级真相源文档（本文件、`BACKLOG.md`、`docs/features/`）**以 `main` 为家**。

**Feature ↔ 分支归属规则**：新 feature 立项时，按"改哪块代码"决定分支——
- 改**核心录制/存储/查看** → 归 `main`（如 F002 后台常驻）。
- 改**点亮/成就** → 归 city 分支（如 F001、F003）。
- 改**相册** → 归 photo 分支。
- 跨核心+点亮（如未来行程导入 F004）→ 立项时在本文件登记归属。

## `main` 核心代码结构（16 Swift 文件）

```
footprint/
├── footprintApp.swift          App 入口（@main）
├── ContentView.swift           路由：record / history / dayDetail / achievements / achievementMap
├── Models/
│   └── TrackModels.swift        TrackPoint · RecordingProfile(High/Daily/Eco) · DaySummary · DaySession · ActiveRecordingSession
├── Services/
│   ├── RecordingManager.swift   录制核心：CLLocationManager 生命周期 · 前后台 · 授权 · session 管理
│   ├── LocationFilter.swift      点准入过滤：accuracy / 距离 / 间隔 / 跳变
│   ├── TrackDatabase.swift       SQLite：track_points / sessions / segments · 按天查询 · migration
│   └── GPXExporter.swift         GPX 1.1 导出（session / day）
├── Utilities/
│   └── Formatters.swift          时间/距离/日期格式化 · nowMs · localDayKey
└── Views/
    ├── RecordView.swift          主录制页（地图 + Start/Stop + 左上菜单入口）
    ├── RecordSettingsView.swift  左菜单设置（Recording 档位 / Map / Track / Export）← F002 常驻开关加这里
    ├── RecordComponents.swift    录制状态面板 / 低电模式视图
    ├── HistoryView.swift         历史（按天列表 DaySummary）
    ├── DayDetailView.swift       某天详情（地图 + Sessions 列表 SessionRow + 导出/删除）
    ├── TrackMapView.swift        MapKit 轨迹渲染
    ├── ColorControls.swift       RGBColor 编辑器（换色复用组件）
    └── ShareSheet.swift          分享
```

## 核心数据流

```
CLLocationManager → RecordingManager.handle()
   → LocationFilter.shouldAccept()  [accuracy/距离/间隔/跳变]
   → TrackDatabase.appendTrackPoint()  [SQLite: track_points, 带 session/segment/localDayKey]
        ↓ 查看                          ↓ 导出            ↓ (F001, city 分支) 消费轨迹点点亮区域
   HistoryView(按天) → DayDetailView   GPXExporter
```

**录制档位**：`RecordingProfile`（High/Daily/Eco）定义 `desiredAccuracy` + `distanceFilter` + 过滤阈值。F002 在此之上加"后台常驻 + 每档省电引擎"（详见 `docs/features/F002-*.md`）。

**查看模型（两层）**：History 按 `localDayKey` 聚合成 `DaySummary`（每天一卡）→ DayDetail 展示当天 `DaySession` 列表（`ForEach(sessions)` → `SessionRow`：时间段 + 档位 + 点数 + 距离）。**此结构天然支持一天多段**（F002 行程段分组直接复用，无需重构）。

## 分支增量速览（相对 main）

- **city（F001）**：新增 `Models/Region*` `Services/{ChinaGeo,RegionMatcher,BundledRegionDataProvider,CityBoundaryCatalog,RegionAchievement*}` `Views/RegionAchievement*` + `Data/city_boundaries.geojson`；`TrackDatabase` 加 region 表（+600 行）；`RecordView/RecordSettingsView` 加成就入口。
- **photo**：相册位置导入（`PhotoLocationExtractor` 等）。

## tags
- `core-gps-checkpoint-2026-07-07`：main 核心 checkpoint。
- `f001-tokyo-ward-level-v1`：F001 東京 62 区精细版封存。
