---
feature_ids: [F001]
related_features: []
topics: [map, geo, region-achievement, coordinate-system, point-in-polygon, mapkit]
doc_kind: spec
created: 2026-07-09
---

# F001: Region Lighting（城市点亮）

> Status: spec | Owner: 砚砚（缅因猫/gpt，实现）| Design: opus（布偶猫/opus-4-8）
> Branch: `feature/city-boundary-achievements`

## Why

把当前「10 个 starter 城市 + 中心 marker」的雏形（图 2），升级为「行政区 polygon 被整块系统性点亮」的能力（图 1）。
真正的缺口不是地图上色代码，而是三样：**稳定的行政区数据模型（region_id）、point-in-polygon 识别引擎、跨坐标系兼容的渲染**。

## What

用户走过的 GPS 轨迹，通过 point-in-polygon 命中行政区边界 → 点亮该 region → 地图上整块填色。

**已锁定的产品约束（来自 co-creator 决策，2026-07-09）：**
- **个人使用优先**，首发地点不重要。→ 不构成「向社会公开的互联网地图服务」，**不触发**中国地图审核 / ICP 备案 / 测绘资质 / 审图号义务（见 §Risk 的合规调研结论）。
- **兼容优先**：架构必须能同时在中国（GCJ-02 底图）和海外（WGS-84 底图）正确工作。
- **方案 C（hybrid）**：代码开源；数据源可插拔（region data pack）；坐标系抽象化。当下用统一 WGS-84 数据把复杂度降到最低，未来若要合规中国公开版，只加一个 GCJ-02 provider，不改架构。
- **V0 unlock 规则**：一个 accepted GPS 点落入 region 边界即点亮（存在即点亮）；50m 精度暂接受；置信度/防漂移放 V1。

## 核心决策（不可在实现中擅自更改，要改先回本文档）

1. **Canonical datum = WGS-84。** 轨迹点（CoreLocation 原始）与边界数据在 V0 **全部**以 WGS-84 存储与匹配。CLLocationCoordinate2D 官方定义即 WGS-84，且 iOS **未**在中国对 CLLocation 做 GCJ 预偏移（已一手核实，见 §Evidence）。
2. **GCJ-02 只是「渲染时的显示变换」**，不写回数据。仅当把叠加层画到中国大陆 MapKit 底图（Amap/GCJ-02）时，对坐标做 WGS-84→GCJ-02。海外为 identity。
3. **region_id 是主键**（如 `CN-440100` / `US-CA-SF` / `JP-13`），**不再**用 `cityKey`/name/alias 作为匹配核心。
4. **反向地理编码降级**为 debug/ fallback，**不作**主识别引擎。
5. **cell 网格降级**为 scan dedupe cursor，不代表城市。
6. **MapKit 保留**（Apple 在华走 Amap 合规底图、系统框架、不引入闭源第三方 SDK）。MapLibre/vector tiles 推迟到 V0 之后再评估，本 feature 不做。

## Acceptance Criteria

- [ ] AC-1（坐标层）：`wgs84ToGcj02` / `gcj02ToWgs84` round-trip 误差 < 1m；`isInsideChina` 对大陆/港澳/海外样例判定正确。
- [ ] AC-2（Catalog）：现有 10 个 starter 城市迁移到以 `region_id` 为主键的新 catalog；旧 achievement 能映射到 region_id；地图仍能显示。
- [ ] AC-3（Matcher）：给广州点返回 `CN-440100`；深圳点返回深圳 region_id；东京新宿点返回对应 region_id；**边界外点不误命中**；香港等 MultiPolygon 可命中。
- [ ] AC-4（增量）：同一地点多次记录不重复扫描 / 不重复点亮；重启后不重复点亮；新增轨迹只扫新增区域。
- [ ] AC-5（渲染）：多个已点亮城市**整块 cyan 填色**；未点亮默认不画或极淡边界；去掉「金色中心 marker 作为主点亮效果」；统计卡显示已点亮城市数。
- [ ] AC-6（兼容）：海外区域（WGS-84）与中国区域（渲染转 GCJ-02）都能画且与底图对齐（中国对齐需真机确认，见 OQ-1）。
- [ ] AC-7（provenance）：每次命中写 `region_hits`，可回答「这个城市为什么被点亮 / 首次何时 / 由哪个 point」。

