# Issue tracker: GitHub

Clear 的 Issues、PRD 和 Wayfinder 决策地图存放在 `Maidang1/clear` 的 GitHub Issues。

优先使用已连接的 GitHub 能力读取和修改 Issues；本地 Git 只用于解析当前分支和代码上下文。Pull Requests 不作为需求分流入口。

## Wayfinder

- 地图：优先使用 `wayfinder:map` 标签；连接器无法创建自定义标签时，使用现有 `enhancement` 标签，并在正文写入 `Wayfinder type: map`。
- 票据：优先使用 `wayfinder:research`、`wayfinder:prototype`、`wayfinder:grilling` 或 `wayfinder:task` 标签；不可用时，在正文写入对应的 `Wayfinder type`，并使用现有 `question` 或 `enhancement` 标签。
- 原生子 Issue 不可用时，在地图中使用任务列表，并在票据顶部写入 `Part of #<map>`。
- 原生依赖不可用时，在票据顶部使用 `Blocked by: #<issue>`。
- 票据在开始处理前必须先认领。
- 解决票据时记录答案、关闭票据，并把摘要链接追加到地图的 Decisions so far。
