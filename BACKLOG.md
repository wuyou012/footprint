---
topics: [backlog]
doc_kind: note
created: 2026-07-08
---

# Feature Roadmap

> **家在 `main`**（项目级索引真相源）。分支布局见 `docs/ARCHITECTURE.md`。
> **Rules**: Only active Features (idea/spec/in-progress/review). Move to done after completion.
> Details in `docs/features/Fxxx-*.md`.

| ID | Name | Status | Branch | Owner | Link |
|----|------|--------|--------|-------|------|
| F001 | Region Lighting（城市点亮）| in-progress · 全日本 47 都道府県 admin1 已合入(`692e6e1`) | city | 砚砚（实现）/ opus（设计）| [F001](features/F001-region-lighting.md)¹ |
| F002 | Background Persistent Recording（后台常驻 + 三档省电）| spec · 立项 2026-07-10；三档参数+分组+分段查看已定，待 Design Gate | **main** | 砚砚（实现）/ opus（设计）| [F002](features/F002-background-persistent-recording.md) |

¹ F001 spec 文档在 `feature/city-boundary-achievements` 分支（点亮 feature 的家）。

## Parking Lot（已拍板/待议，未立项）

> co-creator 决策记录（2026-07-10），到点再走 feat-lifecycle 立项。

- **F003 候选 · 全球点亮 + 换色**（任务1，顺序第二，归 city 分支）：全球 admin1；换色（点亮填色 + 边界描边色）；渲染/内存 = 重启 DB R*Tree + viewport 裁剪 + zoom LOD。
  - TODO：**admin2（中国地级市）先不做**，V0 只到 admin1。
- **F004 候选 · 行程导入：航班 + 高铁**（任务3，顺序第三，**暂搁置待议**）：导入用户真实行程渲染轨迹。调研结论：12306/携程/飞猪无开放行程 API；航班走 BCBP 登机牌扫码，几何用 OpenFlights 大圆 / OSM 高铁线。
  - 已定：**先做手动输入 + 扫码**；**邮件解析可做**（之后讨论）；**不做短信**；先航班后高铁。
  - 待议：高铁几何保真 / 付费第三方车次 API / 点亮交互（**不点亮或可选，优先级最低，2·1·3 完成后再议**）。

## TODO（技术/杂项）

- **F002 OQ-2**：常驻模式 × 手动 Start 高精度录制如何切换/叠加（本 feature 暂不处理，倾向"手动 Start 临时提权 High，停止落回常驻档"）。
- **核心 migration bug**：`main` `TrackDatabase.migrate()` 无条件 `PRAGMA user_version=1`，跨分支切换降级共享 dev DB → 改"只升不降"（F002 碰核心时顺带修）。
- **仓库结构**：项目级 docs（本 BACKLOG / ARCHITECTURE / features）已收敛到 `main`；city 分支尚有历史 BACKLOG/docs 副本，以 `main` 为准，后续可清理。
- **根目录 `策略.md`**：0 字节空文件，疑误建，待 co-creator 确认删除。