## 架构（5 层）

```
① CoordinateTransform  兼容核心：identity(海外) / WGS↔GCJ(中国显示)
② RegionCatalog        region_id 主键 + datum 标签 + 可插拔 RegionDataProvider
③ RegionMatcher        R*Tree bbox 预筛 → point-in-polygon（统一 WGS-84 空间）
④ Storage              regions / region_geometries / region_hits / region_achievements / region_scan_cells
⑤ Renderer             MapKit MapPolygon + per-region 显示变换
```

### ① 坐标层（纯函数，零依赖，先写）
```swift
enum Datum { case wgs84, gcj02 }

enum ChinaGeo {
    static func isInsideChina(_ c: Coordinate) -> Bool      // 大陆 bbox + 排除港澳台的成熟判定
    static func wgs84ToGcj02(_ c: Coordinate) -> Coordinate // 前向精确算法
    static func gcj02ToWgs84(_ c: Coordinate) -> Coordinate // 迭代近似(~1m)
}

protocol CoordinateTransform { func forDisplay(_ c: Coordinate) -> Coordinate }
// OverseasTransform: identity
// ChinaDisplayTransform: isInsideChina ? wgs84ToGcj02 : identity
```

### ② 目录层
```swift
struct Region: Identifiable {
    let regionId: String        // 稳定 ID
    let level: RegionLevel      // country / admin1 / city / district
    let datum: Datum            // V0 统一 .wgs84
    let bbox: BBox              // WGS-84 canonical，进 R*Tree
    let parentId: String?
    let nameZh: String, nameEn: String, countryCode: String
}
protocol RegionDataProvider {
    func regions() throws -> [Region]
    func geometry(for id: String) throws -> [Polygon]   // WGS-84
}
// V0: BundledGeoJSONProvider(海外 + 中国都从 WGS-84 GeoJSON 出)
// 未来 C 合规轨: 追加 GCJProvider(datum=.gcj02)，架构不变
```

### ③ 检测层（替换反向地理编码）
```
未扫 cell(0.025°网格，scan cursor) → 代表点(WGS-84)
   ↓ R*Tree 查 bbox(point ± ε，padding 吸收误差)      [索引统一 WGS-84]
候选 region_ids
   ↓ point-in-polygon(point, geometry)                 [点与边界都 WGS-84，天然一致]
命中 region_id
   ↓ 写 region_hits + upsert region_achievements
```

### ④ 数据模型（SQLite；user_version 从 2 → 3，写 migration）
```sql
regions(region_id PK, level, datum, name_zh, name_en, country_code, parent_id,
        min_lat, max_lat, min_lng, max_lng);
region_geometries(region_id, polygon_index, coordinates_blob, datum,
        PRIMARY KEY(region_id, polygon_index));
region_hits(id PK AUTOINCREMENT, region_id, track_point_id, session_id, ts,
        lat, lng, hit_method);                              -- 新表：点亮 provenance
region_achievements(region_id PK, level, name, country_code, parent_id,
        first_seen_ts, last_seen_ts, visit_count, point_count, source);  -- 升级现有表
region_scan_cells(cell_key PK, scanned_at, matched_region_ids);          -- 原 cells 改造为游标
CREATE VIRTUAL TABLE region_rtree USING rtree(id, minLat, maxLat, minLng, maxLng);
```

### ⑤ 渲染层
```
for region in 视野内 regions:
    coords = geometry(region)                 // WGS-84
    coords = transform.forDisplay(coords)     // 中国→GCJ；海外→identity
    MapPolygon(coords).fill(unlocked ? cyan(0.5) : faint)
// 删除抖动圆圈兜底；金色中心 marker 仅用于 selected 态，不作主点亮效果
```

## 从现有代码迁移

| 保留 | 重构 |
|---|---|
| Awards 入口（ContentView route）| `RegionAchievementService.reverseGeocode` 主流程 → `RegionMatcher`（point-in-polygon）|
| `region_achievements`（升级 schema）| `cityKey`/alias 匹配 → `region_id` 主键 |
| cell 网格 SQL（改造为 scan cursor）| `RegionAchievementMapCity.generatedBoundaryCoordinates`（抖动圆圈）→ **删除** |
| `CityBoundaryCatalog` GeoJSON loader（泛化为 `RegionDataProvider`）| 新增坐标层 + `region_hits` 表 + R*Tree 索引 |
| `RegionAchievementMapView` MapPolygon 渲染骨架 | 金色 marker：主效果 → selected 标记 |

