---
topics: [backlog]
doc_kind: note
created: 2026-07-08
---

# Feature Roadmap

> **Rules**: Only active Features (idea/spec/in-progress/review). Move to done after completion.
> Details in `docs/features/Fxxx-*.md`.

| ID | Name | Status | Owner | Link |
|----|------|--------|-------|------|
| F001 | Region Lighting（城市点亮）| in-progress · 全日本 47 都道府県 admin1 已合入(`692e6e1`)：東京都点亮 + 其余 46 未点亮轮廓 | 砚砚（实现）/ opus（设计）| [F001](docs/features/F001-region-lighting.md) |
| F002 | Background Persistent Recording（后台常驻记录 + 三档省电）| spec · 立项 2026-07-10；三档（省电/普通/运行）省电引擎已设计，待 Design Gate | 砚砚（实现）/ opus（设计）| [F002](docs/features/F002-background-persistent-recording.md) |

## Parking Lot（已拍板/待议，未立项）

> co-creator 决策记录（2026-07-10），到点再走 feat-lifecycle 立项。

- **F003 候选 · 全球点亮 + 换色**（任务1，顺序第二）：全球 admin1；**换色**（点亮填色 + 边界描边色）；渲染/内存 = 重启 DB R*Tree + viewport 裁剪 + zoom LOD。
  - TODO：**admin2（中国地级市）先不做**，放本 todo，V0 只到 admin1。
- **F004 候选 · 行程导入：航班 + 高铁**（任务3，顺序第三，**暂搁置待议**）：导入用户真实行程渲染轨迹。已调研结论：12306/携程/飞猪无开放行程 API；航班走 BCBP 登机牌扫码（黄金路径），几何用 OpenFlights 大圆 / OSM 高铁线。
  - 已定：**先做手动输入 + 扫码**；**邮件解析可做**（之后讨论）；**不做短信解析**；先航班后高铁。
  - 待议：高铁几何保真度 / 是否引入付费第三方车次 API / 点亮交互（**不点亮或可选，优先级最低，2·1·3 完成后再议**）。
- **杂项**：根目录 `策略.md`（0 字节空文件，疑误建）待 co-creator 确认删除。