## 分阶段实现计划（TDD，逐阶段可验收）

| 阶段 | 内容 | 验收（先红后绿）|
|---|---|---|
| **P1** | 坐标层 `ChinaGeo` + `CoordinateTransform`（纯函数）| AC-1：round-trip <1m；isInsideChina 用例 |
| **P2** | `regions/region_geometries` schema + migration(v2→v3) + `RegionDataProvider` + 迁移 10 starter 城市到 region_id | AC-2 |
| **P3** | `RegionMatcher`：R*Tree bbox 预筛 + point-in-polygon（Polygon/MultiPolygon）| AC-3 |
| **P4** | 接入 sync 管线替换 geocode；cell 作 scan cursor；写 `region_hits` | AC-4 + AC-7 |
| **P5** | 渲染改造：区域显示变换 + cyan 整块填色 + 统计卡；删抖动圆圈 | AC-5 + AC-6(海外部分) |
| **P6** | 数据包：Overture/OSM 抽取 中国地级市 + 美/日，打 region_id，控制包体 | zoom out 见多城点亮 |

**P1 是最佳起点**：纯逻辑、隔离、零风险、TDD 最友好，先立兼容地基。

## Dependencies
- 现有 `TrackDatabase`（SQLite）、`track_points` 表、录制管线（保持不变，作为上游）。
- V0 数据包：Overture divisions / OSM 行政边界（WGS-84；个人使用许可允许）。

## Risk
- **合规**：个人自用**不触发**中国互联网地图审核/备案/资质（已一手核实：审核义务针对"向社会公开的互联网地图服务"，自然资办函〔2024〕972号）。**⚠️ 若未来转公开/上架，本约束失效**，需重走合规轨（compliant GCJ 数据包 + 审核 + 审图号 + 可能资质）——架构已为此预留 provider 抽象，但不在 V0 scope。
- **坐标对齐**：中国叠加层与 MapKit 底图对齐依赖 WGS→GCJ 显示变换；此为社区实测共识**非 Apple 官方**，须真机验证（OQ-1）。海外为 identity 无此风险。
- **数据许可**：Overture/OSM 个人使用 OK；一旦公开分发受 ODbL 署名/share-alike 约束——用 `DataProvenance` 单独记录来源许可，不默认套开源许可到数据文件。
- **连片城市误点亮**：广佛莞连片 + 50m 精度下边界附近可能误判；V0 接受，V1 加精度门限/驻留。

## Open Questions
- **OQ-1（blocker，仅影响中国显示对齐）**：真机（在华 iPhone）验证 WGS→GCJ 变换后叠加层是否与 MapKit 底图贴合。测法见 §Evidence。**不阻塞 P1–P4 与海外渲染。**
- **OQ-2**：Overture divisions → region_id 命名映射方案（P6 定；建议 `CN-<adcode>` / `US-<state>-<slug>` / `JP-<pref>`）。
- **OQ-3**：R*Tree 索引对含港澳台/海岛 MultiPolygon 的 bbox padding 取值（P3 定）。

## Implementation Notes（2026-07-09）

首批实现已锁定以下工程规则，后续 P2-P5 不应绕开：

- **SQLite migration**：不得继续在 `migrate()` 末尾无条件写 `PRAGMA user_version = 2`。P2 必须先读取 `user_version`，按 v0/v1/v2→v3 做幂等迁移；旧 `city_key` achievement 要通过 catalog alias 映射到 `region_id`，无法映射的 legacy row 保留为 fallback/debug，不静默删除。
- **R*Tree integer id**：SQLite R*Tree 主键使用 integer。`region_id` 仍是业务主键，但 storage 层要增加 `region_geometry_index(id INTEGER PRIMARY KEY, region_id, polygon_index)`，R*Tree 只存 integer id，再 join 回 `region_id`。
- **PIP policy**：V0 matcher 采用 `edgePolicy = inside`；外环边界点视为命中，内环 hole 里的点不命中。GeoJSON Polygon 的 holes 必须保留，不能只读取 outer ring。
- **真实点优先**：cell 只能作为 scan cursor/dedupe。P4 接入 sync 时，实际 point-in-polygon 应使用 cell 内真实 `track_points`（优先 accuracy 最好或 first accepted point），不要用 cell 平均代表点作为唯一点亮依据。
- **Accuracy policy**：现有 `daily/eco` accepted point 可能达到 200m/300m。V0 可先遵循“accepted 即可点亮”，但命中记录必须写入 `region_hits.accuracy` 或可追溯到 `track_points.accuracy`；V1 再按 accuracy/驻留时间收紧。
- **China display transform flag**：WGS→GCJ 只用于显示，不写回 DB。P5 接 MapKit 时必须保留可开关 display transform，直到 OQ-1 真机验证完成，避免在某些 MapKit 环境发生双重偏移。

## Evidence（一手来源，2026-07-09 调研）
- CLLocationCoordinate2D = WGS-84：Apple 官方文档（T0）。iOS 未对 CLLocation 做中国 GCJ 预偏移（社区实测反证 + Apple 论坛 787990 工程师回避坐标问题，T1/T2）。
- Apple Maps 中国用 Amap：apple.com/legal/privacy（T0）。
- 高德 district API 禁止缓存/打包/再分发（服务协议 3.5 / 4.12.7，T0）→ 不作数据源。
- 自然资源部标准地图只提供 JPG/EPS 非矢量；提取矢量+公开需送审（T0 地图管理条例 + T1 官方问答）→ 个人自用不涉及。
- 真机坐标测法：同一地点读 CLLocation 描 pin，对比系统蓝点；用已知地标的 WGS/GCJ 两个 pin 看哪个贴底图。

## Review
- 实现：砚砚（缅因猫/gpt）。Review：opus 或第三只猫（**禁止 self-review**）。
- 按 `docs/SOP.md`：worktree → TDD → quality-gate → cross-review → merge-gate。

## 进度日志（2026-07-09 · V0 交付）

### 已交付并合入 `feature/city-boundary-achievements`
- ✅ **P1 坐标层**：`ChinaGeo`（WGS↔GCJ 前向/迭代 + `isInsideChina`）、`CoordinateTransform`。
- ✅ **2 城 demo**：SF `US-CA-SF` + 新宿 `JP-13104`，region_id + point-in-polygon + MapKit 渲染 + DEBUG seed 点亮（`aa542e5`）。
- ✅ **Region catalog DB**：migration v3（幂等、无损）、`region_catalog_metadata` fingerprint gate（同 fingerprint 跳过重建）、`loadRegionCatalog` DB geometry readback、R*Tree（`region_geometry_index` integer id）。
- ✅ **東京都 admin1 整块点亮**：`JP-13` 单 region，渲染压力 62→1，in-memory matcher（删除 per-sample DB R*Tree 查询）。数据源：官方 **国土数値情報 N03 2024（CC BY 4.0）**，mapshaper dissolve/simplify（`399f71e`）。
- ✅ dogfood：iPhone 17 模拟器截图验收，co-creator 确认合理。

### 封存（git tag，待后续恢复）
- `f001-tokyo-ward-level-v1`（`b5526f5`）：東京都 62 市区町村精细版。恢复用于 ①「整块 vs 分区」切换开关；②区级精度 fix（细 cell 0.0025°）。

### 追踪 debt（cross-review 记录，非阻塞）
- **P4（重要）**：legacy `CLGeocoder` 成就路径仍在跑（设计决策 #4「反向地理编码降级」尚未落地），当前靠 `adminCoverageKeys` suppression band-aid 压其输出。应移除/降级为纯 debug fallback，让 `RegionMatcher` 成为唯一识别源。
- **区级精度**：per-sample DB 查询已删；细 cell（0.0025°/278m）封存在 tag，admin1 模式不需要。
- **远岛 bbox**：含小笠原的 region bbox 巨大 → in-memory 区级 bbox 预筛变弱；多 admin1 region 时应上 per-polygon in-memory 空间索引。
- **默认 focus**：当前硬编码东京本土；region 增多时改 data-driven（按选中 region 本土 bbox，排除远岛离群）。

### 进行中
- 全日本 47 都道府県 admin1：東京都（已亮）+ 其余 46 未点亮 faint 轮廓。
